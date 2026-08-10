from pathlib import Path

APP = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaAcceptedApplicationEvidenceSealSourceTests.swift")

source = APP.read_text()


def replace_once(old: str, new: str, label: str) -> None:
    global source
    count = source.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one anchor, found {count}")
    source = source.replace(old, new, 1)


replace_once(
    "    private var driver: OfficialTuyaDriver?\n    private var events: [Event] = []\n    private var watchdog: Task<Void, Never>?\n",
    "    private var driver: OfficialTuyaDriver?\n    private var events: [Event] = []\n    private var sealedAcceptedEventPrefix: [Event]?\n    private var watchdog: Task<Void, Never>?\n",
    "sealed accepted event storage",
)

replace_once(
    "    var applicationUpdateCount: Int { ledgerSnapshot.applicationPayloadCount }\n    var correlationProgress: PassiveBluetoothPowerCycleObservationProgress? { correlationSession?.progress }\n",
    "    var applicationUpdateCount: Int { ledgerSnapshot.applicationPayloadCount }\n    private var acceptedApplicationEventCount: Int {\n        events.lazy.filter { $0.kind == \"tuya_application_update\" }.count\n    }\n    var correlationProgress: PassiveBluetoothPowerCycleObservationProgress? { correlationSession?.progress }\n",
    "accepted application event count",
)

replace_once(
    "            try await sessionLedger.recordApplicationUpdate(isNonEmpty: !update.isEmpty, for: token)\n            await refreshLedgerSnapshot()\n            log(\"tuya_application_update\", update.merging([\n                \"generation\": String(token.diagnosticGeneration)\n            ]) { current, _ in current })\n            message = \"Receiving same-generation scooter application data · \\(applicationUpdateCount) update(s). Canonical readiness still depends on the sealed observation horizon.\"\n",
    "            try await sessionLedger.recordApplicationUpdate(isNonEmpty: !update.isEmpty, for: token)\n            // Package admission happens first so rejected callbacks never enter accepted structured\n            // evidence. Once admitted, copy the sanitized values before this task suspends again.\n            log(\"tuya_application_update\", update.merging([\n                \"generation\": String(token.diagnosticGeneration)\n            ]) { current, _ in current })\n            await refreshLedgerSnapshot()\n            message = \"Receiving same-generation scooter application data · \\(applicationUpdateCount) update(s). Canonical readiness still depends on the sealed observation horizon.\"\n",
    "accepted structured application chronology",
)

replace_once(
    "                case .readyForStationaryMapping:\n                    guard self.buildIdentity.isAuthoritativeFieldBuild else {\n",
    "                case .readyForStationaryMapping:\n                    // A ledger mutation can finish while its MainActor callback is still suspended.\n                    // Never seal until every package-admitted application receipt has a matching\n                    // structured event in the app-owned evidence prefix.\n                    guard self.acceptedApplicationEventCount == self.applicationUpdateCount else {\n                        self.message = \"Synchronizing accepted application evidence before canonical seal…\"\n                        break\n                    }\n                    guard self.buildIdentity.isAuthoritativeFieldBuild else {\n",
    "seal evidence parity gate",
)

replace_once(
    "                        try await sessionLedger.sealAcceptedObservation(for: token)\n                        self.currentConnectionToken = nil\n",
    "                        try await sessionLedger.sealAcceptedObservation(for: token)\n                        // Freeze the app-exportable prefix synchronously after package seal and\n                        // before another suspension can admit post-seal diagnostic callbacks.\n                        self.sealedAcceptedEventPrefix = events\n                        self.currentConnectionToken = nil\n",
    "canonical accepted prefix freeze",
)

replace_once(
    "            candidates: candidates,\n            events: events\n        )\n",
    "            candidates: candidates,\n            events: sealedAcceptedEventPrefix ?? events\n        )\n",
    "export event source",
)

replace_once(
    "    private func resetDiscoverySessionOnly() {\n        correlationSession?.abandonCurrentWindow()\n",
    "    private func resetDiscoverySessionOnly() {\n        sealedAcceptedEventPrefix = nil\n        correlationSession?.abandonCurrentWindow()\n",
    "fresh capture reset",
)

APP.write_text(source)

TEST.write_text(r'''import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture accepted application evidence export seal")
struct TuyaAcceptedApplicationEvidenceSealSourceTests {
    @Test("successful package seal freezes app-exportable accepted evidence before another suspension point")
    func acceptanceSealFreezesExportPrefixSynchronously() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let watchdog = try section(
            in: app,
            from: "private func startWatchdog",
            to: "private func recordObservedTransportLoss"
        )
        let seal = try section(
            in: String(watchdog),
            from: "try await sessionLedger.sealAcceptedObservation(for: token)",
            to: "} catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed"
        )
        let body = String(seal)

        guard let packageSeal = body.range(of: "try await sessionLedger.sealAcceptedObservation(for: token)"),
              let frozenPrefix = body.range(of: "sealedAcceptedEventPrefix = events", range: packageSeal.upperBound..<body.endIndex) else {
            Issue.record("Successful package seal must synchronously snapshot the exportable accepted event prefix.")
            throw SourceContractError.sectionMissing
        }

        if let nextAwait = body.range(of: "await ", range: packageSeal.upperBound..<body.endIndex) {
            #expect(frozenPrefix.lowerBound < nextAwait.lowerBound)
        }
    }

    @Test("accepted export uses the frozen prefix instead of the mutable live event log")
    func acceptedExportUsesFrozenEventPrefix() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        #expect(app.contains("private var sealedAcceptedEventPrefix: [Event]?"))

        let export = try section(
            in: app,
            from: "func prepareExport()",
            to: "private func resetDiscoverySessionOnly"
        )
        let body = String(export)

        #expect(body.contains("events: sealedAcceptedEventPrefix"))
        #expect(!body.contains("events: events\n"))
    }

    @Test("starting a fresh correlation life clears the prior accepted export prefix")
    func freshCorrelationClearsPriorAcceptedPrefix() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let reset = try section(
            in: app,
            from: "private func resetDiscoverySessionOnly()",
            to: "private func failLocally"
        )

        #expect(reset.contains("sealedAcceptedEventPrefix = nil"))
    }

    @Test("accepted structured application values are copied before the callback suspends again")
    func acceptedApplicationValuesAreCopiedBeforeNextSuspension() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receive = try section(
            in: app,
            from: "private func receivedApplicationUpdate(",
            to: "private func startWatchdog"
        )
        let body = String(receive)

        guard let admission = body.range(of: "try await sessionLedger.recordApplicationUpdate(isNonEmpty: !update.isEmpty, for: token)"),
              let valueLog = body.range(of: "log(\"tuya_application_update\"", range: admission.upperBound..<body.endIndex),
              let nextAwait = body.range(of: "await ", range: admission.upperBound..<body.endIndex) else {
            Issue.record("Accepted application-value chronology anchors are missing.")
            throw SourceContractError.sectionMissing
        }

        #expect(valueLog.lowerBound < nextAwait.lowerBound)
    }

    @Test("canonical seal waits for app structured evidence to match package-admitted count")
    func canonicalSealRequiresStructuredEvidenceParity() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let watchdog = try section(
            in: app,
            from: "private func startWatchdog",
            to: "private func recordObservedTransportLoss"
        )
        let body = String(watchdog)

        guard let readyCase = body.range(of: "case .readyForStationaryMapping:"),
              let parity = body.range(of: "acceptedApplicationEventCount == self.applicationUpdateCount", range: readyCase.upperBound..<body.endIndex),
              let seal = body.range(of: "try await sessionLedger.sealAcceptedObservation(for: token)", range: readyCase.upperBound..<body.endIndex) else {
            Issue.record("Canonical seal must prove structured application evidence parity first.")
            throw SourceContractError.sectionMissing
        }

        #expect(parity.lowerBound < seal.lowerBound)
        #expect(app.contains("events.lazy.filter { $0.kind == \"tuya_application_update\" }.count"))
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

# Portable source-level assertions. Apple-framework compile/runtime remains the exact-head Xcode gate.
app = APP.read_text()
assert "private var sealedAcceptedEventPrefix: [Event]?" in app
assert "events: sealedAcceptedEventPrefix ?? events" in app
assert "events: events\n" not in app[app.index("func prepareExport()"):app.index("private func resetDiscoverySessionOnly")]
assert "sealedAcceptedEventPrefix = nil" in app[app.index("private func resetDiscoverySessionOnly"):app.index("private func failLocally")]

receive = app[app.index("private func receivedApplicationUpdate("):app.index("private func startWatchdog")]
admission = receive.index("try await sessionLedger.recordApplicationUpdate(isNonEmpty: !update.isEmpty, for: token)")
value_log = receive.index('log("tuya_application_update"', admission)
next_await = receive.index("await ", admission + len("try await sessionLedger.recordApplicationUpdate(isNonEmpty: !update.isEmpty, for: token)"))
assert value_log < next_await

watchdog = app[app.index("private func startWatchdog"):app.index("private func recordObservedTransportLoss")]
ready = watchdog.index("case .readyForStationaryMapping:")
parity = watchdog.index("acceptedApplicationEventCount == self.applicationUpdateCount", ready)
seal = watchdog.index("try await sessionLedger.sealAcceptedObservation(for: token)", ready)
assert parity < seal
frozen = watchdog.index("sealedAcceptedEventPrefix = events", seal)
next_seal_await = watchdog.index("await ", seal + len("try await sessionLedger.sealAcceptedObservation(for: token)"))
assert frozen < next_seal_await
