import Foundation
import Testing

@Suite("Capture app application-receipt incomplete horizon")
struct TuyaAppIncompleteHorizonApplicationReceiptSourceTests {
    @Test("application receipt preserves the package incomplete-horizon reason")
    func applicationReceiptDoesNotCollapseIncompleteHorizonIntoGenericLifecycle() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receipt = String(try section(
            in: app,
            from: "private func receivedApplicationUpdate",
            to: "private func redactedApplicationEventDetails"
        ))
        let terminal = String(try section(
            in: receipt,
            from: "catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.incompleteObservationHorizonReached",
            to: "} catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.staleConnection"
        ))

        #expect(terminal.contains("invalidateInternalLifecycle"))
        #expect(terminal.contains("incomplete_readiness_horizon_reached"))
        #expect(terminal.contains("60-second incomplete-evidence horizon"))
        #expect(terminal.contains("without another liveness sample"))
        #expect(terminal.contains("Bluetooth-disconnect claim"))
        #expect(!terminal.contains("application_update_lifecycle_rejected"))
        #expect(!terminal.contains("recordObservedTransportLoss"))
        #expect(!terminal.contains("sessionLedger.endConnection"))
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
