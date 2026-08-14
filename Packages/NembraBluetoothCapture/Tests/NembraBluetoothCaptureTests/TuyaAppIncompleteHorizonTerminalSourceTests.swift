import Foundation
import Testing

@Suite("Capture app incomplete-horizon terminal")
struct TuyaAppIncompleteHorizonTerminalSourceTests {
    @Test("both app admission paths mirror the package-owned incomplete horizon terminal")
    func appDoesNotAttemptSecondIncompleteHorizonTerminal() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        let applicationAdmission = String(try section(
            in: app,
            from: "private func receivedApplicationUpdate",
            to: "private func redactedApplicationEventDetails"
        ))
        let applicationTerminal = String(try section(
            in: applicationAdmission,
            from: "catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.incompleteObservationHorizonReached",
            to: "} catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.staleConnection"
        ))

        let watchdog = String(try section(
            in: app,
            from: "private func startWatchdog",
            to: "private func recordObservedTransportLoss"
        ))
        let watchdogTerminal = String(try section(
            in: watchdog,
            from: "catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.incompleteObservationHorizonReached",
            to: "} catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.staleConnection"
        ))

        for terminal in [applicationTerminal, watchdogTerminal] {
            #expect(terminal.contains("mirrorAlreadyTerminalIncompleteObservationHorizon"))
            #expect(terminal.contains("incomplete"))
            #expect(terminal.contains("Scooter data did not become sufficient within 60 seconds."))
            #expect(!terminal.contains("invalidateInternalLifecycle"))
            #expect(!terminal.contains("markApplicationObservationTimedOut"))
            #expect(!terminal.contains("recordObservedTransportLoss"))
            #expect(!terminal.contains("sessionLedger.observeCurrentConnection"))
            #expect(!terminal.contains("sessionLedger.endConnection"))
        }

        let mirror = String(try section(
            in: app,
            from: "private func mirrorAlreadyTerminalIncompleteObservationHorizon",
            to: "private func invalidateObservationContinuity"
        ))
        #expect(!mirror.contains("sessionLedger.markApplicationObservationTimedOut"))
        #expect(!mirror.contains("sessionLedger.markInternalLifecycleFailure"))
        #expect(!mirror.contains("sessionLedger.endConnection"))
        #expect(!mirror.contains("sessionLedger.observeCurrentConnection"))
        #expect(!mirror.contains("recordObservedTransportLoss"))
        #expect(mirror.contains("sdkLocalBLEOnline = false"))
        #expect(app.contains("test.sdkLocalBLEOnline ? \"Online\" : \"Not proven\""))
        #expect(mirror.contains("refreshLedgerSnapshot"))
        #expect(mirror.contains("phase = .failed"))
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
