import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture application-update admission deadline chronology")
struct TuyaApplicationAdmissionDeadlineSourceTests {
    @Test("no-application timeout cannot retire a callback already admitted by the app boundary")
    func timeoutWaitsForInFlightApplicationAdmission() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let watchdog = try section(
            in: app,
            from: "private func startWatchdog",
            to: "private func recordObservedTransportLoss"
        )
        let body = String(watchdog)

        guard let timeoutCondition = body.range(of: "if (self.canonicalObservedAgeSeconds ?? 0) > 60"),
              let timeoutMutation = body.range(
                of: "sessionLedger.markApplicationObservationTimedOut(for: token)",
                range: timeoutCondition.upperBound..<body.endIndex
              ) else {
            Issue.record("Expected no-application timeout path is missing.")
            throw SourceContractError.sectionMissing
        }

        let timeoutGate = String(body[timeoutCondition.lowerBound..<timeoutMutation.lowerBound])
        #expect(timeoutGate.contains("applicationUpdateAdmissionsInFlight == 0"))
    }

    @Test("accepted seal and timeout share the same in-flight application admission fence")
    func sealAndTimeoutUseSameAdmissionFence() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let watchdog = try section(
            in: app,
            from: "private func startWatchdog",
            to: "private func recordObservedTransportLoss"
        )
        let body = String(watchdog)

        guard let readyCase = body.range(of: "case .readyForStationaryMapping:"),
              let seal = body.range(of: "sessionLedger.sealAcceptedObservation(for: token)"),
              let timeout = body.range(of: "sessionLedger.markApplicationObservationTimedOut(for: token)") else {
            Issue.record("Expected seal/timeout paths are missing.")
            throw SourceContractError.sectionMissing
        }

        #expect(readyCase.lowerBound < seal.lowerBound)
        #expect(body[readyCase.lowerBound..<seal.lowerBound].contains("applicationUpdateAdmissionsInFlight == 0"))
        #expect(body[seal.upperBound..<timeout.lowerBound].contains("applicationUpdateAdmissionsInFlight == 0"))
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
