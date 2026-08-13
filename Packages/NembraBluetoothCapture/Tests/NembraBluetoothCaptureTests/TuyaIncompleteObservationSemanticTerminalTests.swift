import Foundation
import Testing

extension TuyaAppIncompleteHorizonTerminalSourceTests {
    @Test("bounded incomplete horizon uses the dedicated observation-timeout terminal")
    func incompleteHorizonDoesNotBecomeInternalLifecycleFailure() throws {
        let app = try readSemanticTerminalRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        let applicationAdmission = String(try semanticTerminalSection(
            in: app,
            from: "private func receivedApplicationUpdate",
            to: "private func redactedApplicationEventDetails"
        ))
        let applicationTerminal = String(try semanticTerminalSection(
            in: applicationAdmission,
            from: "catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.incompleteObservationHorizonReached",
            to: "} catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.staleConnection"
        ))

        let watchdog = String(try semanticTerminalSection(
            in: app,
            from: "private func startWatchdog",
            to: "private func recordObservedTransportLoss"
        ))
        let watchdogTerminal = String(try semanticTerminalSection(
            in: watchdog,
            from: "catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.incompleteObservationHorizonReached",
            to: "} catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.staleConnection"
        ))

        for terminal in [applicationTerminal, watchdogTerminal] {
            #expect(terminal.contains("invalidateIncompleteObservationHorizon"))
            #expect(!terminal.contains("invalidateInternalLifecycle"))
            #expect(!terminal.contains("recordObservedTransportLoss"))
            #expect(!terminal.contains("endConnection"))
        }

        let dedicatedTerminal = String(try semanticTerminalSection(
            in: app,
            from: "private func invalidateIncompleteObservationHorizon",
            to: "private func invalidateObservationContinuity"
        ))
        #expect(dedicatedTerminal.contains("sessionLedger.markApplicationObservationTimedOut(for: token)"))
        #expect(!dedicatedTerminal.contains("sessionLedger.markInternalLifecycleFailure"))
        #expect(!dedicatedTerminal.contains("sessionLedger.endConnection"))
        #expect(!dedicatedTerminal.contains("sessionLedger.observeCurrentConnection"))
        #expect(!dedicatedTerminal.contains("recordObservedTransportLoss"))
    }

    @Test("observation-timeout ledger reason covers insufficient repeated evidence")
    func timeoutReasonDoesNotClaimZeroApplicationUpdates() throws {
        let ledger = try readSemanticTerminalRepositoryFile(
            "Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/TuyaAuthenticatedReadOnlySessionLedger.swift"
        )
        let timeoutTerminal = String(try semanticTerminalSection(
            in: ledger,
            from: "public func markApplicationObservationTimedOut",
            to: "public func sealAcceptedObservation"
        ))

        #expect(timeoutTerminal.contains("sufficient application evidence"))
        #expect(!timeoutTerminal.contains("produced no application update"))
    }

    private func semanticTerminalSection(in source: String, from start: String, to end: String) throws -> Substring {
        guard let startRange = source.range(of: start),
              let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            Issue.record("Expected semantic-terminal source section missing: \(start) ... \(end)")
            throw SemanticTerminalSourceContractError.sectionMissing
        }
        return source[startRange.lowerBound..<endRange.lowerBound]
    }

    private func readSemanticTerminalRepositoryFile(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private enum SemanticTerminalSourceContractError: Error {
        case sectionMissing
    }
}
