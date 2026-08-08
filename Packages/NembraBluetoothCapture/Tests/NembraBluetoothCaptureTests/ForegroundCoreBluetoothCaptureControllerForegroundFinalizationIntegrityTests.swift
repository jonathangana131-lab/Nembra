import Foundation
import Testing
@testable import NembraBluetoothCapture

/// Expected-red controller integration contract for foreground integrity while an
/// admitted observation Horizon is being finalized. The package already owns exact
/// pre-recorder abandonment authority; this suite pins the missing controller
/// consumption without modifying the high-contention controller itself.
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

    @Test("pre-recorder finalization failure consumes exact H abandonment authority")
    func preRecorderFailureQuarantinesExactUnusedHorizon() throws {
        let source = try Self.controllerSource()
        let section = try Self.finalizedHorizonSection(in: source)

        let beginHorizon = try #require(
            section.range(of: "let horizonAdmission = try durationPermit.beginHorizon")?.lowerBound
        )
        let drain = try #require(
            section.range(of: "await flushPendingEvents(through: horizonAdmission.queueCutoff)")?.lowerBound
        )
        let mutationAttempt = try #require(
            section.range(of: ".recordBoundaryWithMutationOutcome(on: recorder)")?.lowerBound
        )
        let abandonment = try #require(
            section.range(of: "horizonAdmission.abandonBeforeRecorderAttempt()")?.lowerBound
        )
        let quarantine = try #require(
            section.range(of: "abortHorizonBeforeRecorderAttempt")?.lowerBound
        )

        // The exact-cutoff drain is an unavoidable actor suspension. Any failure in
        // the health/authority checks after that suspension must consume the unused H
        // admission before the first recorder attempt can begin.
        #expect(beginHorizon < drain)
        #expect(drain < abandonment)
        #expect(abandonment < quarantine)
        #expect(quarantine < mutationAttempt)

        let preMutation = section[drain..<mutationAttempt]
        #expect(preMutation.contains("try ensureCaptureHealthy()"))
        #expect(preMutation.contains("try validateBoundaryAuthority(horizonAdmission.authority)"))
        #expect(preMutation.contains("abandonBeforeRecorderAttempt()"))
        #expect(preMutation.contains("abortHorizonBeforeRecorderAttempt"))
        #expect(!preMutation.contains("rejectedBeforeMutation"))
    }

    @Test("foreground loss cannot become transport-only after Horizon admission")
    func foregroundLossFailsClosingCaptureInsteadOfSilentlyPreservingIt() throws {
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
        let closingPath = method[closingStart..<closingEnd]

        // Transport callbacks after H are outside the artifact interval, but losing
        // foreground integrity is different: Experiment One requires foreground
        // integrity through finalization. The closing path must therefore distinguish
        // foreground loss from ordinary/finalized transport teardown and fail closed.
        #expect(closingPath.contains("foregroundIntegrityLoss"))
        #expect(closingPath.contains("failCapture"))
    }

    @Test("foreground loss observed during recorder or JSON awaits is checked before promotion")
    func suspendedFinalizationRechecksHealthAtEachDurabilityPromotion() throws {
        let source = try Self.controllerSource()
        let section = try Self.finalizedHorizonSection(in: source)

        let mutationAttempt = try #require(
            section.range(of: ".recordBoundaryWithMutationOutcome(on: recorder)")?.lowerBound
        )
        let queueCommit = try #require(
            section.range(of: "recordedHorizon.markBoundaryRecorded", range: mutationAttempt..<section.endIndex)?.lowerBound
        )
        let encodedJSON = try #require(
            section.range(of: "recorder.encodedJSON", range: queueCommit..<section.endIndex)?.lowerBound
        )
        let freeze = try #require(
            section.range(of: "committedHorizon.completeHorizonArtifactFreeze", range: encodedJSON..<section.endIndex)?.lowerBound
        )

        let recordedToCommit = section[mutationAttempt..<queueCommit]
        let encodedToFreeze = section[encodedJSON..<freeze]

        // Foreground loss can arrive while either recorder actor await is suspended.
        // A successful H append is durable evidence, so health must be rechecked
        // before queue promotion and any failure must flow through recorded-H
        // quarantine. Likewise JSON materialization must recheck health before freeze
        // so committed-H quarantine owns that partial state.
        #expect(recordedToCommit.contains("try ensureCaptureHealthy()"))
        #expect(section[mutationAttempt..<encodedJSON].contains("abortRecordedHorizonBeforeGateCommit"))
        #expect(encodedToFreeze.contains("try ensureCaptureHealthy()"))
        #expect(section[encodedJSON..<section.endIndex].contains("abortCommittedHorizonBeforeArtifactFreeze"))
    }
}
