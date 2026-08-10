import Foundation
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
