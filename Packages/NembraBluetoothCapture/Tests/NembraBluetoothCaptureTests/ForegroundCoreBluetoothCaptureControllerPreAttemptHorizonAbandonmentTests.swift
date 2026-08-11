import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Foreground CoreBluetooth pre-attempt Horizon abandonment")
struct ForegroundCoreBluetoothCaptureControllerPreAttemptHorizonAbandonmentTests {
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

    private static func finalizedHorizonSection() throws -> Substring {
        let source = try controllerSource()
        let functionStart = try #require(
            source.range(of: "    public func encodedFinalizedObservationHorizonJSON(")?.lowerBound
        )
        let functionEnd = try #require(
            source.range(
                of: "    private func beginTargetSessionIfNeeded",
                range: functionStart..<source.endIndex
            )?.lowerBound
        )
        return source[functionStart..<functionEnd]
    }

    @Test("allocated H is exactly quarantined before the first recorder attempt")
    func preRecorderFailureConsumesUnusedAdmissionBeforeRecorderAttempt() throws {
        let section = try Self.finalizedHorizonSection()
        let begin = try #require(
            section.range(of: "let horizonAdmission = try durationPermit.beginHorizon(")?.lowerBound
        )
        let flush = try #require(
            section.range(
                of: "await flushPendingEvents(through: horizonAdmission.queueCutoff)",
                range: begin..<section.endIndex
            )?.lowerBound
        )
        let preservedFailure = try #require(
            section.range(
                of: "let preAttemptFailure = error",
                range: flush..<section.endIndex
            )?.lowerBound
        )
        let abandonment = try #require(
            section.range(
                of: "let abandonment = try horizonAdmission.abandonBeforeRecorderMutation()",
                range: preservedFailure..<section.endIndex
            )?.lowerBound
        )
        let quarantine = try #require(
            section.range(
                of: "try observationBoundaryQueueGate.abortUncommittedHorizon(after: abandonment)",
                range: abandonment..<section.endIndex
            )?.lowerBound
        )
        let firstRecorderAttempt = try #require(
            section.range(
                of: ".recordBoundaryWithMutationOutcome(on: recorder)",
                range: quarantine..<section.endIndex
            )?.lowerBound
        )

        #expect(begin < flush)
        #expect(flush < preservedFailure)
        #expect(preservedFailure < abandonment)
        #expect(abandonment < quarantine)
        #expect(quarantine < firstRecorderAttempt)

        let preAttemptSection = section[begin..<firstRecorderAttempt]
        #expect(!preAttemptSection.contains("try? horizonAdmission.abandonBeforeRecorderMutation()"))
        #expect(!preAttemptSection.contains("try? observationBoundaryQueueGate.abortUncommittedHorizon(after: abandonment)"))
    }

    @Test("pre-attempt abandonment stays distinct from mutation-point rejection")
    func preservesDistinctZeroMutationAuthorities() throws {
        let section = try Self.finalizedHorizonSection()

        #expect(section.components(separatedBy: "abandonBeforeRecorderMutation()").count - 1 == 1)
        #expect(section.contains("case let .rejectedBeforeMutation(rejection):"))
        #expect(section.contains("abortUncommittedHorizon(after: rejection)"))
        #expect(section.contains("abortUncommittedHorizon(after: abandonment)"))
    }
}
