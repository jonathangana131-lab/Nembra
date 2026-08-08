import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Foreground controller terminal fresh-session consumer")
struct ForegroundCoreBluetoothCaptureControllerTerminalFreshSessionConsumerTests {
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

    @Test("immutable finalization retains terminal resolution without reopening")
    func finalizationRetainsResolutionButStaysTerminal() throws {
        let source = try Self.controllerSource()
        #expect(source.contains("private var pendingTerminalQueueResolution: PassiveCoreBluetoothTerminalQueueResolution.Receipt?"))
        #expect(source.contains("let terminalResolution = try resolveQueuedEvidenceAfterTerminalHorizon()"))
        #expect(source.contains("pendingTerminalQueueResolution = terminalResolution"))
        #expect(!source.contains("_ = try resolveQueuedEvidenceAfterTerminalHorizon()"))

        let start = try #require(
            source.range(of: "    public func encodedFinalizedObservationHorizonJSON(")?.lowerBound
        )
        let end = try #require(
            source.range(of: "    private func completeTerminalFreshTargetSessionIfReady(", range: start..<source.endIndex)?.lowerBound
        )
        let finalization = source[start..<end]
        #expect(!finalization.contains("reopenAfterTerminalFreshTargetSession"))
        #expect(finalization.contains("lastFinalizedArtifactAuthority = committedHorizon.authority"))
    }

    @Test("fresh recorder publication and gate reopen are one synchronous MainActor transition")
    func freshConsumerUsesExactInstalledRecorderAndAppliedChronology() throws {
        let source = try Self.controllerSource()
        let start = try #require(
            source.range(of: "    private func completeTerminalFreshTargetSessionIfReady(")?.lowerBound
        )
        let end = try #require(
            source.range(of: "    private func beginTargetSessionIfNeeded", range: start..<source.endIndex)?.lowerBound
        )
        let recovery = source[start..<end]

        #expect(recovery.contains("guard !isSelectedTargetAwaitingTerminalCallback else"))
        #expect(recovery.contains("PassiveCoreBluetoothTerminalFreshTargetSession.create("))
        #expect(recovery.contains("try artifactAuthorityFence.transition("))
        #expect(recovery.contains("recorder = freshSession.recorder"))
        #expect(recovery.contains("reopenAfterTerminalFreshTargetSession("))
        #expect(recovery.contains("freshSession.receipt"))
        #expect(recovery.contains("installedRecorder: freshSession.recorder"))
        #expect(recovery.contains("currentResolvedThroughQueueSequence: lastResolvedEventSequence"))
        #expect(recovery.contains("currentLastEnqueuedEventSequence: lastEnqueuedEventSequence"))
        #expect(recovery.contains("pendingTerminalQueueResolution = nil"))

        let recorderInstall = try #require(recovery.range(of: "recorder = freshSession.recorder"))
        let gateReopen = try #require(recovery.range(of: "reopenAfterTerminalFreshTargetSession("))
        #expect(recorderInstall.lowerBound < gateReopen.lowerBound)
    }

    @Test("recovery is downstream of finalized teardown and real terminal callback")
    func teardownAndTerminalCallbackDriveRecovery() throws {
        let source = try Self.controllerSource()

        let teardownStart = try #require(
            source.range(of: "    public func teardownActiveConnectionAfterFinalization() throws {")?.lowerBound
        )
        let teardownEnd = try #require(
            source.range(of: "    private func cancelActiveConnection", range: teardownStart..<source.endIndex)?.lowerBound
        )
        let teardown = source[teardownStart..<teardownEnd]
        #expect(teardown.contains("_ = try completeTerminalFreshTargetSessionIfReady()"))
        #expect(teardown.contains("guard observationBoundaryQueueGate.isTerminal else"))

        let disconnectStart = try #require(
            source.range(of: "    private func handleDisconnect(")?.lowerBound
        )
        let disconnect = source[disconnectStart...]
        #expect(disconnect.contains("let disposition = targetState.completeDisconnect(from: identifier)"))
        #expect(disconnect.contains("if observationBoundaryQueueGate.isTerminal || observationBoundaryBlocksArtifactMutation"))
        #expect(disconnect.contains("_ = try completeTerminalFreshTargetSessionIfReady()"))
    }
}
