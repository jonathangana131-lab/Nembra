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
        let clearStart = try #require(controller.range(of: "    private func clearActiveConnectionState(for identifier: UUID) {")?.lowerBound)
        let clearEnd = try #require(controller.range(of: "    private func ensureCaptureHealthy() throws", range: clearStart..<controller.endIndex)?.lowerBound)
        let clear = controller[clearStart..<clearEnd]
        let idle = try #require(clear.range(of: "connectionPhase = .idle")?.lowerBound)
        let schedule = try #require(clear.range(of: "scheduleAbortedFreshTargetSessionRecoveryIfNeeded()")?.lowerBound)
        #expect(idle < schedule)
        #expect(controller.contains("captureFailed = false"))
        #expect(controller.contains("case .abortQuarantined"))
    }
}