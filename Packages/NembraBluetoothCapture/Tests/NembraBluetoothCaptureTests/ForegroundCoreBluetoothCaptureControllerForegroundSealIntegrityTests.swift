import Foundation
import Testing
@testable import NembraBluetoothCapture

/// Expected-red source contract for the foreground-only validity boundary while
/// an observation Horizon is being sealed.
///
/// Horizon admission isolates later BLE/FIFO transport callbacks from the accepted
/// artifact prefix. It does not make loss of foreground integrity irrelevant before
/// immutable terminal freeze. A loss that interleaves across either actor suspension
/// must be observed synchronously on MainActor and routed into the matching partial-H
/// recovery state instead of allowing commit/freeze to continue.
struct ForegroundCoreBluetoothCaptureControllerForegroundSealIntegrityTests {
    private static func controllerSource() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: packageRoot
                .appendingPathComponent("Sources")
                .appendingPathComponent("NembraBluetoothCapture")
                .appendingPathComponent("ForegroundCoreBluetoothCaptureController.swift"),
            encoding: .utf8
        )
    }

    private static func section(
        in source: String,
        from startMarker: String,
        to endMarker: String
    ) throws -> Substring {
        let start = try #require(source.range(of: startMarker)?.lowerBound)
        let end = try #require(
            source.range(of: endMarker, range: start..<source.endIndex)?.lowerBound
        )
        return source[start..<end]
    }

    @Test("foreground loss is classified before generic closing transport teardown")
    func foregroundLossCannotBeSwallowedByHorizonTransportIsolation() throws {
        let source = try Self.controllerSource()
        let method = try Self.section(
            in: source,
            from: "    private func cancelActiveConnection(cause: PassiveCoreBluetoothCancellationCause) {",
            to: "    /// Adds a human-observed stock-app value"
        )

        let foregroundCase = try #require(method.range(of: ".foregroundIntegrityLoss"))
        let genericClosingShortcut = try #require(
            method.range(of: "if observationBoundaryBlocksArtifactMutation {")
        )

        #expect(foregroundCase.lowerBound < genericClosingShortcut.lowerBound)
    }

    @Test("foreground validity is rechecked after H recorder and JSON actor suspensions")
    func sealingRevalidatesBeforeQueueCommitAndTerminalFreeze() throws {
        let source = try Self.controllerSource()
        let finalization = try Self.section(
            in: source,
            from: "    public func encodedFinalizedObservationHorizonJSON(",
            to: "    private func beginTargetSessionIfNeeded"
        )

        let recorderAwait = try #require(
            finalization.range(of: ".recordBoundaryWithMutationOutcome(on: recorder)")
        )
        let queueCommit = try #require(
            finalization.range(
                of: "recordedHorizon.markBoundaryRecorded(",
                range: recorderAwait.upperBound..<finalization.endIndex
            )
        )
        let afterRecorderBeforeCommit = finalization[
            recorderAwait.upperBound..<queueCommit.lowerBound
        ]

        let jsonAwait = try #require(
            finalization.range(
                of: "recorder.encodedJSON(prettyPrinted: prettyPrinted)",
                range: queueCommit.upperBound..<finalization.endIndex
            )
        )
        let terminalFreeze = try #require(
            finalization.range(
                of: "committedHorizon.completeHorizonArtifactFreeze(",
                range: jsonAwait.upperBound..<finalization.endIndex
            )
        )
        let afterJSONBeforeFreeze = finalization[
            jsonAwait.upperBound..<terminalFreeze.lowerBound
        ]

        // `ensureCaptureHealthy()` is the incumbent controller's synchronous
        // validity primitive. A future explicit foreground lease/generation may
        // replace it, but the equivalent checks must remain between these exact
        // suspension and mutation boundaries.
        #expect(afterRecorderBeforeCommit.contains("ensureCaptureHealthy()"))
        #expect(afterJSONBeforeFreeze.contains("ensureCaptureHealthy()"))

        // The matching fail-closed recovery authorities already exist on this
        // lineage and must remain available to consume the failed revalidation.
        #expect(finalization.contains("abortRecordedHorizonBeforeGateCommit"))
        #expect(finalization.contains("abortCommittedHorizonBeforeArtifactFreeze"))
    }
}
