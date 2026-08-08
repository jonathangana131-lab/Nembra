from pathlib import Path

GATE = Path("Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/PassiveCoreBluetoothObservationBoundaryQueueGate.swift")
CONTROLLER = Path("Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/ForegroundCoreBluetoothCaptureController.swift")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


gate = GATE.read_text()
gate = replace_once(
    gate,
    "        case horizonArtifactNotReady\n",
    "        case horizonArtifactNotReady\n"
    "        case freshTargetSessionRequired\n"
    "        case terminalResolvedFrontierNotApplied(expected: UInt64, actual: UInt64)\n"
    "        case resolvedQueueTailChanged(expected: UInt64, actual: UInt64)\n"
    "        case installedFreshRecorderMismatch\n",
    "gate errors",
)
gate = replace_once(
    gate,
    "    private var committedReadyTransaction: Transaction?\n",
    "    private var committedReadyTransaction: Transaction?\n"
    "    /// Exact producer-created target-session generation allowed to consume the\n"
    "    /// first Ready after terminal recovery. Weak reset cannot erase this bind.\n"
    "    private var requiredReadyTargetSessionGeneration: UInt64?\n",
    "gate recovery bind",
)
gate = replace_once(
    gate,
    "        guard processedQueueSequence == nil else {\n"
    "            throw StateError.invalidTransition\n"
    "        }\n"
    "        guard nextRevision != UInt64.max else {\n",
    "        guard processedQueueSequence == nil else {\n"
    "            throw StateError.invalidTransition\n"
    "        }\n"
    "        if let requiredReadyTargetSessionGeneration,\n"
    "           authority.targetSessionGeneration != requiredReadyTargetSessionGeneration {\n"
    "            throw StateError.freshTargetSessionRequired\n"
    "        }\n"
    "        guard nextRevision != UInt64.max else {\n",
    "Ready recovery bind check",
)
gate = replace_once(
    gate,
    "        phase = .drainingReady(transaction)\n"
    "        nextRevision += 1\n",
    "        requiredReadyTargetSessionGeneration = nil\n"
    "        phase = .drainingReady(transaction)\n"
    "        nextRevision += 1\n",
    "Ready recovery bind consume",
)
reset_marker = "    /// Terminal retirement alone cannot reopen lifecycle admission because retired positions\n"
reopen_method = '''    /// Reopens a successfully frozen terminal Horizon only after the controller has
    /// installed the exact producer-created fresh recorder, applied the exact terminal
    /// resolution to its distinct global FIFO frontier, and observed no enqueue-tail drift.
    /// This is software lifecycle authority only; it does not upgrade retired callbacks
    /// into recorder-written evidence or establish physical scooter truth.
    @MainActor
    mutating func reopenAfterTerminalQueueResolution(
        _ freshSession: PassiveCoreBluetoothTerminalFreshTargetSession.Receipt,
        installedRecorderIdentity: ObjectIdentifier,
        currentResolvedThroughQueueSequence: UInt64,
        currentLastEnqueuedEventSequence: UInt64
    ) throws {
        guard case let .terminal(transaction) = phase else {
            throw StateError.invalidTransition
        }

        let resolution = freshSession.terminalResolution
        guard resolution.terminalTransactionRevision == transaction.revision,
              resolution.terminalTransactionIdentity == transaction.identity,
              resolution.horizonQueueCutoff == transaction.queueCutoff,
              resolution.previouslyResolvedThroughQueueSequence == transaction.queueCutoff else {
            throw StateError.staleTransaction
        }
        guard resolution.terminalAuthority == transaction.authority else {
            throw StateError.authorityChanged
        }
        guard resolution.resolvedThroughQueueSequence == currentResolvedThroughQueueSequence else {
            throw StateError.terminalResolvedFrontierNotApplied(
                expected: resolution.resolvedThroughQueueSequence,
                actual: currentResolvedThroughQueueSequence
            )
        }
        guard resolution.resolvedThroughQueueSequence == currentLastEnqueuedEventSequence else {
            throw StateError.resolvedQueueTailChanged(
                expected: resolution.resolvedThroughQueueSequence,
                actual: currentLastEnqueuedEventSequence
            )
        }
        guard installedRecorderIdentity == freshSession.recorderIdentity else {
            throw StateError.installedFreshRecorderMismatch
        }
        guard transaction.authority.targetSessionGeneration != UInt64.max,
              freshSession.targetSessionGeneration == transaction.authority.targetSessionGeneration + 1 else {
            throw StateError.freshTargetSessionRequired
        }

        committedReadyTransaction = nil
        requiredReadyTargetSessionGeneration = freshSession.targetSessionGeneration
        phase = .awaitingReady
    }

'''
if gate.count(reset_marker) != 1:
    raise SystemExit(f"gate reset marker: expected one match, found {gate.count(reset_marker)}")
gate = gate.replace(reset_marker, reopen_method + reset_marker, 1)
GATE.write_text(gate)

controller = CONTROLLER.read_text()
controller = replace_once(
    controller,
    "    private var lastFinalizedArtifactAuthority: PassiveCoreBluetoothArtifactAuthorityContext?\n",
    "    private var lastFinalizedArtifactAuthority: PassiveCoreBluetoothArtifactAuthorityContext?\n"
    "    /// Exact terminal FIFO resolution retained after immutable artifact return so\n"
    "    /// transport teardown can finish before a new durable recorder is admitted.\n"
    "    private var pendingTerminalQueueResolution: PassiveCoreBluetoothTerminalQueueResolution.Receipt?\n",
    "controller terminal resolution property",
)
controller = replace_once(
    controller,
    "                _ = try resolveQueuedEvidenceAfterTerminalHorizon()\n",
    "                let terminalResolution = try resolveQueuedEvidenceAfterTerminalHorizon()\n"
    "                pendingTerminalQueueResolution = terminalResolution\n",
    "retain terminal resolution",
)
controller = replace_once(
    controller,
    "        lastFinalizedArtifactAuthority = nil\n\n"
    "        targetState.selectTarget(identifier)\n",
    "        lastFinalizedArtifactAuthority = nil\n"
    "        pendingTerminalQueueResolution = nil\n\n"
    "        targetState.selectTarget(identifier)\n",
    "ordinary fresh target clears stale terminal resolution",
)
stock_marker = "    /// Adds a human-observed stock-app value to the selected target's monotonic\n"
recovery_method = '''    /// Creates the exact next durable capture session after a successful terminal
    /// artifact has already been returned and transport teardown has crossed its real
    /// CoreBluetooth terminal callback. No actor suspension exists between fresh-recorder
    /// publication and queue-gate reopen.
    public func prepareFreshTargetSessionAfterFinalization(
        startedAt: Date = Date()
    ) throws {
        try ensureCaptureHealthy()
        guard observationBoundaryQueueGate.isTerminal,
              let terminalResolution = pendingTerminalQueueResolution else {
            throw ControllerError.artifactNotFinalized
        }
        guard !artifactReadBarrier.isActive, observationBoundaryTask == nil else {
            throw ControllerError.captureIncomplete
        }
        guard activePeripheral == nil, connectionPhase == .idle else {
            throw ControllerError.captureIncomplete
        }
        guard let selectedTargetIdentifier = targetState.selectedTargetIdentifier else {
            throw ControllerError.targetNotSelected
        }
        guard !isSelectedTargetAwaitingTerminalCallback else {
            throw ControllerError.peripheralAwaitingTerminalCallback(selectedTargetIdentifier)
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
            // Publish the exact recorder/authority pair synchronously before gate
            // consumption. MainActor cannot interleave a late callback inside this block.
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

            try observationBoundaryQueueGate.reopenAfterTerminalQueueResolution(
                freshSession.receipt,
                installedRecorderIdentity: ObjectIdentifier(freshSession.recorder),
                currentResolvedThroughQueueSequence: lastResolvedEventSequence,
                currentLastEnqueuedEventSequence: lastEnqueuedEventSequence
            )
        } catch {
            failCapture(error)
            throw ControllerError.captureFailed
        }

        pendingTerminalQueueResolution = nil
        lastFinalizedArtifactAuthority = nil
    }

'''
if controller.count(stock_marker) != 1:
    raise SystemExit(f"controller insertion marker: expected one match, found {controller.count(stock_marker)}")
controller = controller.replace(stock_marker, recovery_method + stock_marker, 1)
CONTROLLER.write_text(controller)
