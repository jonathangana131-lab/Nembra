import Foundation
import Testing
@testable import NembraBluetoothCapture

/// Expected-red controller contract for the successful terminal-H -> fresh durable
/// Capture-session handoff. Software lifecycle authority only; no physical ES80 claim.
struct ForegroundCoreBluetoothCaptureControllerTerminalFreshSessionReopenContractTests {
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

    @Test("terminal resolution is retained instead of discarded after immutable artifact freeze")
    func finalizedArtifactRetainsExactResolutionForLaterRecovery() throws {
        let source = try Self.controllerSource()

        #expect(!source.contains("_ = try resolveQueuedEvidenceAfterTerminalHorizon()"))
        #expect(source.contains("pendingTerminalQueueResolution"))
        #expect(source.contains("let terminalResolution = try resolveQueuedEvidenceAfterTerminalHorizon()"))
        #expect(source.contains("pendingTerminalQueueResolution = terminalResolution"))
    }

    @Test("artifact finalization stays terminal so finalized transport teardown keeps its old authority")
    func finalizationDoesNotReopenBeforeTransportTeardown() throws {
        let source = try Self.controllerSource()
        let start = try #require(
            source.range(of: "    public func encodedFinalizedObservationHorizonJSON(")?.lowerBound
        )
        let end = try #require(
            source.range(of: "    private func beginTargetSessionIfNeeded", range: start..<source.endIndex)?.lowerBound
        )
        let finalization = source[start..<end]

        #expect(!finalization.contains("reopenAfterTerminalQueueResolution"))
        #expect(finalization.contains("lastFinalizedArtifactAuthority = committedHorizon.authority"))
    }

    @Test("fresh-session reopen proves applied chronology and waits out same-target terminal callback quarantine")
    func freshRecoveryConsumesExactAppliedResolution() throws {
        let source = try Self.controllerSource()

        // The old same-target helper deliberately returns while a recorder exists and
        // calls raw reset, so it cannot be the terminal-recovery path. Recovery needs
        // an explicit fresh durable recorder/session before reopening the preserved gate.
        #expect(source.contains("guard !isSelectedTargetAwaitingTerminalCallback else"))
        #expect(source.contains("reopenAfterTerminalQueueResolution("))
        #expect(source.contains("currentResolvedThroughQueueSequence: lastResolvedEventSequence"))
        #expect(source.contains("currentLastEnqueuedEventSequence: lastEnqueuedEventSequence"))
        #expect(source.contains("freshTargetSessionGeneration: targetSessionGeneration"))
    }
}
