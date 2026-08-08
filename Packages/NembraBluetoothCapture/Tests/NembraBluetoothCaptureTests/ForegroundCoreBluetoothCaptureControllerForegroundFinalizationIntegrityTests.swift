import Foundation
import Testing
@testable import NembraBluetoothCapture

/// Source integration contract for foreground-only evidence integrity across
/// Horizon finalization actor suspensions. Software lifecycle truth only.
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

    private static func finalizedHorizonSection(in source: String) throws -> Substring {
        let start = try #require(
            source.range(of: "    public func encodedFinalizedObservationHorizonJSON(")?.lowerBound
        )
        let end = try #require(
            source.range(
                of: "\n    private func beginTargetSessionIfNeeded",
                range: start..<source.endIndex
            )?.lowerBound
        )
        return source[start..<end]
    }

    @Test("foreground integrity is durable per target session and fresh-session-owned")
    func integrityBitInvalidatesOldSessionAndOnlyFreshRecorderRestoresIt() throws {
        let source = try Self.controllerSource()
        #expect(source.contains("private var foregroundEvidenceIntegrityValid = true"))
        #expect(source.contains("&& foregroundEvidenceIntegrityValid"))

        let invalidateStart = try #require(
            source.range(of: "    public func invalidateActiveCaptureForForegroundLoss()")?.lowerBound
        )
        let invalidateEnd = try #require(
            source.range(
                of: "\n    /// Ends transport only after",
                range: invalidateStart..<source.endIndex
            )?.lowerBound
        )
        let invalidate = source[invalidateStart..<invalidateEnd]
        let invalidation = try #require(
            invalidate.range(of: "foregroundEvidenceIntegrityValid = false")?.lowerBound
        )
        let teardown = try #require(
            invalidate.range(of: "cancelActiveConnection(cause: .foregroundIntegrityLoss)")?.lowerBound
        )
        #expect(invalidation < teardown)

        let freshStart = try #require(
            source.range(of: "    private func beginTargetSessionIfNeeded(for identifier: UUID)")?.lowerBound
        )
        let freshEnd = try #require(
            source.range(
                of: "\n    private func currentArtifactContext",
                range: freshStart..<source.endIndex
            )?.lowerBound
        )
        let fresh = source[freshStart..<freshEnd]
        let restore = try #require(
            fresh.range(of: "foregroundEvidenceIntegrityValid = true")?.lowerBound
        )
        let publish = try #require(fresh.range(of: "recorder = newRecorder")?.lowerBound)
        #expect(restore < publish)
    }

    @Test("foreground loss during closing path fails capture rather than transport-only cleanup")
    func closingForegroundLossFailsCapture() throws {
        let source = try Self.controllerSource()
        let methodStart = try #require(
            source.range(of: "    private func cancelActiveConnection(cause: PassiveCoreBluetoothCancellationCause)")?.lowerBound
        )
        let methodEnd = try #require(
            source.range(
                of: "\n    /// Adds a human-observed stock-app value",
                range: methodStart..<source.endIndex
            )?.lowerBound
        )
        let method = source[methodStart..<methodEnd]
        let closingStart = try #require(
            method.range(of: "if observationBoundaryBlocksArtifactMutation {")?.lowerBound
        )
        let closingEnd = try #require(
            method.range(
                of: "\n        if targetState.selectedTargetIdentifier",
                range: closingStart..<method.endIndex
            )?.lowerBound
        )
        let closing = method[closingStart..<closingEnd]
        #expect(closing.contains("foregroundIntegrityLoss"))
        #expect(closing.contains("failCapture("))
    }

    @Test("every actor-suspended Horizon promotion rechecks foreground integrity")
    func postAwaitPromotionsRecheckIntegrityAndQuarantineExactPartialState() throws {
        let source = try Self.controllerSource()
        let section = try Self.finalizedHorizonSection(in: source)

        let mutation = try #require(
            section.range(of: ".recordBoundaryWithMutationOutcome(on: recorder)")?.lowerBound
        )
        let queueCommit = try #require(
            section.range(of: "recordedHorizon.markBoundaryRecorded", range: mutation..<section.endIndex)?.lowerBound
        )
        let encoded = try #require(
            section.range(of: "recorder.encodedJSON", range: queueCommit..<section.endIndex)?.lowerBound
        )
        let freeze = try #require(
            section.range(of: "committedHorizon.completeHorizonArtifactFreeze", range: encoded..<section.endIndex)?.lowerBound
        )

        let recordedToCommit = section[mutation..<queueCommit]
        #expect(recordedToCommit.contains("try ensureCaptureHealthy()"))
        #expect(recordedToCommit.contains("foregroundEvidenceIntegrityValid"))
        #expect(section[mutation..<encoded].contains("abortRecordedHorizonBeforeGateCommit"))
        #expect(!section[mutation..<encoded].contains("_ = try? observationBoundaryQueueGate.abortRecordedHorizonBeforeGateCommit"))

        let encodedToFreeze = section[encoded..<freeze]
        #expect(encodedToFreeze.contains("try ensureCaptureHealthy()"))
        #expect(encodedToFreeze.contains("foregroundEvidenceIntegrityValid"))
        #expect(section[encoded..<section.endIndex].contains("abortCommittedHorizonBeforeArtifactFreeze"))
    }
}
