import Foundation
import Testing
@testable import NembraBluetoothCapture

/// Expected-red validation child for the package-owned incomplete-observation horizon.
///
/// The ledger already owns the terminal. This contract is narrower: after the app mirror
/// suspends to refresh the ledger snapshot, it may publish rider-visible terminal presentation
/// only if the same app-local request/lifecycle owner still owns that presentation.
///
/// The suite name deliberately extends the canonical presentation-race suite so the existing
/// `swift test --filter TuyaApplicationTimeoutPresentationRaceSourceTests` standalone gate also
/// discovers this validation child without changing workflow bytes.
@Suite("Tuya incomplete-horizon post-await presentation ownership")
struct TuyaApplicationTimeoutPresentationRaceSourceTestsPostAwaitOwnership {
    @Test("package-owned horizon mirror cannot repaint a newer lifecycle owner after actor suspension")
    func incompleteHorizonMirrorRevalidatesPresentationOwnerAfterSnapshotRefresh() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let mirror = String(try section(
            in: source,
            from: "private func mirrorAlreadyTerminalIncompleteObservationHorizon",
            to: "private func invalidateObservationContinuity"
        ))

        let ownerCapture = try requiredOffset(
            "let presentationOwnerRequestID = officialConnectionRequestID",
            in: mirror
        )
        let snapshotRefresh = try requiredOffset(
            "await refreshLedgerSnapshot()",
            in: mirror,
            after: ownerCapture
        )
        let ownerFence = try requiredOffset(
            "guard officialConnectionRequestID == presentationOwnerRequestID,",
            in: mirror,
            after: snapshotRefresh
        )
        let phaseFence = try requiredOffset(
            "phase == .observing else { return }",
            in: mirror,
            after: ownerFence
        )
        let failedPresentation = try requiredOffset(
            "phase = .failed",
            in: mirror,
            after: phaseFence
        )
        let messagePresentation = try requiredOffset(
            "self.message = message",
            in: mirror,
            after: failedPresentation
        )

        #expect(ownerCapture < snapshotRefresh)
        #expect(snapshotRefresh < ownerFence)
        #expect(ownerFence < phaseFence)
        #expect(phaseFence < failedPresentation)
        #expect(failedPresentation < messagePresentation)

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
        after lowerBound: String.Index? = nil
    ) throws -> String.Index {
        let lower = lowerBound ?? source.startIndex
        guard let range = source.range(of: token, range: lower..<source.endIndex) else {
            Issue.record("Expected post-await presentation-ownership source contract missing: \(token)")
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
