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

    @Test("foreground controller resolves retired FIFO and installs the exact fresh recorder before reopening")
    func liveControllerMustConsumeAbortRecoveryWithoutRelabelingRetiredEvidence() throws {
        let controller = try Self.packageSource(
            "Sources/NembraBluetoothCapture/ForegroundCoreBluetoothCaptureController.swift"
        )

        #expect(controller.contains("PassiveCoreBluetoothAbortedObservationQueueRetirement.retire("))
        #expect(controller.contains("PassiveCoreBluetoothAbortedQueueResolution.resolve("))
        #expect(controller.contains("lastResolvedEventSequence = resolution.resolvedThroughQueueSequence"))
        #expect(controller.contains("PassiveCoreBluetoothAbortedFreshTargetSession.create("))
        #expect(controller.contains("recorder = freshSession.recorder"))
        #expect(controller.contains("reopenAfterAbortedFreshTargetSession("))
        #expect(controller.contains("installedRecorder: freshSession.recorder"))
        #expect(controller.contains("currentResolvedThroughQueueSequence: lastResolvedEventSequence"))
        #expect(controller.contains("currentLastEnqueuedEventSequence: lastEnqueuedEventSequence"))
    }

    @Test("aborted recovery waits for the real terminal callback and idle drain before clearing failure")
    func recoveryCannotBypassTransportOrQueueQuarantine() throws {
        let controller = try Self.packageSource(
            "Sources/NembraBluetoothCapture/ForegroundCoreBluetoothCaptureController.swift"
        )

        #expect(controller.contains("isSelectedTargetAwaitingTerminalCallback"))
        #expect(controller.contains("eventDrainTask == nil"))
        #expect(controller.contains("scheduleAbortedFreshTargetSessionRecoveryIfNeeded()"))
        #expect(controller.contains("case .abortQuarantined"))

        let disconnectStart = try #require(controller.range(of: "    private func handleDisconnect("))
        let disconnect = controller[disconnectStart.lowerBound...]
        let idleOffset = try #require(disconnect.range(of: "clearActiveConnectionState(for: identifier)"))
        let scheduleOffset = try #require(
            disconnect.range(
                of: "scheduleAbortedFreshTargetSessionRecoveryIfNeeded()",
                range: idleOffset.upperBound..<disconnect.endIndex
            )
        )
        #expect(idleOffset.lowerBound < scheduleOffset.lowerBound)

        let recoveryStart = try #require(controller.range(of: "    private func completeAbortedFreshTargetSessionIfReady("))
        let recoveryEnd = try #require(
            controller.range(
                of: "    private func beginTargetSessionIfNeeded",
                range: recoveryStart.upperBound..<controller.endIndex
            )
        )
        let recovery = controller[recoveryStart.lowerBound..<recoveryEnd.lowerBound]
        let installOffset = try #require(recovery.range(of: "recorder = freshSession.recorder"))
        let clearFailureOffset = try #require(recovery.range(of: "captureFailed = false"))
        #expect(installOffset.lowerBound < clearFailureOffset.lowerBound)
    }
}
