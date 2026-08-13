import Foundation
import Testing

@Suite("Capture app incomplete-horizon terminal")
struct TuyaAppIncompleteHorizonTerminalSourceTests {
    @Test("watchdog mirrors package-owned incomplete-horizon retirement without a second terminal")
    func watchdogDoesNotRetryLedgerRetirementAfterPackageTerminal() throws {
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

        #expect(terminal.contains("mirrorAlreadyTerminal"))
        #expect(terminal.contains("incomplete"))
        #expect(terminal.contains("horizon"))
        #expect(!terminal.contains("invalidateInternalLifecycle"))
        #expect(!terminal.contains("markInternalLifecycleFailure"))
        #expect(!terminal.contains("markApplicationObservationTimedOut"))
        #expect(!terminal.contains("recordObservedTransportLoss"))
        #expect(!terminal.contains("sessionLedger."))
        #expect(!terminal.contains("session_liveness_lifecycle_rejected"))
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
