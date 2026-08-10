from pathlib import Path

APP = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaAcceptedApplicationEvidenceSealSourceTests.swift")

app = APP.read_text()


def replace_once(old: str, new: str, label: str) -> None:
    global app
    count = app.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one anchor, found {count}")
    app = app.replace(old, new, 1)


replace_once(
    "    private var acceptanceCutIsClosed = false\n    private var sealedAcceptedEventPrefix: [Event]?\n    private var watchdog: Task<Void, Never>?\n",
    "    private var acceptanceCutIsClosed = false\n    private var sealedAcceptedEventPrefix: [Event]?\n    private var sealedAcceptedExport: Export?\n    private var watchdog: Task<Void, Never>?\n",
    "sealed full-export storage",
)

replace_once(
    "        captureAttemptEventStartIndex = events.count\n        sealedAcceptedEventPrefix = nil\n\n        // Every physical attempt receives a fresh complete current-account membership verdict\n",
    "        captureAttemptEventStartIndex = events.count\n        sealedAcceptedEventPrefix = nil\n        sealedAcceptedExport = nil\n\n        // Every physical attempt receives a fresh complete current-account membership verdict\n",
    "fresh attempt clears sealed export",
)

replace_once(
    "                    let acceptedEventPrefixAtCut = Array(self.events.dropFirst(self.captureAttemptEventStartIndex))\n                    do {\n                        try await sessionLedger.sealAcceptedObservation(for: token)\n                        self.sealedAcceptedEventPrefix = acceptedEventPrefixAtCut\n",
    "                    let acceptedEventPrefixAtCut = Array(self.events.dropFirst(self.captureAttemptEventStartIndex))\n                    // Freeze the entire accepted envelope at the same pre-await cut as its event bytes.\n                    // Publication waits for package seal success, but later account/logout/UI changes can\n                    // no longer rewrite accepted provenance at share time.\n                    let acceptedExportAtCut = self.makeExport(\n                        events: acceptedEventPrefixAtCut,\n                        phase: .accepted,\n                        exportedAt: Date()\n                    )\n                    do {\n                        try await sessionLedger.sealAcceptedObservation(for: token)\n                        self.sealedAcceptedEventPrefix = acceptedEventPrefixAtCut\n                        self.sealedAcceptedExport = acceptedExportAtCut\n",
    "full envelope frozen before package seal suspension",
)

start = app.index("    func prepareExport() {")
end = app.index("    private func resetDiscoverySessionOnly() {", start)
old_export_region = app[start:end]
new_export_region = '''    private func makeExport(events: [Event], phase: Phase, exportedAt: Date) -> Export {
        Export(
            schemaVersion: 8,
            purpose: "Sanitized Tuya authenticated read-only stationary preflight",
            exportedAt: exportedAt,
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

    func prepareExport() {
        let envelope: Export
        if phase == .accepted {
            guard let acceptedEnvelope = self.sealedAcceptedExport else {
                exportData = nil
                message = "Accepted diagnostics cannot be exported because the immutable accepted envelope is unavailable. Restart from OFF1 rather than rebuilding accepted provenance from mutable live state."
                return
            }
            envelope = acceptedEnvelope
        } else {
            envelope = makeExport(events: events, phase: phase, exportedAt: Date())
        }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            encoder.dateEncodingStrategy = .iso8601
            exportData = try encoder.encode(envelope)
            exportName = "Nembra-Secure-Link-\\(deviceID.prefix(8))-Diagnostics.json"
            message = phase == .accepted
                ? "Immutable accepted diagnostics are ready exactly as frozen at the canonical seal cut. No later account, lifecycle, or callback state was re-read for accepted provenance."
                : "Sanitized diagnostics ready with exact compiled build provenance. No account UID, AppKey/AppSecret, password, account token, local_key, session key, raw FD50 claim, DP query, or DP command is exported."
        } catch {
            exportData = nil
            message = "Diagnostic export failed: \\(error.localizedDescription)"
        }
    }

'''
app = app[:start] + new_export_region + app[end:]

replace_once(
    "    private func resetDiscoverySessionOnly() {\n        acceptanceCutIsClosed = false\n        sealedAcceptedEventPrefix = nil\n",
    "    private func resetDiscoverySessionOnly() {\n        acceptanceCutIsClosed = false\n        sealedAcceptedEventPrefix = nil\n        sealedAcceptedExport = nil\n",
    "reset clears sealed full envelope",
)

APP.write_text(app)

tests = TEST.read_text()
old_test = '''    @Test("accepted export fails closed onto the frozen prefix instead of the mutable live event log")
    func acceptedExportUsesFrozenEventPrefix() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        #expect(app.contains("private var sealedAcceptedEventPrefix: [Event]?"))
        #expect(app.contains("private var applicationUpdateAdmissionsInFlight = 0"))
        #expect(app.contains("private var acceptanceCutIsClosed = false"))

        let export = try section(in: app, from: "func prepareExport()", to: "private func resetDiscoverySessionOnly")
        let body = String(export)

        #expect(body.contains("if phase == .accepted"))
        #expect(body.contains("guard let acceptedEventPrefix = self.sealedAcceptedEventPrefix"))
        #expect(body.contains("sealedAcceptedEventPrefix = acceptedEventPrefix"))
        #expect(body.contains("events: sealedAcceptedEventPrefix"))
        #expect(!body.contains("events: events\\n"))
    }
'''
new_test = '''    @Test("accepted export uses the fully frozen envelope instead of rebuilding from mutable live state")
    func acceptedExportUsesFrozenEnvelope() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        #expect(app.contains("private var sealedAcceptedEventPrefix: [Event]?"))
        #expect(app.contains("private var sealedAcceptedExport: Export?"))
        #expect(app.contains("private var applicationUpdateAdmissionsInFlight = 0"))
        #expect(app.contains("private var acceptanceCutIsClosed = false"))

        let export = try section(in: app, from: "func prepareExport()", to: "private func resetDiscoverySessionOnly")
        let body = String(export)

        #expect(body.contains("if phase == .accepted"))
        #expect(body.contains("guard let acceptedEnvelope = self.sealedAcceptedExport"))
        #expect(body.contains("envelope = acceptedEnvelope"))
        #expect(body.contains("envelope = makeExport(events: events, phase: phase, exportedAt: Date())"))
        #expect(!body.contains("guard let acceptedEventPrefix = self.sealedAcceptedEventPrefix"))
    }
'''
if tests.count(old_test) != 1:
    raise SystemExit("accepted export test anchor changed")
tests = tests.replace(old_test, new_test, 1)

old_reset_expect = '''        #expect(reset.contains("acceptanceCutIsClosed = false"))
        #expect(reset.contains("sealedAcceptedEventPrefix = nil"))
'''
new_reset_expect = '''        #expect(reset.contains("acceptanceCutIsClosed = false"))
        #expect(reset.contains("sealedAcceptedEventPrefix = nil"))
        #expect(reset.contains("sealedAcceptedExport = nil"))
'''
if tests.count(old_reset_expect) != 1:
    raise SystemExit("fresh reset expectations changed")
tests = tests.replace(old_reset_expect, new_reset_expect, 1)

anchor = "\n    @Test(\"application callbacks cannot cross the acceptance cut and in-flight admissions remain owned until async ledger work finishes\")\n"
if tests.count(anchor) != 1:
    raise SystemExit("source-test insertion anchor changed")
addition = r'''
    @Test("the full accepted envelope is frozen before package seal suspension and published only after seal succeeds")
    func fullAcceptedEnvelopeSharesTheImmutableSealCut() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let watchdog = try section(in: app, from: "private func startWatchdog", to: "private func recordObservedTransportLoss")
        let body = String(watchdog)

        guard let eventCut = body.range(of: "let acceptedEventPrefixAtCut = Array(self.events.dropFirst(self.captureAttemptEventStartIndex))"),
              let envelopeCut = body.range(of: "let acceptedExportAtCut = self.makeExport(", range: eventCut.upperBound..<body.endIndex),
              let acceptedPhase = body.range(of: "phase: .accepted", range: envelopeCut.upperBound..<body.endIndex),
              let packageSeal = body.range(of: "try await sessionLedger.sealAcceptedObservation(for: token)", range: acceptedPhase.upperBound..<body.endIndex),
              let publish = body.range(of: "self.sealedAcceptedExport = acceptedExportAtCut", range: packageSeal.upperBound..<body.endIndex) else {
            Issue.record("Canonical acceptance must freeze the whole accepted envelope at the pre-await cut and publish it only after package seal succeeds.")
            throw SourceContractError.sectionMissing
        }

        #expect(eventCut.lowerBound < envelopeCut.lowerBound)
        #expect(envelopeCut.lowerBound < acceptedPhase.lowerBound)
        #expect(acceptedPhase.lowerBound < packageSeal.lowerBound)
        #expect(packageSeal.lowerBound < publish.lowerBound)
    }

'''
tests = tests.replace(anchor, "\n" + addition + anchor, 1)
TEST.write_text(tests)

# Portable source invariants. Real Apple-framework compile/test remains exact-head Xcode acceptance.
app = APP.read_text()
assert "private var sealedAcceptedExport: Export?" in app
watchdog = app[app.index("private func startWatchdog"):app.index("private func recordObservedTransportLoss")]
event_cut = watchdog.index("let acceptedEventPrefixAtCut = Array(self.events.dropFirst(self.captureAttemptEventStartIndex))")
envelope_cut = watchdog.index("let acceptedExportAtCut = self.makeExport(", event_cut)
package_seal = watchdog.index("try await sessionLedger.sealAcceptedObservation(for: token)", envelope_cut)
publish = watchdog.index("self.sealedAcceptedExport = acceptedExportAtCut", package_seal)
assert event_cut < envelope_cut < package_seal < publish
export = app[app.index("func prepareExport()"):app.index("private func resetDiscoverySessionOnly")]
assert "guard let acceptedEnvelope = self.sealedAcceptedExport" in export
assert "envelope = acceptedEnvelope" in export
assert "envelope = makeExport(events: events, phase: phase, exportedAt: Date())" in export
assert "guard let acceptedEventPrefix = self.sealedAcceptedEventPrefix" not in export
reset = app[app.index("private func resetDiscoverySessionOnly"):app.index("private func failLocally")]
assert "sealedAcceptedExport = nil" in reset
start = app[app.index("func startBaseline()"):app.index("private func beginCorrelationSeries")]
assert "sealedAcceptedExport = nil" in start
assert "func consumeCorrelationAsyncInvalidation()" in app
