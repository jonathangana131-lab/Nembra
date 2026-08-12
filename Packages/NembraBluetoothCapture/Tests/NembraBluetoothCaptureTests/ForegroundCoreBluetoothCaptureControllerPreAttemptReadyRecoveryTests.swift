import Foundation
import Testing

@Suite("Foreground CoreBluetooth pre-attempt Ready recovery")
struct ForegroundCoreBluetoothCaptureControllerPreAttemptReadyRecoveryTests {
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

    @Test("allocated Ready quarantines before first recorder attempt when drained health fails")
    func controllerConsumesExactUnusedReadyBeforeRecorderAttempt() throws {
        let source = try Self.controllerSource()
        let ready = try #require(source.range(of: "let admission = try PassiveCoreBluetoothObservationBoundaryTransactionDecision.beginReady("))
        let flush = try #require(source.range(
            of: "await self.flushPendingEvents(through: admission.queueCutoff)",
            range: ready.lowerBound..<source.endIndex
        ))
        let failure = try #require(source.range(
            of: "let preAttemptFailure = error",
            range: flush.lowerBound..<source.endIndex
        ))
        let abandonment = try #require(source.range(
            of: "let abandonment = try admission.abandonBeforeRecorderAttempt()",
            range: failure.lowerBound..<source.endIndex
        ))
        let quarantine = try #require(source.range(
            of: "try self.observationBoundaryQueueGate.abortReadyBeforeRecorderAttempt(",
            range: abandonment.lowerBound..<source.endIndex
        ))
        let recorderAttempt = try #require(source.range(
            of: "admission.recordBoundaryWithMutationOutcome(on: recorder)",
            range: quarantine.lowerBound..<source.endIndex
        ))

        #expect(ready.lowerBound < flush.lowerBound)
        #expect(flush.lowerBound < failure.lowerBound)
        #expect(failure.lowerBound < abandonment.lowerBound)
        #expect(abandonment.lowerBound < quarantine.lowerBound)
        #expect(quarantine.lowerBound < recorderAttempt.lowerBound)
    }

    @Test("pre-attempt Ready abandonment stays distinct from mutation-point rejection")
    func controllerPreservesDistinctZeroReadyOrigins() throws {
        let source = try Self.controllerSource()
        #expect(source.components(separatedBy: "admission.abandonBeforeRecorderAttempt()").count - 1 == 1)
        #expect(source.components(separatedBy: "abortReadyBeforeRecorderAttempt(").count - 1 == 1)
        #expect(source.contains("case let .rejectedBeforeMutation(rejection):"))
        #expect(source.contains("abortUncommittedReady(after: rejection)"))
    }
}
