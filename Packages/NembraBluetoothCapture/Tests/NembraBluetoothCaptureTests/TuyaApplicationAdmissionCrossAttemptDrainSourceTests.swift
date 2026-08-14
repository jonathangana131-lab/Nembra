import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture application admission cross-attempt drain")
struct TuyaApplicationAdmissionCrossAttemptDrainSourceTests {
    @Test("fresh attempt reset does not forget an older callback admission that is still unwinding")
    func resetPreservesGlobalAdmissionDrain() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let reset = try section(
            in: app,
            from: "private func resetDiscoverySessionOnly()",
            to: "private func failLocally"
        )
        let body = String(reset)

        #expect(app.contains("private var applicationUpdateAdmissionsInFlight = 0"))
        #expect(app.components(separatedBy: "applicationUpdateAdmissionsInFlight = 0").count - 1 == 1,
                Comment(rawValue: "The admission counter is controller-lifetime drain state. Resetting it during a fresh correlation life could forget an older callback that already crossed the acceptance-cut guard and is still suspended in package work."))
        #expect(!body.contains("applicationUpdateAdmissionsInFlight = 0"),
                Comment(rawValue: "A fresh attempt may reopen admission, but it must wait for every older in-flight application admission to unwind rather than manufacturing quiescence."))
        #expect(body.contains("acceptanceCutIsClosed = false"))
        #expect(body.contains("sealedAcceptedEventPrefix = nil"))
    }

    @Test("accepted seal still waits on the controller-lifetime drain after reset can reopen the cut")
    func sealRemainsFencedByGlobalDrain() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let watchdog = try section(
            in: app,
            from: "private func startWatchdog",
            to: "private func recordObservedTransportLoss"
        )
        let body = String(watchdog)

        guard let quiescence = body.range(of: "guard self.applicationUpdateAdmissionsInFlight == 0"),
              let closeCut = body.range(of: "self.acceptanceCutIsClosed = true", range: quiescence.upperBound..<body.endIndex),
              let seal = body.range(of: "try await sessionLedger.sealAcceptedObservation(for: token)", range: closeCut.upperBound..<body.endIndex) else {
            Issue.record("Canonical acceptance must still wait for the controller-lifetime admission drain before closing the new attempt's cut and sealing package evidence.")
            throw SourceContractError.sectionMissing
        }

        #expect(quiescence.lowerBound < closeCut.lowerBound)
        #expect(closeCut.lowerBound < seal.lowerBound)
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
