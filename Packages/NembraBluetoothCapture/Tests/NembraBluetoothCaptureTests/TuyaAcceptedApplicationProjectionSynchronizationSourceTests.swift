import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture accepted application projection synchronization")
struct TuyaAcceptedApplicationProjectionSynchronizationSourceTests {
    @Test("a package-accepted application update is projected before the controller suspends again")
    func acceptedUpdateProjectsBeforeNextSuspension() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receive = try section(
            in: app,
            from: "private func receivedApplicationUpdate",
            to: "private func startWatchdog"
        )
        let body = String(receive)

        #expect(app.contains("private var acceptedApplicationProjectionCount = 0"), Comment(rawValue: "The controller needs a current-attempt projection counter that cannot be inferred from the lifetime diagnostic event log."))

        guard let packageAdmission = body.range(of: "try await sessionLedger.recordApplicationUpdate"),
              let projectedValue = body.range(of: "log(\"tuya_application_update\"", range: packageAdmission.upperBound..<body.endIndex),
              let projectionAdvance = body.range(of: "acceptedApplicationProjectionCount += 1", range: projectedValue.upperBound..<body.endIndex) else {
            Issue.record("A package-accepted structured update must be synchronously projected and counted in the app before another suspension point.")
            throw SourceContractError.sectionMissing
        }

        if let nextAwait = body.range(of: "await ", range: packageAdmission.upperBound..<body.endIndex) {
            #expect(projectedValue.lowerBound < nextAwait.lowerBound)
            #expect(projectionAdvance.lowerBound < nextAwait.lowerBound)
        }
    }

    @Test("canonical readiness cannot seal while the app structured projection trails package receipts")
    func sealRequiresProjectionReceiptSynchronization() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let watchdog = try section(
            in: app,
            from: "private func startWatchdog",
            to: "private func recordObservedTransportLoss"
        )
        let ready = try section(
            in: String(watchdog),
            from: "case .readyForStationaryMapping:",
            to: "try await sessionLedger.sealAcceptedObservation(for: token)"
        )
        let body = String(ready)

        #expect(body.contains("acceptedApplicationProjectionCount"), Comment(rawValue: "The seal path must consult app-side accepted structured evidence, not package readiness alone."))
        #expect(body.contains("applicationUpdateCount"), Comment(rawValue: "The app projection must be compared with the current package-accepted application receipt count."))
        #expect(body.contains("=="), Comment(rawValue: "The accepted prefix may seal only when app projection and package accepted receipts are synchronized."))
    }

    @Test("a fresh correlation life cannot inherit an older generation projection count")
    func freshAttemptResetsProjectionCount() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let reset = try section(
            in: app,
            from: "private func resetDiscoverySessionOnly()",
            to: "private func failLocally"
        )

        #expect(reset.contains("acceptedApplicationProjectionCount = 0"), Comment(rawValue: "Current-generation accepted application projection state must not survive into a fresh OFF1 correlation life."))
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
