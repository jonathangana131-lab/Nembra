import Foundation
import Testing

@Suite("Foreground CoreBluetooth pre-attempt Horizon recovery")
struct ForegroundCoreBluetoothCaptureControllerPreAttemptHorizonRecoveryTests {
    private static func controllerSource() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile
            .deletingLastPathComponent() // NembraBluetoothCaptureTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // package root
        return try String(
            contentsOf: packageRoot
                .appendingPathComponent("Sources")
                .appendingPathComponent("NembraBluetoothCapture")
                .appendingPathComponent("ForegroundCoreBluetoothCaptureController.swift"),
            encoding: .utf8
        )
    }

    @Test("allocated H is quarantined before the first recorder attempt when pre-attempt work fails")
    func controllerConsumesUnusedAdmissionBeforeRecorderAttempt() throws {
        let source = try Self.controllerSource()
        let horizon = try #require(
            source.range(of: "let horizonAdmission = try durationPermit.beginHorizon(")
        )
        let flush = try #require(
            source.range(
                of: "await flushPendingEvents(through: horizonAdmission.queueCutoff)",
                range: horizon.lowerBound..<source.endIndex
            )
        )
        let abandonment = try #require(
            source.range(
                of: "let abandonment = try horizonAdmission.abandonBeforeRecorderMutation()",
                range: flush.lowerBound..<source.endIndex
            )
        )
        let quarantine = try #require(
            source.range(
                of: "try observationBoundaryQueueGate.abortUncommittedHorizon(",
                range: abandonment.lowerBound..<source.endIndex
            )
        )
        let abandonmentArgument = try #require(
            source.range(
                of: "after: abandonment",
                range: quarantine.lowerBound..<source.endIndex
            )
        )
        let recorderAttempt = try #require(
            source.range(
                of: ".recordBoundaryWithMutationOutcome(on: recorder)",
                range: abandonmentArgument.lowerBound..<source.endIndex
            )
        )

        #expect(horizon.lowerBound < flush.lowerBound)
        #expect(flush.lowerBound < abandonment.lowerBound)
        #expect(abandonment.lowerBound < quarantine.lowerBound)
        #expect(quarantine.lowerBound < abandonmentArgument.lowerBound)
        #expect(abandonmentArgument.lowerBound < recorderAttempt.lowerBound)
        #expect(source.contains("let preAttemptFailure = error"))
    }

    @Test("pre-attempt abandonment stays distinct from mutation-point rejection")
    func controllerPreservesDistinctZeroMutationOrigins() throws {
        let source = try Self.controllerSource()

        #expect(source.components(separatedBy: "abandonBeforeRecorderMutation()").count - 1 == 1)
        #expect(source.contains("case let .rejectedBeforeMutation(rejection):"))
        #expect(source.contains("abortUncommittedHorizon(after: rejection)"))
    }
}
