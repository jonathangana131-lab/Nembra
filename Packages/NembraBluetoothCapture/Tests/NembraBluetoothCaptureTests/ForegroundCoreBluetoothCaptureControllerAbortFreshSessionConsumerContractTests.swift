import Foundation
import Testing

@Suite("Abort quarantine exact fresh-session consumer contract")
struct ForegroundCoreBluetoothCaptureControllerAbortFreshSessionConsumerContractTests {
    private static func packageSource(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    @Test("abort quarantine cannot reopen without the producer-issued real recorder and applied FIFO resolution")
    func exactAbortFreshSessionAuthorityMustReachTheLiveGate() throws {
        let gate = try Self.packageSource("Sources/NembraBluetoothCapture/PassiveCoreBluetoothObservationBoundaryQueueGate.swift")
        #expect(gate.contains("reopenAfterAbortedFreshTargetSession("))
        #expect(gate.contains("PassiveCoreBluetoothAbortedFreshTargetSession.Receipt"))
        #expect(gate.contains("installedRecorder: PassiveCoreBluetoothCaptureRecorder"))
        #expect(gate.contains("currentResolvedThroughQueueSequence: UInt64"))
        #expect(gate.contains("currentLastEnqueuedEventSequence: UInt64"))
        #expect(gate.contains("freshRecorderIdentityMismatch"))
        #expect(gate.contains("requiredReadyTargetSessionGeneration = freshTargetSession.targetSessionGeneration"))
    }

    @Test("foreground controller resolves retired FIFO and installs the exact fresh recorder before reopening")
    func liveControllerMustConsumeAbortRecoveryWithoutRelabelingRetiredEvidence() throws {
        let controller = try Self.packageSource("Sources/NembraBluetoothCapture/ForegroundCoreBluetoothCaptureController.swift")
        #expect(controller.contains("PassiveCoreBluetoothAbortedObservationQueueRetirement.retire("))
        #expect(controller.contains("PassiveCoreBluetoothAbortedQueueResolution.resolve("))
        #expect(controller.contains("lastResolvedEventSequence = resolution.resolvedThroughQueueSequence"))
        #expect(controller.contains("PassiveCoreBluetoothAbortedFreshTargetSession.create("))
        #expect(controller.contains("recorder = freshSession.recorder"))
        #expect(controller.contains("reopenAfterAbortedFreshTargetSession("))
        #expect(controller.contains("installedRecorder: freshSession.recorder"))
    }

    @Test("aborted recovery waits for the real terminal callback and idle transition before clearing failure")
    func recoveryCannotBypassTransportOrQueueQuarantine() throws {
        let controller = try Self.packageSource("Sources/NembraBluetoothCapture/ForegroundCoreBluetoothCaptureController.swift")
        #expect(controller.contains("isSelectedTargetAwaitingTerminalCallback"))
        #expect(controller.contains("eventDrainTask == nil"))
        #expect(controller.contains("scheduleAbortedFreshTargetSessionRecoveryIfNeeded()"))
        let idle = try #require(controller.range(of: "connectionPhase = .idle"))
        let schedule = try #require(controller.range(of: "scheduleAbortedFreshTargetSessionRecoveryIfNeeded()", range: idle.upperBound..<controller.endIndex))
        #expect(idle.lowerBound < schedule.lowerBound)
        #expect(controller.contains("captureFailed = false"))
        #expect(controller.contains("case .abortQuarantined"))
    }
}
