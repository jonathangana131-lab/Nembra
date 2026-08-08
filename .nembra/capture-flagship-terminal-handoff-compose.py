from pathlib import Path

gate = Path("Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/PassiveCoreBluetoothObservationBoundaryQueueGate.swift")
g = gate.read_text()

def gone(old: str, new: str) -> None:
    global g
    count = g.count(old)
    if count != 1:
        raise SystemExit(f"gate expected one match, found {count}: {old[:140]!r}")
    g = g.replace(old, new, 1)

gone(
'''        case cutoffNotDrained\n        case cutoffOverrun\n        case horizonArtifactNotReady\n''',
'''        case cutoffNotDrained\n        case cutoffOverrun\n        case horizonArtifactNotReady\n        case freshTargetSessionRequired\n        case freshRecorderIdentityMismatch\n        case terminalResolvedFrontierNotApplied(expected: UInt64, actual: UInt64)\n        case terminalQueueChangedAfterResolution(expected: UInt64, actual: UInt64)\n'''
)

gone(
'''    private(set) var phase: Phase = .awaitingReady\n    private var nextRevision: UInt64 = 1\n    private var committedReadyTransaction: Transaction?\n''',
'''    private(set) var phase: Phase = .awaitingReady\n    private var nextRevision: UInt64 = 1\n    private var committedReadyTransaction: Transaction?\n    /// Exact already-provisioned durable target session required after terminal\n    /// recovery. Weak reset cannot erase this one-shot generation bind.\n    private var requiredReadyTargetSessionGeneration: UInt64?\n'''
)

gone(
'''        guard processedQueueSequence == nil else {\n            throw StateError.invalidTransition\n        }\n        guard nextRevision != UInt64.max else {\n''',
'''        guard processedQueueSequence == nil else {\n            throw StateError.invalidTransition\n        }\n        if let requiredReadyTargetSessionGeneration {\n            guard authority.targetSessionGeneration == requiredReadyTargetSessionGeneration else {\n                throw StateError.freshTargetSessionRequired\n            }\n        }\n        guard nextRevision != UInt64.max else {\n'''
)

gone(
'''        let transaction = Transaction(\n            boundaryKind: .finiteAcquisitionReady,\n            queueCutoff: queueCutoff,\n            authority: authority,\n            revision: nextRevision\n        )\n        phase = .drainingReady(transaction)\n''',
'''        let transaction = Transaction(\n            boundaryKind: .finiteAcquisitionReady,\n            queueCutoff: queueCutoff,\n            authority: authority,\n            revision: nextRevision\n        )\n        requiredReadyTargetSessionGeneration = nil\n        phase = .drainingReady(transaction)\n'''
)

gone(
'''    /// Abort quarantine is intentionally irreversible in this slice. Raw FIFO\n    /// retirement alone cannot reopen lifecycle admission because retired positions\n    /// still need a separate globally-resolved frontier update. #450 owns that\n    /// producer and its successor integration must make fresh-session reopen consume\n    /// the producer-issued resolution receipt. Until then reset and Ready both fail.\n    @discardableResult\n    mutating func resetForNewCaptureSession() -> Bool {\n''',
'''    /// Reopens a successful terminal Horizon only after the controller has\n    /// installed the exact recorder whose construction earned producer-issued\n    /// fresh-session proof, applied the exact terminal resolution to its global\n    /// resolved frontier, and proved no callback advanced the FIFO tail afterward.\n    @MainActor\n    mutating func reopenAfterTerminalFreshTargetSession(\n        _ freshTargetSession: PassiveCoreBluetoothTerminalFreshTargetSession.Receipt,\n        installedRecorder: PassiveCoreBluetoothCaptureRecorder,\n        currentResolvedThroughQueueSequence: UInt64,\n        currentLastEnqueuedEventSequence: UInt64\n    ) throws {\n        guard case let .terminal(transaction) = phase else {\n            throw StateError.invalidTransition\n        }\n\n        let resolution = freshTargetSession.terminalResolution\n        guard resolution.terminalTransactionRevision == transaction.revision,\n              resolution.terminalTransactionIdentity == transaction.identity,\n              resolution.horizonQueueCutoff == transaction.queueCutoff,\n              resolution.previouslyResolvedThroughQueueSequence == transaction.queueCutoff else {\n            throw StateError.staleTransaction\n        }\n        guard resolution.terminalAuthority == transaction.authority else {\n            throw StateError.authorityChanged\n        }\n        guard freshTargetSession.recorderIdentity == ObjectIdentifier(installedRecorder) else {\n            throw StateError.freshRecorderIdentityMismatch\n        }\n        guard currentResolvedThroughQueueSequence == resolution.resolvedThroughQueueSequence else {\n            throw StateError.terminalResolvedFrontierNotApplied(\n                expected: resolution.resolvedThroughQueueSequence,\n                actual: currentResolvedThroughQueueSequence\n            )\n        }\n        guard currentLastEnqueuedEventSequence == resolution.resolvedThroughQueueSequence else {\n            throw StateError.terminalQueueChangedAfterResolution(\n                expected: resolution.resolvedThroughQueueSequence,\n                actual: currentLastEnqueuedEventSequence\n            )\n        }\n        guard freshTargetSession.targetSessionGeneration > transaction.authority.targetSessionGeneration else {\n            throw StateError.freshTargetSessionRequired\n        }\n\n        committedReadyTransaction = nil\n        requiredReadyTargetSessionGeneration = freshTargetSession.targetSessionGeneration\n        phase = .awaitingReady\n    }\n\n    /// Abort quarantine remains irreversible here. Its real-recorder producer is\n    /// separate authority and must converge without weakening terminal success.\n    @discardableResult\n    mutating func resetForNewCaptureSession() -> Bool {\n'''
)

gate.write_text(g)

controller = Path("Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/ForegroundCoreBluetoothCaptureController.swift")
s = controller.read_text()

def one(old: str, new: str) -> None:
    global s
    count = s.count(old)
    if count != 1:
        raise SystemExit(f"controller expected one match, found {count}: {old[:160]!r}")
    s = s.replace(old, new, 1)

one(
'''    private var lastFinalizedArtifactAuthority: PassiveCoreBluetoothArtifactAuthorityContext?\n    private var targetState = PassiveCoreBluetoothTargetState()\n''',
'''    private var lastFinalizedArtifactAuthority: PassiveCoreBluetoothArtifactAuthorityContext?\n    /// Exact terminal-resolution authority retained across immutable artifact return\n    /// and finalized transport teardown. It is consumed only after same-target\n    /// terminal callback quarantine clears.\n    private var pendingTerminalQueueResolution: PassiveCoreBluetoothTerminalQueueResolution.Receipt?\n    private var targetState = PassiveCoreBluetoothTargetState()\n'''
)

one(
'''    public func teardownActiveConnectionAfterFinalization() throws {\n        guard activePeripheral != nil else { return }\n        guard observationBoundaryQueueGate.isTerminal else {\n            throw ControllerError.artifactNotFinalized\n        }\n        guard let finalizedAuthority = lastFinalizedArtifactAuthority,\n              finalizedAuthority.matches(\n                targetSessionGeneration: targetSessionGeneration,\n                authorityGeneration: artifactAuthorityGeneration\n              ) else {\n            throw ControllerError.artifactNotFinalized\n        }\n        cancelActiveConnection(cause: .finalizedArtifactTeardown)\n    }\n''',
'''    public func teardownActiveConnectionAfterFinalization() throws {\n        guard observationBoundaryQueueGate.isTerminal else {\n            throw ControllerError.artifactNotFinalized\n        }\n        guard let finalizedAuthority = lastFinalizedArtifactAuthority,\n              finalizedAuthority.matches(\n                targetSessionGeneration: targetSessionGeneration,\n                authorityGeneration: artifactAuthorityGeneration\n              ) else {\n            throw ControllerError.artifactNotFinalized\n        }\n        if activePeripheral != nil {\n            cancelActiveConnection(cause: .finalizedArtifactTeardown)\n        }\n        try completeTerminalFreshTargetSessionIfEligible()\n    }\n'''
)

one(
'''            do {\n                _ = try resolveQueuedEvidenceAfterTerminalHorizon()\n            } catch {\n''',
'''            do {\n                let terminalResolution = try resolveQueuedEvidenceAfterTerminalHorizon()\n                pendingTerminalQueueResolution = terminalResolution\n            } catch {\n'''
)

one(
'''    private func beginTargetSessionIfNeeded(for identifier: UUID) throws {\n''',
'''    /// Final terminal-success handoff. Artifact finalization itself stays terminal;\n    /// this runs only after explicit finalized teardown and real same-target callback\n    /// quarantine clearance. Everything below is MainActor-synchronous.\n    private func completeTerminalFreshTargetSessionIfEligible() throws {\n        guard observationBoundaryQueueGate.isTerminal,\n              let terminalResolution = pendingTerminalQueueResolution,\n              let identifier = targetState.selectedTargetIdentifier,\n              activePeripheral == nil else { return }\n        guard !isSelectedTargetAwaitingTerminalCallback else { return }\n\n        // Receipt issuance does not mutate controller chronology. Require the exact\n        // applied resolved frontier and unchanged accepted FIFO tail before any\n        // authority transition or fresh recorder publication.\n        guard lastResolvedEventSequence == terminalResolution.resolvedThroughQueueSequence,\n              lastEnqueuedEventSequence == terminalResolution.resolvedThroughQueueSequence else {\n            throw ControllerError.captureIncomplete\n        }\n\n        let previousAuthority = currentArtifactAuthorityContext()\n        guard previousAuthority == terminalResolution.terminalAuthority else {\n            throw ControllerError.targetSessionChanged\n        }\n\n        let freshTargetSession = try PassiveCoreBluetoothTerminalFreshTargetSession.create(\n            after: terminalResolution,\n            vehicleIdentity: vehicleIdentity,\n            startedAt: Date()\n        )\n        let freshAuthority = PassiveCoreBluetoothArtifactAuthorityContext(\n            targetSessionGeneration: freshTargetSession.receipt.targetSessionGeneration,\n            authorityGeneration: 1\n        )\n\n        try artifactAuthorityFence.transition(\n            from: previousAuthority,\n            to: freshAuthority\n        )\n        targetSessionGeneration = freshAuthority.targetSessionGeneration\n        artifactAuthorityGeneration = freshAuthority.authorityGeneration\n        recorder = freshTargetSession.recorder\n        targetState.selectTarget(identifier)\n        acquisitionLedger.beginTargetSession()\n        gattIdentityRegistry.reset()\n        selectedTargetCancellationPending = false\n        foregroundEvidenceIntegrityValid = true\n        hasUsedInitialSessionIdentity = true\n        committedReadyEpoch = nil\n        lastFinalizedArtifactAuthority = nil\n\n        // No actor hop occurs between installing the recorder/authority and gate\n        // consumption. Failure is fail-closed; callers never reopen by weak reset.\n        try observationBoundaryQueueGate.reopenAfterTerminalFreshTargetSession(\n            freshTargetSession.receipt,\n            installedRecorder: freshTargetSession.recorder,\n            currentResolvedThroughQueueSequence: lastResolvedEventSequence,\n            currentLastEnqueuedEventSequence: lastEnqueuedEventSequence\n        )\n        pendingTerminalQueueResolution = nil\n    }\n\n    private func beginTargetSessionIfNeeded(for identifier: UUID) throws {\n'''
)

one(
'''        if observationBoundaryQueueGate.isTerminal || observationBoundaryBlocksArtifactMutation {\n            selectedTargetCancellationPending = false\n            if case .active = disposition {\n                clearActiveConnectionState(for: identifier)\n            }\n            return\n        }\n''',
'''        if observationBoundaryQueueGate.isTerminal || observationBoundaryBlocksArtifactMutation {\n            selectedTargetCancellationPending = false\n            if case .active = disposition {\n                clearActiveConnectionState(for: identifier)\n            }\n            if observationBoundaryQueueGate.isTerminal,\n               targetState.selectedTargetIdentifier == identifier {\n                do {\n                    try completeTerminalFreshTargetSessionIfEligible()\n                } catch {\n                    failCapture(error)\n                }\n            }\n            return\n        }\n'''
)

controller.write_text(s)

Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/ForegroundCoreBluetoothCaptureControllerTerminalFreshSessionReopenContractTests.swift").write_text(r'''import Foundation
import Testing
@testable import NembraBluetoothCapture

struct ForegroundCoreBluetoothCaptureControllerTerminalFreshSessionReopenContractTests {
    private static func controllerSource() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/NembraBluetoothCapture/ForegroundCoreBluetoothCaptureController.swift"),
            encoding: .utf8
        )
    }

    @Test("terminal resolution is retained instead of discarded after immutable freeze")
    func retainsExactTerminalResolution() throws {
        let source = try Self.controllerSource()
        #expect(!source.contains("_ = try resolveQueuedEvidenceAfterTerminalHorizon()"))
        #expect(source.contains("pendingTerminalQueueResolution"))
        #expect(source.contains("let terminalResolution = try resolveQueuedEvidenceAfterTerminalHorizon()"))
        #expect(source.contains("pendingTerminalQueueResolution = terminalResolution"))
    }

    @Test("finalization remains terminal and recovery is post-teardown")
    func finalizationDoesNotPrematurelyReopen() throws {
        let source = try Self.controllerSource()
        let start = try #require(source.range(of: "public func encodedFinalizedObservationHorizonJSON(")?.lowerBound)
        let end = try #require(source.range(of: "\n    private func completeTerminalFreshTargetSessionIfEligible", range: start..<source.endIndex)?.lowerBound)
        #expect(!source[start..<end].contains("reopenAfterTerminalFreshTargetSession"))
        #expect(source.contains("teardownActiveConnectionAfterFinalization"))
    }

    @Test("fresh reopen proves applied chronology, callback clearance, and exact installed recorder")
    func freshRecoveryConsumesExactAuthority() throws {
        let source = try Self.controllerSource()
        let start = try #require(source.range(of: "private func completeTerminalFreshTargetSessionIfEligible()")?.lowerBound)
        let end = try #require(source.range(of: "\n    private func beginTargetSessionIfNeeded", range: start..<source.endIndex)?.lowerBound)
        let section = source[start..<end]
        #expect(section.contains("guard !isSelectedTargetAwaitingTerminalCallback else"))
        #expect(section.contains("lastResolvedEventSequence == terminalResolution.resolvedThroughQueueSequence"))
        #expect(section.contains("lastEnqueuedEventSequence == terminalResolution.resolvedThroughQueueSequence"))
        #expect(section.contains("PassiveCoreBluetoothTerminalFreshTargetSession.create("))
        #expect(section.contains("recorder = freshTargetSession.recorder"))
        #expect(section.contains("reopenAfterTerminalFreshTargetSession("))
        #expect(section.contains("installedRecorder: freshTargetSession.recorder"))
        #expect(section.contains("currentResolvedThroughQueueSequence: lastResolvedEventSequence"))
        #expect(section.contains("currentLastEnqueuedEventSequence: lastEnqueuedEventSequence"))
    }

    @Test("real terminal callback releases same-target quarantine before recovery")
    func callbackCompletesQuarantineBeforeRecovery() throws {
        let source = try Self.controllerSource()
        let start = try #require(source.range(of: "private func handleDisconnect(")?.lowerBound)
        let end = try #require(source.range(of: "\n}\n\nextension ForegroundCoreBluetoothCaptureController", range: start..<source.endIndex)?.lowerBound)
        let section = source[start..<end]
        let complete = try #require(section.range(of: "targetState.completeDisconnect(from: identifier)")?.lowerBound)
        let recovery = try #require(section.range(of: "completeTerminalFreshTargetSessionIfEligible()", range: complete..<section.endIndex)?.lowerBound)
        #expect(complete < recovery)
    }
}
''')
