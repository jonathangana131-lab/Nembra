import Foundation
import Testing
@testable import NembraBluetoothCapture

/// Expected-red coordination contract for foreground-integrity loss while an
/// observation Horizon is closing.
///
/// Horizon admission freezes the accepted BLE/FIFO prefix, but it does not by
/// itself make the artifact safe to export. If the app loses foreground before
/// immutable terminal freeze, the controller must invalidate finalization and
/// classify the exact partial-H state with producer-issued recovery authority.
/// Transport isolation alone is insufficient.
struct ForegroundCoreBluetoothCaptureControllerForegroundFinalizationIntegrityTests {
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

    private static func offset(of needle: String, in haystack: Substring) throws -> Int {
        let range = try #require(haystack.range(of: needle))
        return haystack.distance(from: haystack.startIndex, to: range.lowerBound)
    }

    @Test("foreground loss is classified before the generic Horizon transport-only shortcut")
    func foregroundLossCannotBeSwallowedByClosingTransportIsolation() throws {
        let source = try Self.controllerSource()
        let method = try Self.section(
            in: source,
            from: "    private func cancelActiveConnection(cause: PassiveCoreBluetoothCancellationCause) {",
            to: "    /// Adds a human-observed stock-app value"
        )

        // A closing H may isolate later transport callbacks from the accepted
        // artifact prefix, but foreground loss before immutable freeze still
        // invalidates finalization. The cause therefore needs explicit treatment
        // before the broad transport-only early return can run.
        let foregroundClassification = try Self.offset(of: ".foregroundIntegrityLoss", in: method)
        let transportOnlyShortcut = try Self.offset(
            of: "if observationBoundaryBlocksArtifactMutation {",
            in: method
        )

        #expect(foregroundClassification < transportOnlyShortcut)
    }

    @Test("pre-recorder foreground failure abandons the exact unused Horizon transaction")
    func preRecorderFailureConsumesFourthStateRecovery() throws {
        let source = try Self.controllerSource()
        let finalization = try Self.section(
            in: source,
            from: "    public func encodedFinalizedObservationHorizonJSON(",
            to: "    private func beginTargetSessionIfNeeded"
        )

        let flush = try Self.offset(
            of: "await flushPendingEvents(through: horizonAdmission.queueCutoff)",
            in: finalization
        )
        let recordAttempt = try Self.offset(
            of: "recordBoundaryWithMutationOutcome(on: recorder)",
            in: finalization
        )
        let abandonment = try Self.offset(
            of: "horizonAdmission.abandonBeforeRecorderMutation()",
            in: finalization
        )
        let quarantine = try Self.offset(
            of: "abortUncommittedHorizon",
            in: finalization
        )

        #expect(flush < abandonment)
        #expect(abandonment < quarantine)
        #expect(quarantine < recordAttempt)
    }

    @Test("foreground validity is rechecked after recorder and artifact actor suspensions")
    func finalizationRevalidatesForegroundBeforeCommitAndFreeze() throws {
        let source = try Self.controllerSource()
        let finalization = try Self.section(
            in: source,
            from: "    public func encodedFinalizedObservationHorizonJSON(",
            to: "    private func beginTargetSessionIfNeeded"
        )

        let recordedCase = try Self.offset(
            of: "case let .recorded(recordedHorizon):",
            in: finalization
        )
        let queueCommit = try Self.offset(
            of: "recordedHorizon.markBoundaryRecorded(",
            in: finalization
        )
        let encoded = try Self.offset(
            of: "recorder.encodedJSON(prettyPrinted: prettyPrinted)",
            in: finalization
        )
        let freeze = try Self.offset(
            of: "committedHorizon.completeHorizonArtifactFreeze(",
            in: finalization
        )

        let recordedToCommit = finalization.index(
            finalization.startIndex,
            offsetBy: recordedCase
        )..<finalization.index(
            finalization.startIndex,
            offsetBy: queueCommit
        )
        let encodedToFreeze = finalization.index(
            finalization.startIndex,
            offsetBy: encoded
        )..<finalization.index(
            finalization.startIndex,
            offsetBy: freeze
        )

        // `ensureCaptureHealthy()` is the incumbent controller's fail-closed
        // validity primitive. A production successor may replace this with a
        // stronger explicit foreground lease, but it must preserve the same two
        // synchronous revalidation points and exact partial-H quarantine behavior.
        #expect(finalization[recordedToCommit].contains("ensureCaptureHealthy()"))
        #expect(finalization[encodedToFreeze].contains("ensureCaptureHealthy()"))
    }
}
