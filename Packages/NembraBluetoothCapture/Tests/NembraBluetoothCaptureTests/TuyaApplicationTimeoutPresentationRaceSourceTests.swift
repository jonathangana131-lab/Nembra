import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya incomplete-horizon presentation ownership")
struct TuyaApplicationTimeoutPresentationRaceSourceTests {
    @Test("package-owned horizon removes the duplicate app timeout authority")
    func watchdogDoesNotOwnASecondTimeoutTerminal() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let watchdog = String(try section(
            in: source,
            from: "private func startWatchdog",
            to: "private func recordObservedTransportLoss"
        ))

        #expect(!watchdog.contains("sessionLedger.markApplicationObservationTimedOut(for: token)"))
        #expect(watchdog.contains(
            "catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.incompleteObservationHorizonReached"
        ))
        #expect(watchdog.contains("mirrorAlreadyTerminalIncompleteObservationHorizon"))
    }

    @Test("already-terminal mirror keeps presentation ownership local")
    func incompleteHorizonMirrorDoesNotReenterTheLedger() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let mirror = String(try section(
            in: source,
            from: "private func mirrorAlreadyTerminalIncompleteObservationHorizon",
            to: "private func invalidateObservationContinuity"
        ))

        #expect(mirror.contains("currentConnectionToken == token"))
        #expect(mirror.contains("phase = .failed"))
        #expect(!mirror.contains("sessionLedger."))
        #expect(!mirror.contains("markApplicationObservationTimedOut"))
        #expect(!mirror.contains("markInternalLifecycleFailure"))
        #expect(!mirror.contains("endConnection"))
        #expect(!mirror.contains("recordObservedTransportLoss"))
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
