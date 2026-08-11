import Foundation
import Testing

@Suite("Foreground CoreBluetooth Ready foreground pre-attempt recovery")
struct ForegroundCoreBluetoothCaptureControllerReadyForegroundPreAttemptTests {
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

    @Test("Ready proves foreground integrity after FIFO drain and before recorder attempt")
    func readyRechecksForegroundBeforeRecorderMutation() throws {
        let source = try Self.controllerSource()
        let ready = try #require(source.range(of: "let admission = try PassiveCoreBluetoothObservationBoundaryTransactionDecision.beginReady("))
        let flush = try #require(source.range(
            of: "await self.flushPendingEvents(through: admission.queueCutoff)",
            range: ready.lowerBound..<source.endIndex
        ))
        let foreground = try #require(source.range(
            of: "try self.requireForegroundEvidenceIntegrity()",
            range: flush.lowerBound..<source.endIndex
        ))
        let health = try #require(source.range(
            of: "try self.ensureCaptureHealthy()",
            range: foreground.lowerBound..<source.endIndex
        ))
        let abandonment = try #require(source.range(
            of: "let abandonment = try admission.abandonBeforeRecorderAttempt()",
            range: health.lowerBound..<source.endIndex
        ))
        let quarantine = try #require(source.range(
            of: "try self.observationBoundaryQueueGate.abortReadyBeforeRecorderAttempt(",
            range: abandonment.lowerBound..<source.endIndex
        ))
        let recorderAttempt = try #require(source.range(
            of: "admission.recordBoundaryWithMutationOutcome(on: recorder)",
            range: quarantine.lowerBound..<source.endIndex
        ))

        #expect(flush.lowerBound < foreground.lowerBound)
        #expect(foreground.lowerBound < health.lowerBound)
        #expect(health.lowerBound < abandonment.lowerBound)
        #expect(abandonment.lowerBound < quarantine.lowerBound)
        #expect(quarantine.lowerBound < recorderAttempt.lowerBound)
    }
}
