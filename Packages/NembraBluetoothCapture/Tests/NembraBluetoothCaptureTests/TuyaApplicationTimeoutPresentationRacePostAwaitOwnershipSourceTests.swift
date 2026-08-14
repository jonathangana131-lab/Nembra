import Foundation
import Testing
@testable import NembraBluetoothCapture

/// Expected-red validation child for package-owned observation terminals.
///
/// The ledger already owns these terminal verdicts. The app mirror must consume the exact local
/// token without issuing a second package terminal, but a lifecycle failure that became visible
/// while the package actor was suspended must not be repainted by the resumed mirror.
///
/// The suite name deliberately extends the canonical presentation-race suite so the existing
/// `swift test --filter TuyaApplicationTimeoutPresentationRaceSourceTests` standalone gate also
/// discovers this validation child without changing workflow bytes.
@Suite("Tuya terminal mirrors preserve lifecycle presentation ownership")
struct TuyaApplicationTimeoutPresentationRaceSourceTestsPostAwaitOwnership {
    @Test("package-owned incomplete-horizon mirror preserves a newer lifecycle failure")
    func incompleteHorizonMirrorPreservesPresentationOwnership() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let mirror = String(try section(
            in: source,
            from: "private func mirrorAlreadyTerminalIncompleteObservationHorizon",
            to: "private func invalidateObservationContinuity"
        ))
        try requireLifecyclePresentationFence(in: mirror)
    }

    @Test("package-owned continuity mirror preserves a newer lifecycle failure")
    func continuityMirrorPreservesPresentationOwnership() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let mirror = String(try section(
            in: source,
            from: "private func mirrorAlreadyTerminalObservationContinuity",
            to: "private func mirrorAlreadyTerminalIncompleteObservationHorizon"
        ))
        try requireLifecyclePresentationFence(in: mirror)
    }

    private func requireLifecyclePresentationFence(in mirror: String) throws {
        let tokenGuard = try requiredOffset("guard currentConnectionToken == token", in: mirror)
        let tokenClear = try requiredOffset(
            "currentConnectionToken = nil",
            in: mirror,
            after: tokenGuard
        )
        let snapshotRefresh = try requiredOffset(
            "await refreshLedgerSnapshot()",
            in: mirror,
            after: tokenClear
        )
        let failedPresentation = try requiredOffset(
            "phase = .failed",
            in: mirror,
            after: snapshotRefresh
        )
        let phaseFence = try requiredOffset(
            "phase == .observing",
            in: mirror,
            after: snapshotRefresh,
            before: failedPresentation
        )
        let messagePresentation = try requiredOffset(
            "self.message = message",
            in: mirror,
            after: failedPresentation
        )

        // Consume app-local generation ownership even when another lifecycle path already changed
        // presentation. This makes the lifecycle retirement task's exact-token guard fail closed
        // instead of attempting a second package terminal against the already-terminal ledger.
        #expect(tokenGuard < tokenClear)
        #expect(tokenClear < snapshotRefresh)

        // The package actor hop can resume after foreground/view teardown has already published a
        // more specific failure. Only an observation that still owns presentation may publish the
        // package-terminal copy after cleanup/snapshot refresh.
        #expect(snapshotRefresh < phaseFence)
        #expect(phaseFence < failedPresentation)
        #expect(failedPresentation < messagePresentation)

        // The package already terminalized this generation. Never regress to a second ledger
        // terminal or manufacture transport-loss evidence while fixing presentation ownership.
        #expect(!mirror.contains("sessionLedger."))
        #expect(!mirror.contains("markApplicationObservationTimedOut"))
        #expect(!mirror.contains("markInternalLifecycleFailure"))
        #expect(!mirror.contains("endConnection"))
        #expect(!mirror.contains("recordObservedTransportLoss"))
    }

    private func requiredOffset(
        _ token: String,
        in source: String,
        after lowerBound: String.Index? = nil,
        before upperBound: String.Index? = nil
    ) throws -> String.Index {
        let lower = lowerBound ?? source.startIndex
        let upper = upperBound ?? source.endIndex
        guard lower <= upper,
              let range = source.range(of: token, range: lower..<upper) else {
            Issue.record("Expected lifecycle-presentation source contract missing: \(token)")
            throw SourceContractError.requiredTokenMissing
        }
        return range.lowerBound
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

    private enum SourceContractError: Error {
        case sectionMissing
        case requiredTokenMissing
    }
}
