from pathlib import Path

APP = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaAcceptedApplicationSealCustodySourceTests.swift")

source = APP.read_text()


def replace_once(old: str, new: str, label: str) -> None:
    global source
    count = source.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one anchor, found {count}")
    source = source.replace(old, new, 1)


replace_once(
    "    private var driver: OfficialTuyaDriver?\n    private var events: [Event] = []\n    private var sealedAcceptedEventPrefix: [Event]?\n    private var watchdog: Task<Void, Never>?\n",
    "    private var driver: OfficialTuyaDriver?\n    private var events: [Event] = []\n    private var captureAttemptEventStartIndex = 0\n    private var sealedAcceptedEventPrefix: [Event]?\n    private var applicationAdmissionInFlightCount = 0\n    private var acceptanceSealInProgress = false\n    private var watchdog: Task<Void, Never>?\n",
    "application evidence custody storage",
)

replace_once(
    "    var applicationUpdateCount: Int { ledgerSnapshot.applicationPayloadCount }\n    var correlationProgress: PassiveBluetoothPowerCycleObservationProgress? { correlationSession?.progress }\n",
    "    var applicationUpdateCount: Int { ledgerSnapshot.applicationPayloadCount }\n    private func acceptedApplicationEventCount(for token: TuyaReadOnlyConnectionToken) -> Int {\n        let generation = String(token.diagnosticGeneration)\n        return events.lazy.filter {\n            $0.kind == \"tuya_application_update\" && $0.details[\"generation\"] == generation\n        }.count\n    }\n    var correlationProgress: PassiveBluetoothPowerCycleObservationProgress? { correlationSession?.progress }\n",
    "current-generation structured evidence counter",
)

replace_once(
    "        // Every physical attempt receives a fresh complete current-account membership verdict\n        // before the package-owned four-window Bluetooth correlation series may start.\n        verifySDKMembership { [weak self] authorized in\n",
    "        // Start a new app-owned evidence lifetime before fresh membership verification. Accepted\n        // export must never inherit diagnostic/application events from an older failed attempt.\n        captureAttemptEventStartIndex = events.count\n        sealedAcceptedEventPrefix = nil\n\n        // Every physical attempt receives a fresh complete current-account membership verdict\n        // before the package-owned four-window Bluetooth correlation series may start.\n        verifySDKMembership { [weak self] authorized in\n",
    "current-attempt event boundary",
)

replace_once(
    "        guard driver.isLocallyConnected(uuid: tuyaUUID) else {\n            await recordObservedTransportLoss(token: token)\n            return\n        }\n\n        do {\n            try await sessionLedger.recordApplicationUpdate(isNonEmpty: !update.isEmpty, for: token)\n            await refreshLedgerSnapshot()\n            log(\"tuya_application_update\", update.merging([\n                \"generation\": String(token.diagnosticGeneration)\n            ]) { current, _ in current })\n",
    "        guard driver.isLocallyConnected(uuid: tuyaUUID) else {\n            await recordObservedTransportLoss(token: token)\n            return\n        }\n        guard !acceptanceSealInProgress else {\n            log(\"application_update_during_acceptance_seal_ignored\", [\n                \"generation\": String(token.diagnosticGeneration)\n            ])\n            return\n        }\n\n        // MainActor serialization makes guard + increment atomic with the watchdog. Keep this\n        // non-zero across actor suspension so sealing cannot overtake an admitted receipt whose\n        // structured values are not yet settled into app-owned evidence.\n        applicationAdmissionInFlightCount += 1\n        defer { applicationAdmissionInFlightCount -= 1 }\n\n        do {\n            try await sessionLedger.recordApplicationUpdate(isNonEmpty: !update.isEmpty, for: token)\n            // Only package-admitted values become structured evidence. Once admitted, copy them\n            // before this MainActor task suspends again.\n            log(\"tuya_application_update\", update.merging([\n                \"generation\": String(token.diagnosticGeneration)\n            ]) { current, _ in current })\n            await refreshLedgerSnapshot()\n",
    "application admission chronology + seal latch",
)

replace_once(
    "                case .readyForStationaryMapping:\n                    guard self.buildIdentity.isAuthoritativeFieldBuild else {\n",
    "                case .readyForStationaryMapping:\n                    // A package mutation can finish while its MainActor callback is still suspended.\n                    // Seal only after every in-flight admission has settled and this generation's\n                    // structured event count exactly matches package-owned admitted chronology.\n                    guard self.applicationAdmissionInFlightCount == 0 else {\n                        self.message = \"Settling accepted application evidence before canonical seal…\"\n                        break\n                    }\n                    guard self.acceptedApplicationEventCount(for: token) == self.applicationUpdateCount else {\n                        self.message = \"Synchronizing accepted application evidence before canonical seal…\"\n                        break\n                    }\n                    guard self.buildIdentity.isAuthoritativeFieldBuild else {\n",
    "pre-seal structured evidence parity",
)

replace_once(
    "                    do {\n                        try await sessionLedger.sealAcceptedObservation(for: token)\n                        self.sealedAcceptedEventPrefix = self.events\n",
    "                    // Close new application admission synchronously on MainActor, then snapshot\n                    // this physical attempt before the package-seal suspension. Diagnostic callbacks\n                    // during sealing can remain visible live but cannot enter accepted evidence.\n                    self.acceptanceSealInProgress = true\n                    let eventsAtSealBarrier = Array(self.events.dropFirst(self.captureAttemptEventStartIndex))\n                    do {\n                        try await sessionLedger.sealAcceptedObservation(for: token)\n                        self.sealedAcceptedEventPrefix = eventsAtSealBarrier\n",
    "pre-suspension immutable seal barrier",
)

replace_once(
    "    private func resetDiscoverySessionOnly() {\n        sealedAcceptedEventPrefix = nil\n",
    "    private func resetDiscoverySessionOnly() {\n        sealedAcceptedEventPrefix = nil\n        acceptanceSealInProgress = false\n",
    "fresh-life seal latch reset",
)

APP.write_text(source)

TEST.write_text(r'''import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture accepted application seal custody")
struct TuyaAcceptedApplicationSealCustodySourceTests {
    @Test("package-admitted structured values settle before the callback suspends again")
    func admittedValuesSettleBeforeNextSuspension() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receive = try section(in: app, from: "private func receivedApplicationUpdate(", to: "private func startWatchdog")
        let body = String(receive)

        guard let admission = body.range(of: "try await sessionLedger.recordApplicationUpdate(isNonEmpty: !update.isEmpty, for: token)"),
              let valueLog = body.range(of: "log(\"tuya_application_update\"", range: admission.upperBound..<body.endIndex),
              let nextAwait = body.range(of: "await ", range: admission.upperBound..<body.endIndex) else {
            Issue.record("Accepted application-value chronology anchors are missing.")
            throw SourceContractError.sectionMissing
        }
        #expect(valueLog.lowerBound < nextAwait.lowerBound)
    }

    @Test("canonical seal closes admission and proves current-generation parity")
    func sealFencesInFlightAdmissionAndRequiresParity() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receive = try section(in: app, from: "private func receivedApplicationUpdate(", to: "private func startWatchdog")
        let watchdog = try section(in: app, from: "private func startWatchdog", to: "private func recordObservedTransportLoss")
        let receiveBody = String(receive)
        let watchdogBody = String(watchdog)

        #expect(app.contains("private var applicationAdmissionInFlightCount = 0"))
        #expect(app.contains("private var acceptanceSealInProgress = false"))
        #expect(app.contains("$0.kind == \"tuya_application_update\" && $0.details[\"generation\"] == generation"))

        guard let callbackLatch = receiveBody.range(of: "guard !acceptanceSealInProgress else"),
              let increment = receiveBody.range(of: "applicationAdmissionInFlightCount += 1"),
              let mutation = receiveBody.range(of: "try await sessionLedger.recordApplicationUpdate", range: increment.upperBound..<receiveBody.endIndex),
              let ready = watchdogBody.range(of: "case .readyForStationaryMapping:"),
              let inFlight = watchdogBody.range(of: "applicationAdmissionInFlightCount == 0", range: ready.upperBound..<watchdogBody.endIndex),
              let parity = watchdogBody.range(of: "acceptedApplicationEventCount(for: token) == self.applicationUpdateCount", range: inFlight.upperBound..<watchdogBody.endIndex),
              let sealLatch = watchdogBody.range(of: "acceptanceSealInProgress = true", range: parity.upperBound..<watchdogBody.endIndex),
              let packageSeal = watchdogBody.range(of: "try await sessionLedger.sealAcceptedObservation(for: token)", range: sealLatch.upperBound..<watchdogBody.endIndex) else {
            Issue.record("Application admission/seal fencing anchors are missing.")
            throw SourceContractError.sectionMissing
        }

        #expect(callbackLatch.lowerBound < increment.lowerBound)
        #expect(increment.lowerBound < mutation.lowerBound)
        #expect(receiveBody.contains("defer { applicationAdmissionInFlightCount -= 1 }"))
        #expect(inFlight.lowerBound < parity.lowerBound)
        #expect(parity.lowerBound < sealLatch.lowerBound)
        #expect(sealLatch.lowerBound < packageSeal.lowerBound)
    }

    @Test("accepted event bytes are snapshotted from only the current attempt before seal suspension")
    func currentAttemptUsesPreSuspensionSealBarrier() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let start = try section(in: app, from: "func startBaseline()", to: "private func beginCorrelationSeries")
        let watchdog = try section(in: app, from: "private func startWatchdog", to: "private func recordObservedTransportLoss")
        let startBody = String(start)
        let watchdogBody = String(watchdog)

        guard let boundary = startBody.range(of: "captureAttemptEventStartIndex = events.count"),
              let membership = startBody.range(of: "verifySDKMembership", range: boundary.upperBound..<startBody.endIndex),
              let latch = watchdogBody.range(of: "acceptanceSealInProgress = true"),
              let barrier = watchdogBody.range(of: "let eventsAtSealBarrier = Array(self.events.dropFirst(self.captureAttemptEventStartIndex))", range: latch.upperBound..<watchdogBody.endIndex),
              let packageSeal = watchdogBody.range(of: "try await sessionLedger.sealAcceptedObservation(for: token)", range: barrier.upperBound..<watchdogBody.endIndex),
              let frozen = watchdogBody.range(of: "sealedAcceptedEventPrefix = eventsAtSealBarrier", range: packageSeal.upperBound..<watchdogBody.endIndex) else {
            Issue.record("Current-attempt immutable seal barrier anchors are missing.")
            throw SourceContractError.sectionMissing
        }

        #expect(boundary.lowerBound < membership.lowerBound)
        #expect(latch.lowerBound < barrier.lowerBound)
        #expect(barrier.lowerBound < packageSeal.lowerBound)
        #expect(packageSeal.lowerBound < frozen.lowerBound)
    }

    @Test("fresh correlation life reopens the seal latch without weakening accepted export")
    func freshLifeResetsLatch() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let reset = try section(in: app, from: "private func resetDiscoverySessionOnly()", to: "private func failLocally")
        let export = try section(in: app, from: "func prepareExport()", to: "private func resetDiscoverySessionOnly")

        #expect(reset.contains("acceptanceSealInProgress = false"))
        #expect(export.contains("if phase == .accepted"))
        #expect(export.contains("guard let acceptedEventPrefix = self.sealedAcceptedEventPrefix"))
        #expect(export.contains("events: sealedAcceptedEventPrefix"))
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

# Portable invariants. Apple-framework compilation/runtime remains the exact-head Xcode gate.
app = APP.read_text()
receive = app[app.index("private func receivedApplicationUpdate("):app.index("private func startWatchdog")]
admission = receive.index("try await sessionLedger.recordApplicationUpdate(isNonEmpty: !update.isEmpty, for: token)")
value_log = receive.index('log("tuya_application_update"', admission)
next_await = receive.index("await ", admission + len("try await sessionLedger.recordApplicationUpdate(isNonEmpty: !update.isEmpty, for: token)"))
assert value_log < next_await
assert receive.index("guard !acceptanceSealInProgress else") < receive.index("applicationAdmissionInFlightCount += 1") < admission
assert "defer { applicationAdmissionInFlightCount -= 1 }" in receive

start = app[app.index("func startBaseline()"):app.index("private func beginCorrelationSeries")]
assert start.index("captureAttemptEventStartIndex = events.count") < start.index("verifySDKMembership")

watchdog = app[app.index("private func startWatchdog"):app.index("private func recordObservedTransportLoss")]
ready = watchdog.index("case .readyForStationaryMapping:")
in_flight = watchdog.index("applicationAdmissionInFlightCount == 0", ready)
parity = watchdog.index("acceptedApplicationEventCount(for: token) == self.applicationUpdateCount", in_flight)
latch = watchdog.index("acceptanceSealInProgress = true", parity)
barrier = watchdog.index("let eventsAtSealBarrier = Array(self.events.dropFirst(self.captureAttemptEventStartIndex))", latch)
seal = watchdog.index("try await sessionLedger.sealAcceptedObservation(for: token)", barrier)
frozen = watchdog.index("sealedAcceptedEventPrefix = eventsAtSealBarrier", seal)
assert in_flight < parity < latch < barrier < seal < frozen
assert '$0.kind == "tuya_application_update" && $0.details["generation"] == generation' in app
assert "func consumeCorrelationAsyncInvalidation()" in app
