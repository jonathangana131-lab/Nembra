from pathlib import Path
import subprocess

SOURCE = "28c9dde0398d14f353415b860d806215d597792b"
CONTROLLER = Path("Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/ForegroundCoreBluetoothCaptureController.swift")
GATE = Path("Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/PassiveCoreBluetoothObservationBoundaryQueueGate.swift")
CONTROLLER_TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/ForegroundCoreBluetoothCaptureControllerTerminalFreshSessionConsumerTests.swift")
GATE_TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/PassiveCoreBluetoothTerminalRealRecorderReopenTests.swift")


def run(*args):
    return subprocess.run(args, text=True, check=True, capture_output=True).stdout


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected one current insertion point, found {count}")
    return text.replace(old, new, 1)


run("git", "fetch", "--no-tags", "origin", SOURCE)

# Compose only the terminal queue-gate semantics onto the current gate instead of
# replaying #656's stale file ancestry.
g = GATE.read_text()
g = replace_once(
    g,
    "        case cutoffOverrun\n        case horizonArtifactNotReady\n",
    "        case cutoffOverrun\n        case horizonArtifactNotReady\n"
    "        case freshTargetSessionRequired\n"
    "        case freshRecorderIdentityMismatch\n"
    "        case terminalResolvedFrontierNotApplied(expected: UInt64, actual: UInt64)\n"
    "        case terminalQueueChangedAfterResolution(expected: UInt64, actual: UInt64)\n",
    "gate state errors",
)
g = replace_once(
    g,
    "    private var nextRevision: UInt64 = 1\n    private var committedReadyTransaction: Transaction?\n",
    "    private var nextRevision: UInt64 = 1\n"
    "    private var committedReadyTransaction: Transaction?\n"
    "    /// Exact already-provisioned durable target session required after recovery.\n"
    "    /// Weak reset cannot erase this one-shot bind.\n"
    "    private var requiredReadyTargetSessionGeneration: UInt64?\n",
    "gate required target session",
)
g = replace_once(
    g,
    "        guard processedQueueSequence == nil else {\n            throw StateError.invalidTransition\n        }\n        guard nextRevision != UInt64.max else {\n",
    "        guard processedQueueSequence == nil else {\n            throw StateError.invalidTransition\n        }\n"
    "        if let requiredReadyTargetSessionGeneration {\n"
    "            guard authority.targetSessionGeneration == requiredReadyTargetSessionGeneration else {\n"
    "                throw StateError.freshTargetSessionRequired\n"
    "            }\n"
    "        }\n"
    "        guard nextRevision != UInt64.max else {\n",
    "gate Ready authority requirement",
)
g = replace_once(
    g,
    "        let transaction = Transaction(\n            boundaryKind: .finiteAcquisitionReady,\n            queueCutoff: queueCutoff,\n            authority: authority,\n            revision: nextRevision\n        )\n        phase = .drainingReady(transaction)\n",
    "        let transaction = Transaction(\n            boundaryKind: .finiteAcquisitionReady,\n            queueCutoff: queueCutoff,\n            authority: authority,\n            revision: nextRevision\n        )\n"
    "        requiredReadyTargetSessionGeneration = nil\n"
    "        phase = .drainingReady(transaction)\n",
    "gate Ready consumes requirement",
)
old_tail = '''    /// Abort quarantine is intentionally irreversible in this slice. Raw FIFO
    /// retirement alone cannot reopen lifecycle admission because retired positions
    /// still need a separate globally-resolved frontier update. #450 owns that
    /// producer and its successor integration must make fresh-session reopen consume
    /// the producer-issued resolution receipt. Until then reset and Ready both fail.
    @discardableResult
    mutating func resetForNewCaptureSession() -> Bool {
        guard phase == .awaitingReady else { return false }
        committedReadyTransaction = nil
        return true
    }
'''
new_tail = '''    /// Reopens a successful terminal Horizon only after the controller has
    /// installed the exact recorder whose construction earned producer-issued fresh-session
    /// proof, applied the exact terminal resolution to its global resolved frontier, and
    /// proved no callback advanced the FIFO tail afterward.
    ///
    /// This transition is synchronous on MainActor. It consumes the terminal transaction's
    /// exact process-local UUID and binds the exact fresh target-session generation until
    /// the next Ready begins. Receipt possession alone and a caller-chosen generation are
    /// deliberately insufficient.
    @MainActor
    mutating func reopenAfterTerminalFreshTargetSession(
        _ freshTargetSession: PassiveCoreBluetoothTerminalFreshTargetSession.Receipt,
        installedRecorder: PassiveCoreBluetoothCaptureRecorder,
        currentResolvedThroughQueueSequence: UInt64,
        currentLastEnqueuedEventSequence: UInt64
    ) throws {
        guard case let .terminal(transaction) = phase else {
            throw StateError.invalidTransition
        }

        let resolution = freshTargetSession.terminalResolution
        guard resolution.terminalTransactionRevision == transaction.revision,
              resolution.terminalTransactionIdentity == transaction.identity,
              resolution.horizonQueueCutoff == transaction.queueCutoff,
              resolution.previouslyResolvedThroughQueueSequence == transaction.queueCutoff else {
            throw StateError.staleTransaction
        }
        guard resolution.terminalAuthority == transaction.authority else {
            throw StateError.authorityChanged
        }
        guard freshTargetSession.recorderIdentity == ObjectIdentifier(installedRecorder) else {
            throw StateError.freshRecorderIdentityMismatch
        }
        guard currentResolvedThroughQueueSequence == resolution.resolvedThroughQueueSequence else {
            throw StateError.terminalResolvedFrontierNotApplied(
                expected: resolution.resolvedThroughQueueSequence,
                actual: currentResolvedThroughQueueSequence
            )
        }
        guard currentLastEnqueuedEventSequence == resolution.resolvedThroughQueueSequence else {
            throw StateError.terminalQueueChangedAfterResolution(
                expected: resolution.resolvedThroughQueueSequence,
                actual: currentLastEnqueuedEventSequence
            )
        }
        guard freshTargetSession.targetSessionGeneration > transaction.authority.targetSessionGeneration else {
            throw StateError.freshTargetSessionRequired
        }

        committedReadyTransaction = nil
        requiredReadyTargetSessionGeneration = freshTargetSession.targetSessionGeneration
        phase = .awaitingReady
    }

    /// Abort quarantine remains irreversible here. Its sibling real-recorder producer
    /// is separately owned and must converge without weakening terminal authority.
    @discardableResult
    mutating func resetForNewCaptureSession() -> Bool {
        guard phase == .awaitingReady else { return false }
        committedReadyTransaction = nil
        return true
    }
'''
g = replace_once(g, old_tail, new_tail, "gate terminal reopen")
GATE.write_text(g)

# Compose the controller consumer against the current flagship text.
s = CONTROLLER.read_text()
s = replace_once(
    s,
    "    private var lastFinalizedArtifactAuthority: PassiveCoreBluetoothArtifactAuthorityContext?\n    private var targetState = PassiveCoreBluetoothTargetState()\n",
    "    private var lastFinalizedArtifactAuthority: PassiveCoreBluetoothArtifactAuthorityContext?\n"
    "    /// Exact successful-terminal FIFO resolution retained after immutable artifact\n"
    "    /// return. It remains inert until transport teardown crosses the real terminal\n"
    "    /// CoreBluetooth callback and a producer-created fresh recorder is installed.\n"
    "    private var pendingTerminalQueueResolution: PassiveCoreBluetoothTerminalQueueResolution.Receipt?\n"
    "    private var targetState = PassiveCoreBluetoothTargetState()\n",
    "pending terminal receipt",
)
s = replace_once(
    s,
    "    public func teardownActiveConnectionAfterFinalization() throws {\n        guard activePeripheral != nil else { return }\n",
    "    public func teardownActiveConnectionAfterFinalization() throws {\n"
    "        guard activePeripheral != nil else {\n"
    "            _ = try completeTerminalFreshTargetSessionIfReady()\n"
    "            return\n"
    "        }\n",
    "teardown idle recovery",
)
s = replace_once(
    s,
    "            do {\n                _ = try resolveQueuedEvidenceAfterTerminalHorizon()\n            } catch {\n",
    "            do {\n"
    "                let terminalResolution = try resolveQueuedEvidenceAfterTerminalHorizon()\n"
    "                pendingTerminalQueueResolution = terminalResolution\n"
    "            } catch {\n",
    "retain terminal resolution",
)
marker = "    private func beginTargetSessionIfNeeded(for identifier: UUID) throws {\n"
if s.count(marker) != 1:
    raise RuntimeError("fresh-session method insertion point moved")
method = '''    /// Consumes one sealed terminal lifecycle into the exact next durable recorder only
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
s = s.replace(marker, method + marker, 1)
s = replace_once(
    s,
    '''        // After Horizon admission/freeze, consume CoreBluetooth transport cleanup
        // only. The finalized/closing artifact authority is immutable.
        if observationBoundaryQueueGate.isTerminal || observationBoundaryBlocksArtifactMutation {
            selectedTargetCancellationPending = false
            if case .active = disposition {
                clearActiveConnectionState(for: identifier)
            }
            return
        }
''',
    '''        // After Horizon admission/freeze, consume CoreBluetooth transport cleanup
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
''',
    "terminal callback recovery",
)
CONTROLLER.write_text(s)

CONTROLLER_TEST.write_text(run("git", "show", f"{SOURCE}:{CONTROLLER_TEST}"))
GATE_TEST.write_text(run("git", "show", f"{SOURCE}:{GATE_TEST}"))
run("git", "add", str(CONTROLLER), str(GATE), str(CONTROLLER_TEST), str(GATE_TEST))

assert "func connectUsingExperimentOneAdmission(" in s
assert "receivedAtUptimeNanoseconds >= payload.issuedAtUptimeNanoseconds" in s
assert s.count("try self.requireForegroundEvidenceIntegrity()") >= 4
assert "PassiveCoreBluetoothTerminalFreshTargetSession.create" in s
assert "pendingTerminalQueueResolution" in s
assert "reopenAfterTerminalFreshTargetSession" in g
run("git", "diff", "--cached", "--check")

run("git", "rm", ".github/workflows/agent-terminal-fresh-session-v14.yml", ".github/agent_terminal_fresh_session_v14.py")
run("git", "config", "user.name", "github-actions[bot]")
run("git", "config", "user.email", "41898282+github-actions[bot]@users.noreply.github.com")
run("git", "add", "-u")
run("git", "commit", "-m", "[Capture terminal] Restack exact fresh recorder handoff")
run("git", "push", "origin", "HEAD:agent/capture-terminal-fresh-session-v14-current")
