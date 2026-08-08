import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Foreground controller Ready + terminal recovery convergence")
struct ForegroundCoreBluetoothCaptureControllerReadyTerminalRecoveryIntegrationTests {
    private static func controllerSource() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/NembraBluetoothCapture/ForegroundCoreBluetoothCaptureController.swift"),
            encoding: .utf8
        )
    }

    @Test("Ready pre-recorder failure consumes producer-issued zero-mutation abandonment")
    func readyPreAttemptRecoveryPrecedesRecorderMutation() throws {
        let source = try Self.controllerSource()
        let start = try #require(source.range(of: "private func beginFiniteAcquisitionReadyBoundaryIfNeeded()")?.lowerBound)
        let end = try #require(source.range(of: "\n    private func requireForegroundEvidenceIntegrity", range: start..<source.endIndex)?.lowerBound)
        let section = source[start..<end]
        let drain = try #require(section.range(of: "flushPendingEvents(through: admission.queueCutoff)")?.lowerBound)
        let abandonment = try #require(section.range(of: "admission.abandonBeforeRecorderMutation()")?.lowerBound)
        let quarantine = try #require(section.range(of: "abortUncommittedReady(", range: abandonment..<section.endIndex)?.lowerBound)
        let recorder = try #require(section.range(of: "recordBoundaryWithMutationOutcome(on: recorder)", range: quarantine..<section.endIndex)?.lowerBound)
        #expect(drain < abandonment)
        #expect(abandonment < quarantine)
        #expect(quarantine < recorder)
        #expect(section[drain..<recorder].contains("requireForegroundEvidenceIntegrity()"))
        #expect(section[drain..<recorder].contains("validateBoundaryAuthority(admission.authority)"))
    }

    @Test("terminal resolution survives artifact return and finalizer does not reopen")
    func terminalResolutionIsRetainedUntilFinalizedTransportRecovery() throws {
        let source = try Self.controllerSource()
        #expect(!source.contains("_ = try resolveQueuedEvidenceAfterTerminalHorizon()"))
        #expect(source.contains("pendingTerminalQueueResolution"))
        #expect(source.contains("let terminalResolution = try resolveQueuedEvidenceAfterTerminalHorizon()"))
        #expect(source.contains("pendingTerminalQueueResolution = terminalResolution"))

        let start = try #require(source.range(of: "public func encodedFinalizedObservationHorizonJSON(")?.lowerBound)
        let end = try #require(source.range(of: "\n    private func completeTerminalFreshTargetSessionIfEligible", range: start..<source.endIndex)?.lowerBound)
        #expect(!source[start..<end].contains("reopenAfterTerminalFreshTargetSession"))
    }

    @Test("fresh terminal reopen requires callback quarantine cleared and exact installed recorder")
    func terminalFreshSessionHandoffConsumesExactProducerAuthority() throws {
        let source = try Self.controllerSource()
        let start = try #require(source.range(of: "private func completeTerminalFreshTargetSessionIfEligible()")?.lowerBound)
        let end = try #require(source.range(of: "\n    private func beginTargetSessionIfNeeded", range: start..<source.endIndex)?.lowerBound)
        let section = source[start..<end]
        #expect(section.contains("guard !isSelectedTargetAwaitingTerminalCallback else"))
        #expect(section.contains("PassiveCoreBluetoothTerminalFreshTargetSession.create("))
        #expect(section.contains("recorder = freshTargetSession.recorder"))
        #expect(section.contains("artifactAuthorityFence.transition("))
        #expect(section.contains("reopenAfterTerminalFreshTargetSession("))
        #expect(section.contains("installedRecorder: freshTargetSession.recorder"))
        #expect(section.contains("currentResolvedThroughQueueSequence: lastResolvedEventSequence"))
        #expect(section.contains("currentLastEnqueuedEventSequence: lastEnqueuedEventSequence"))
        #expect(section.contains("pendingTerminalQueueResolution = nil"))
    }

    @Test("terminal callback path is the automatic recovery trigger after finalized teardown")
    func terminalCallbackConsumesRecoveryOnlyAfterTargetStateCompletesDisconnect() throws {
        let source = try Self.controllerSource()
        let start = try #require(source.range(of: "private func handleDisconnect(")?.lowerBound)
        let end = try #require(source.range(of: "\n}\n\nextension ForegroundCoreBluetoothCaptureController", range: start..<source.endIndex)?.lowerBound)
        let section = source[start..<end]
        let complete = try #require(section.range(of: "targetState.completeDisconnect(from: identifier)")?.lowerBound)
        let recovery = try #require(section.range(of: "completeTerminalFreshTargetSessionIfEligible()", range: complete..<section.endIndex)?.lowerBound)
        #expect(complete < recovery)
        #expect(section[complete..<recovery].contains("observationBoundaryQueueGate.isTerminal"))
    }
}
