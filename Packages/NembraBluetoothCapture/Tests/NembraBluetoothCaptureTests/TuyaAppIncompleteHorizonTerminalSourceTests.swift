import Foundation
import Testing

@Suite("Capture app incomplete-horizon terminal")
struct TuyaAppIncompleteHorizonTerminalSourceTests {
    @Test("watchdog preserves the package incomplete-horizon reason")
    func watchdogDoesNotCollapseIncompleteHorizonIntoGenericLifecycle() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let watchdog = String(try section(
            in: app,
            from: "private func startWatchdog",
            to: "private func recordObservedTransportLoss"
        ))
        let terminal = String(try section(
            in: watchdog,
            from: "catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.incompleteObservationHorizonReached",
            to: "} catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.staleConnection"
        ))

        #expect(terminal.contains("invalidateInternalLifecycle"))
        #expect(terminal.contains("session_authenticated_incomplete_readiness_horizon_reached"))
        #expect(terminal.contains("60-second incomplete-evidence horizon"))
        #expect(terminal.contains("without another liveness sample"))
        #expect(terminal.contains("Bluetooth-disconnect claim"))
        #expect(!terminal.contains("session_liveness_lifecycle_rejected"))
        #expect(!terminal.contains("recordObservedTransportLoss"))
        #expect(!terminal.contains("sessionLedger.observeCurrentConnection"))
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
