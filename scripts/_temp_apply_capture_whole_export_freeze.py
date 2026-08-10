from pathlib import Path

app_path = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
app = app_path.read_text()

# 1) Retain one whole accepted envelope alongside the already-frozen event prefix.
old = "    private var acceptanceCutIsClosed = false\n    private var sealedAcceptedEventPrefix: [Event]?\n    private var watchdog: Task<Void, Never>?"
new = "    private var acceptanceCutIsClosed = false\n    private var sealedAcceptedEventPrefix: [Event]?\n    private var sealedAcceptedExport: Export?\n    private var watchdog: Task<Void, Never>?"
if app.count(old) != 1:
    raise SystemExit(f"accepted-state insertion count={app.count(old)}")
app = app.replace(old, new, 1)

# 2) A fresh physical attempt cannot retain a prior accepted artifact.
old = "        captureAttemptEventStartIndex = events.count\n        sealedAcceptedEventPrefix = nil\n"
new = "        captureAttemptEventStartIndex = events.count\n        sealedAcceptedEventPrefix = nil\n        sealedAcceptedExport = nil\n"
if app.count(old) != 1:
    raise SystemExit(f"fresh-attempt reset count={app.count(old)}")
app = app.replace(old, new, 1)

# 3) Freeze the complete envelope immediately after the package seal succeeds, before any await/UI acceptance.
old = "                        try await sessionLedger.sealAcceptedObservation(for: token)\n                        self.sealedAcceptedEventPrefix = acceptedEventPrefixAtCut\n                        self.currentConnectionToken = nil\n                        await self.refreshLedgerSnapshot()\n                        self.phase = .accepted"
new = "                        try await sessionLedger.sealAcceptedObservation(for: token)\n                        self.sealedAcceptedExport = self.makeExport(\n                            phase: .accepted,\n                            events: acceptedEventPrefixAtCut\n                        )\n                        self.sealedAcceptedEventPrefix = acceptedEventPrefixAtCut\n                        self.currentConnectionToken = nil\n                        await self.refreshLedgerSnapshot()\n                        self.phase = .accepted"
if app.count(old) != 1:
    raise SystemExit(f"post-seal freeze count={app.count(old)}")
app = app.replace(old, new, 1)

# 4) Accepted Share uses only the immutable whole envelope. Diagnostics may still snapshot mutable failed/in-progress state.
start = app.index("    func prepareExport() {")
end = app.index("    private func resetDiscoverySessionOnly()", start)
old_prepare = app[start:end]
new_prepare = r'''    func prepareExport() {
        let envelope: Export
        if phase == .accepted {
            guard let sealedAcceptedExport else {
                exportData = nil
                message = "Accepted diagnostics cannot be exported because the immutable accepted artifact is unavailable. Restart from OFF1 rather than exporting mutable post-seal diagnostics."
                return
            }
            envelope = sealedAcceptedExport
        } else {
            envelope = makeExport(phase: phase, events: events)
        }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            encoder.dateEncodingStrategy = .iso8601
            exportData = try encoder.encode(envelope)
            exportName = "Nembra-Secure-Link-\(deviceID.prefix(8))-Diagnostics.json"
            message = "Sanitized diagnostics ready with exact compiled build provenance. No account UID, AppKey/AppSecret, password, account token, local_key, session key, raw FD50 claim, DP query, or DP command is exported."
        } catch {
            message = "Diagnostic export failed: \(error.localizedDescription)"
        }
    }

    private func makeExport(phase: Phase, events: [Event]) -> Export {
        Export(
            schemaVersion: 8,
            purpose: "Sanitized Tuya authenticated read-only stationary preflight",
            exportedAt: Date(),
            buildIdentifier: buildIdentity.buildIdentifier,
            sourceCommitSHA: buildIdentity.sourceCommitSHA,
            tuyaDeviceID: deviceID,
            tuyaUUID: tuyaUUID,
            productID: productID,
            selectedPeripheralID: selectedID?.uuidString,
            targetCorrelationMethod: targetCorrelationMethod,
            targetCorrelationWindowCount: targetCorrelationWindowCount,
            targetCorrelationOperatorConfirmed: targetCorrelationOperatorConfirmed,
            targetCorrelationProvenance: correlationProvenance,
            phase: phase,
            privateConfigPresent: privateConfig,
            sdkAccountLoggedIn: sdkAccountLoggedIn,
            sdkDeviceMembershipVerified: sdkDeviceMembershipVerified,
            secureSessionEstablished: secureSessionEstablished,
            canonicalObservedAgeSeconds: canonicalObservedAgeSeconds,
            sdkLocalBLEOnline: sdkLocalBLEOnline,
            applicationUpdateCount: applicationUpdateCount,
            connectionGeneration: ledgerSnapshot.connectionGeneration,
            authenticationMethod: ledgerSnapshot.authenticationMethod?.rawValue,
            preflightVerdict: preflightVerdictText,
            applicationValueRepresentation: "ThingSmartDeviceDelegate dpsUpdate values projected with String(describing:); application-level SDK data, not byte-exact or raw FD50 transport",
            rawFD50BytesCaptured: false,
            secretsRedacted: true,
            dpQueriesSent: false,
            dpCommandsSent: false,
            candidates: candidates,
            events: events
        )
    }

'''
app = app[:start] + new_prepare + app[end:]

# 5) Generic discovery reset also clears accepted whole-artifact custody.
old = "    private func resetDiscoverySessionOnly() {\n        acceptanceCutIsClosed = false\n        sealedAcceptedEventPrefix = nil\n"
new = "    private func resetDiscoverySessionOnly() {\n        acceptanceCutIsClosed = false\n        sealedAcceptedEventPrefix = nil\n        sealedAcceptedExport = nil\n"
if app.count(old) != 1:
    raise SystemExit(f"discovery-reset insertion count={app.count(old)}")
app = app.replace(old, new, 1)

required = [
    "private var sealedAcceptedExport: Export?",
    "self.sealedAcceptedExport = self.makeExport(",
    "phase: .accepted",
    "events: acceptedEventPrefixAtCut",
    "if phase == .accepted",
    "guard let sealedAcceptedExport",
    "envelope = sealedAcceptedExport",
    "envelope = makeExport(phase: phase, events: events)",
    "sealedAcceptedExport = nil",
]
for token in required:
    if token not in app:
        raise SystemExit(f"missing repaired contract token: {token}")

# Mechanical no-suspension proof between package seal return and whole-envelope freeze.
seal = app.index("try await sessionLedger.sealAcceptedObservation(for: token)")
freeze = app.index("self.sealedAcceptedExport = self.makeExport(", seal)
if "await " in app[seal + len("try await sessionLedger.sealAcceptedObservation(for: token)"):freeze]:
    raise SystemExit("actor suspension found between package seal and whole-envelope freeze")

# Accepted prepare branch must not reconstruct mutable authority.
prepare_start = app.index("func prepareExport()")
accepted = app.index("if phase == .accepted", prepare_start)
mutable = app.index("else", accepted)
accepted_body = app[accepted:mutable]
for forbidden in ["Date()", "buildIdentity.", "sdkAccountLoggedIn", "sdkDeviceMembershipVerified", "sdkLocalBLEOnline", "ledgerSnapshot", "candidates"]:
    if forbidden in accepted_body:
        raise SystemExit(f"accepted Share still reads mutable authority: {forbidden}")

app_path.write_text(app)

# Re-anchor the exact expected-red source contract onto the live product branch.
test_path = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaWholeAcceptedExportArtifactImmutabilitySourceTests.swift")
test_path.write_text(r'''import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture whole accepted export artifact immutability")
struct TuyaWholeAcceptedExportArtifactImmutabilitySourceTests {
    @Test("accepted Share must use one fully frozen envelope instead of rebuilding from live state")
    func acceptedShareCannotRebuildAcceptedEnvelope() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        #expect(app.contains("private var sealedAcceptedExport: Export?"))

        let prepare = try section(
            in: app,
            from: "func prepareExport()",
            to: "private func resetDiscoverySessionOnly"
        )
        let body = String(prepare)

        #expect(body.contains("if phase == .accepted"))
        #expect(body.contains("guard let sealedAcceptedExport"))
        #expect(body.contains("envelope = sealedAcceptedExport"))

        guard let acceptedBranch = body.range(of: "if phase == .accepted"),
              let mutableBranch = body.range(of: "else", range: acceptedBranch.upperBound..<body.endIndex) else {
            Issue.record("prepareExport must separate accepted immutable export from mutable diagnostic export")
            throw SourceContractError.sectionMissing
        }
        let acceptedBody = body[acceptedBranch.lowerBound..<mutableBranch.lowerBound]
        #expect(!acceptedBody.contains("Date()"))
        #expect(!acceptedBody.contains("buildIdentity."))
        #expect(!acceptedBody.contains("sdkAccountLoggedIn"))
        #expect(!acceptedBody.contains("sdkDeviceMembershipVerified"))
        #expect(!acceptedBody.contains("sdkLocalBLEOnline"))
        #expect(!acceptedBody.contains("ledgerSnapshot"))
        #expect(!acceptedBody.contains("candidates"))
    }

    @Test("whole accepted envelope must freeze after package seal and before accepted UI")
    func canonicalSealFreezesWholeEnvelopeBeforeAcceptedPhase() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let watchdog = try section(
            in: app,
            from: "private func startWatchdog",
            to: "private func recordObservedTransportLoss"
        )
        let body = String(watchdog)

        guard let packageSeal = body.range(of: "try await sessionLedger.sealAcceptedObservation(for: token)"),
              let envelopeFreeze = body.range(of: "self.sealedAcceptedExport = self.makeExport(", range: packageSeal.upperBound..<body.endIndex),
              let acceptedPhase = body.range(of: "self.phase = .accepted", range: envelopeFreeze.upperBound..<body.endIndex) else {
            Issue.record("Successful package seal must freeze the complete accepted Export before presenting accepted UI")
            throw SourceContractError.sectionMissing
        }

        #expect(packageSeal.lowerBound < envelopeFreeze.lowerBound)
        #expect(envelopeFreeze.lowerBound < acceptedPhase.lowerBound)

        let between = body[packageSeal.upperBound..<envelopeFreeze.lowerBound]
        #expect(!between.contains("await "), Comment(rawValue: "Mutable authority must not suspend between package seal and complete accepted-envelope freeze."))
        #expect(body.contains("phase: .accepted"))
        #expect(body.contains("events: acceptedEventPrefixAtCut"))
    }

    @Test("fresh attempt clears the prior whole accepted artifact")
    func freshAttemptClearsWholeAcceptedArtifact() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let start = try section(
            in: app,
            from: "func startBaseline()",
            to: "private func beginCorrelationSeries"
        )
        let reset = try section(
            in: app,
            from: "private func resetDiscoverySessionOnly()",
            to: "private func failLocally"
        )

        #expect(start.contains("sealedAcceptedExport = nil") || reset.contains("sealedAcceptedExport = nil"))
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let startRange = source.range(of: start),
              let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \(start) ... \(end)")
            throw SourceContractError.sectionMissing
        }
        return source[startRange.lowerBound..<endRange.lowerBound]
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private enum SourceContractError: Error {
        case sectionMissing
    }
}
''')
