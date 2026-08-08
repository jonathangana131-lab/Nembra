import Foundation
import Testing

@Suite("Abort quarantine exact fresh-session consumer contract")
struct ForegroundCoreBluetoothCaptureControllerAbortFreshSessionConsumerContractTests {
    private static func packageSource(_ relativePath: String) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile
            .deletingLastPathComponent() // NembraBluetoothCaptureTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // package root
        return try String(
            contentsOf: packageRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    @Test("abort quarantine cannot reopen without the producer-issued real recorder and applied FIFO resolution")
    func exactAbortFreshSessionAuthorityMustReachTheLiveGate() throws {
        let gate = try Self.packageSource(
            "Sources/NembraBluetoothCapture/PassiveCoreBluetoothObservationBoundaryQueueGate.swift"
        )

        #expect(gate.contains("reopenAfterAbortedFreshTargetSession("))
        #expect(gate.contains("PassiveCoreBluetoothAbortedFreshTargetSession.Receipt"))
        #expect(gate.contains("installedRecorder: PassiveCoreBluetoothCaptureRecorder"))
        #expect(gate.contains("currentResolvedThroughQueueSequence: UInt64"))
        #expect(gate.contains("currentLastEnqueuedEventSequence: UInt64"))
        #expect(gate.contains("freshRecorderIdentityMismatch"))
        #expect(gate.contains("requiredReadyTargetSessionGeneration = freshTargetSession.targetSessionGeneration"))
    }

    @Test("foreground controller must complete aborted FIFO resolution into the exact fresh durable session")
    func liveControllerMustConsumeAbortRecoveryWithoutRelabelingRetiredEvidence() throws {
        let controller = try Self.packageSource(
            "Sources/NembraBluetoothCapture/ForegroundCoreBluetoothCaptureController.swift"
        )

        #expect(controller.contains("PassiveCoreBluetoothAbortedQueueResolution.resolve("))
        #expect(controller.contains("PassiveCoreBluetoothAbortedFreshTargetSession.create("))
        #expect(controller.contains("reopenAfterAbortedFreshTargetSession("))
        #expect(controller.contains("lastResolvedEventSequence"))
        #expect(controller.contains("lastEnqueuedEventSequence"))
    }
}
