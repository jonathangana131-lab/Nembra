import Foundation
import Testing
@testable import NembraBluetoothCapture

/// Expected-red validation child for package-owned observation terminals.
///
/// The ledger already owns these terminals. This contract is narrower: an app mirror may not
/// publish rider-visible terminal presentation after an actor suspension unless the same app-local
/// presentation owner is still current. An equivalent repair may instead publish the complete
/// terminal presentation before the suspension, leaving no stale post-await write to resume.
///
/// The suite name deliberately extends the canonical presentation-race suite so the existing
/// `swift test --filter TuyaApplicationTimeoutPresentationRaceSourceTests` standalone gate also
/// discovers this validation child without changing workflow bytes.
@Suite("Tuya terminal mirrors preserve post-await presentation ownership")
struct TuyaApplicationTimeoutPresentationRaceSourceTestsPostAwaitOwnership {
    @Test("package-owned incomplete-horizon mirror cannot repaint a newer lifecycle owner")
    func incompleteHorizonMirrorPreservesPresentationOwnership() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let mirror = String(try section(
            in: source,
            from: "private func mirrorAlreadyTerminalIncompleteObservationHorizon",
            to: "private func invalidateObservationContinuity"
        ))
        try requireNoStalePostAwaitPresentation(in: mirror)
    }

    @Test("package-owned continuity mirror cannot repaint a newer lifecycle owner")
    func continuityMirrorPreservesPresentationOwnership() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let mirror = String(try section(
            in: source,
            from: "private func mirrorAlreadyTerminalObservationContinuity",
            to: "private func mirrorAlreadyTerminalIncompleteObservationHorizon"
        ))
        try requireNoStalePostAwaitPresentation(in: mirror)
    }

    private func requireNoStalePostAwaitPresentation(in mirror: String) throws {
        let snapshotRefresh = try requiredOffset("await refreshLedgerSnapshot()", in: mirror)
        let failedPresentation = try requiredOffset("phase = .failed", in: mirror)
        let messagePresentation = try requiredOffset("self.message = message", in: mirror)

        // One valid implementation is to publish the complete app-local terminal presentation
        // synchronously before suspending for the snapshot refresh. A newer lifecycle owner can
        // then overwrite it while this task is suspended; the old task has no stale presentation
        // write left to resume with.
        let presentationIsCompleteBeforeSuspension =
            failedPresentation < snapshotRefresh && messagePresentation < snapshotRefresh

        if !presentationIsCompleteBeforeSuspension {
            // If presentation remains downstream of the await, it needs a post-await owner fence.
            // Keeping `currentConnectionToken` through the suspension is acceptable if the mirror
            // revalidates that exact token + observation phase before clearing it. If the mirror
            // intentionally clears the token before the await to prevent a second package terminal,
            // it must snapshot another stable app-local owner (the established request ID) and
            // revalidate that owner + phase after the await.
            let tokenClear = try requiredOffset("currentConnectionToken = nil", in: mirror)
            let phaseFence = try requiredOffset(
                "phase == .observing",
                in: mirror,
                after: snapshotRefresh,
                before: failedPresentation
            )

            if tokenClear < snapshotRefresh {
                let ownerCapture = try requiredOffset(
                    "officialConnectionRequestID",
                    in: mirror,
                    before: snapshotRefresh
                )
                let ownerFence = try requiredOffset(
                    "officialConnectionRequestID",
                    in: mirror,
                    after: snapshotRefresh,
                    before: failedPresentation
                )
                #expect(ownerCapture < snapshotRefresh)
                #expect(snapshotRefresh < ownerFence)
                #expect(ownerFence <= phaseFence)
            } else {
                let tokenFence = try requiredOffset(
                    "currentConnectionToken == token",
                    in: mirror,
                    after: snapshotRefresh,
                    before: failedPresentation
                )
                #expect(snapshotRefresh < tokenFence)
                #expect(tokenFence <= phaseFence)
                #expect(phaseFence < tokenClear)
            }
            #expect(phaseFence < failedPresentation)
            #expect(failedPresentation < messagePresentation)
        }

        // The fix is app-local presentation fencing only. The package already terminalized this
        // generation; do not regress into a second ledger terminal or invent transport loss.
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
            Issue.record("Expected presentation-ownership source contract missing: \(token)")
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
