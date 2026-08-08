from pathlib import Path

PATH = Path("Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/ForegroundCoreBluetoothCaptureController.swift")
text = PATH.read_text()


def replace_once(old: str, new: str, label: str) -> None:
    global text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    text = text.replace(old, new, 1)


replace_once(
    "    private var lastFinalizedArtifactAuthority: PassiveCoreBluetoothArtifactAuthorityContext?\n",
    "    private var lastFinalizedArtifactAuthority: PassiveCoreBluetoothArtifactAuthorityContext?\n"
    "    /// Exact successful-terminal FIFO resolution retained after immutable artifact\n"
    "    /// return. It remains inert until transport teardown crosses the real terminal\n"
    "    /// CoreBluetooth callback and a producer-created fresh recorder is installed.\n"
    "    private var pendingTerminalQueueResolution: PassiveCoreBluetoothTerminalQueueResolution.Receipt?\n",
    "terminal resolution property",
)

replace_once(
    "                _ = try resolveQueuedEvidenceAfterTerminalHorizon()\n",
    "                let terminalResolution = try resolveQueuedEvidenceAfterTerminalHorizon()\n"
    "                pendingTerminalQueueResolution = terminalResolution\n",
    "retain final terminal resolution",
)

replace_once(
    "    public func teardownActiveConnectionAfterFinalization() throws {\n"
    "        guard activePeripheral != nil else { return }\n",
    "    public func teardownActiveConnectionAfterFinalization() throws {\n"
    "        guard activePeripheral != nil else {\n"
    "            _ = try completeTerminalFreshTargetSessionIfReady()\n"
    "            return\n"
    "        }\n",
    "finalized teardown no-transport recovery",
)

insertion_marker = "    private func beginTargetSessionIfNeeded(for identifier: UUID) throws {\n"
recovery = '''    /// Consumes one sealed terminal lifecycle into the exact next durable recorder only
    /// after transport is idle and same-target terminal-callback quarantine has cleared.
    /// There is deliberately no actor suspension from recorder/authority publication through
    /// gate consumption, so a late callback cannot be relabeled into the fresh session.
    @discardableResult
    private func completeTerminalFreshTargetSessionIfReady(
        startedAt: Date = Date()
    ) throws -> Bool {
        guard observationBoundaryQueueGate.isTerminal,
              let terminalResolution = pendingTerminalQueueResolution else {
            return false
        }
        guard let finalizedAuthority = lastFinalizedArtifactAuthority,
              finalizedAuthority == terminalResolution.terminalAuthority,
              currentArtifactAuthorityContext() == terminalResolution.terminalAuthority else {
            throw ControllerError.artifactNotFinalized
        }
        guard !artifactReadBarrier.isActive,
              observationBoundaryTask == nil,
              activePeripheral == nil,
              connectionPhase == .idle else {
            return false
        }
        guard targetState.selectedTargetIdentifier != nil else {
            throw ControllerError.targetNotSelected
        }
        guard !isSelectedTargetAwaitingTerminalCallback else {
            return false
        }
        guard pendingEvents.isEmpty,
              lastResolvedEventSequence == terminalResolution.resolvedThroughQueueSequence,
              lastEnqueuedEventSequence == terminalResolution.resolvedThroughQueueSequence else {
            throw ControllerError.captureIncomplete
        }

        let freshSession = try PassiveCoreBluetoothTerminalFreshTargetSession.create(
            after: terminalResolution,
            vehicleIdentity: vehicleIdentity,
            startedAt: startedAt
        )
        let previousAuthority = currentArtifactAuthorityContext()
        let freshAuthority = PassiveCoreBluetoothArtifactAuthorityContext(
            targetSessionGeneration: freshSession.receipt.targetSessionGeneration,
            authorityGeneration: 1
        )

        do {
            try artifactAuthorityFence.transition(
                from: previousAuthority,
                to: freshAuthority
            )
            targetSessionGeneration = freshAuthority.targetSessionGeneration
            artifactAuthorityGeneration = freshAuthority.authorityGeneration
            recorder = freshSession.recorder
            hasUsedInitialSessionIdentity = true
            acquisitionLedger.beginTargetSession()
            gattIdentityRegistry.reset()
            selectedTargetCancellationPending = false
            foregroundEvidenceIntegrityValid = true
            committedReadyEpoch = nil

            try observationBoundaryQueueGate.reopenAfterTerminalFreshTargetSession(
                freshSession.receipt,
                installedRecorder: freshSession.recorder,
                currentResolvedThroughQueueSequence: lastResolvedEventSequence,
                currentLastEnqueuedEventSequence: lastEnqueuedEventSequence
            )
        } catch {
            failCapture(error)
            throw ControllerError.captureFailed
        }

        pendingTerminalQueueResolution = nil
        lastFinalizedArtifactAuthority = nil
        return true
    }

'''
if text.count(insertion_marker) != 1:
    raise SystemExit(f"recovery insertion marker: expected exactly one match, found {text.count(insertion_marker)}")
text = text.replace(insertion_marker, recovery + insertion_marker, 1)

old_terminal_callback = '''        // After Horizon admission/freeze, consume CoreBluetooth transport cleanup
        // only. The finalized/closing artifact authority is immutable.
        if observationBoundaryQueueGate.isTerminal || observationBoundaryBlocksArtifactMutation {
            selectedTargetCancellationPending = false
            if case .active = disposition {
                clearActiveConnectionState(for: identifier)
            }
            return
        }
'''
new_terminal_callback = '''        // After Horizon admission/freeze, consume CoreBluetooth transport cleanup
        // only. The finalized/closing artifact authority is immutable until a real
        // terminal callback has released same-target quarantine. Only then may the
        // exact producer-created fresh recorder consume terminal resolution authority.
        if observationBoundaryQueueGate.isTerminal || observationBoundaryBlocksArtifactMutation {
            selectedTargetCancellationPending = false
            if case .active = disposition {
                clearActiveConnectionState(for: identifier)
            }
            do {
                _ = try completeTerminalFreshTargetSessionIfReady()
            } catch {
                failCapture(error)
            }
            return
        }
'''
replace_once(old_terminal_callback, new_terminal_callback, "terminal callback recovery")

PATH.write_text(text)
