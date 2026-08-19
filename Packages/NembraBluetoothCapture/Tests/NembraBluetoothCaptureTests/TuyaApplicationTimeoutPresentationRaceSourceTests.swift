import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya incomplete-observation terminal ownership")
struct TuyaApplicationTimeoutPresentationRaceSourceTests {
    @Test("watchdog delegates incomplete-session retirement to the package ledger")
    func watchdogUsesPackageOwnedIncompleteHorizon() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let watchdog = String(try section(
            in: source,
            from: "private func startWatchdog",
            to: "private func recordObservedTransportLoss"
        ))

        #expect(watchdog.contains("sessionLedger.observeCurrentConnection"))
        #expect(watchdog.contains("catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.incompleteObservationHorizonReached"))
        #expect(watchdog.contains("mirrorAlreadyTerminalIncompleteObservationHorizon"))

        // The package ledger owns the bounded incomplete-observation terminal. The app must not
        // race it with a second zero-payload timeout or publish a competing terminal reason.
        #expect(!watchdog.contains("markApplicationObservationTimedOut"))
        #expect(!watchdog.contains("authenticated_application_timeout"))
        #expect(!watchdog.contains("Authenticated session produced no application update before the observation deadline."))
    }

    @Test("package-owned horizon mirror does not attempt a second ledger terminal")
    func horizonMirrorIsPresentationOnly() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let mirror = String(try section(
            in: source,
            from: "private func mirrorAlreadyTerminalIncompleteObservationHorizon",
            to: "private func invalidateObservationContinuity"
        ))

        #expect(!mirror.contains("sessionLedger.markApplicationObservationTimedOut"))
        #expect(!mirror.contains("sessionLedger.markInternalLifecycleFailure"))
        #expect(!mirror.contains("sessionLedger.endConnection"))
        #expect(!mirror.contains("sessionLedger.observeCurrentConnection"))
        #expect(!mirror.contains("recordObservedTransportLoss"))
        #expect(mirror.contains("refreshLedgerSnapshot"))
        #expect(mirror.contains("phase = .failed"))
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let a = source.range(of: start),
              let b = source.range(of: end, range: a.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \(start) ... \(end)")
            throw SourceContractError.sectionMissing
        }
        return source[a.lowerBound..<b.lowerBound]
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private enum SourceContractError: Error { case sectionMissing }
}
