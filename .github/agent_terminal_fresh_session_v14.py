from pathlib import Path
import subprocess

BASE = "50732571e01929ef22c79bd7f99178cf4f78a6bf"
SOURCE = "28c9dde0398d14f353415b860d806215d597792b"
CONTROLLER = Path("Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/ForegroundCoreBluetoothCaptureController.swift")
GATE = Path("Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/PassiveCoreBluetoothObservationBoundaryQueueGate.swift")
CONTROLLER_TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/ForegroundCoreBluetoothCaptureControllerTerminalFreshSessionConsumerTests.swift")
GATE_TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/PassiveCoreBluetoothTerminalRealRecorderReopenTests.swift")


def run(*args, input_text=None):
    return subprocess.run(args, input=input_text, text=True, check=True, capture_output=True).stdout


run("git", "fetch", "--no-tags", "origin", BASE, SOURCE)

# Compose the queue-gate authority delta first. It is isolated from the newer
# Experiment One controller chronology changes.
gate_patch = run("git", "diff", "--binary", BASE, SOURCE, "--", str(GATE))
if not gate_patch.strip():
    raise RuntimeError("terminal gate patch unexpectedly empty")
subprocess.run(["git", "apply", "--3way", "--index", "-"], input=gate_patch, text=True, check=True)

s = CONTROLLER.read_text()

def once(old: str, new: str, label: str) -> None:
    global s
    count = s.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected one current insertion point, found {count}")
    s = s.replace(old, new, 1)

once(
    "    private var lastFinalizedArtifactAuthority: PassiveCoreBluetoothArtifactAuthorityContext?\n    private var targetState = PassiveCoreBluetoothTargetState()\n",
    "    private var lastFinalizedArtifactAuthority: PassiveCoreBluetoothArtifactAuthorityContext?\n"
    "    /// Exact successful-terminal FIFO resolution retained after immutable artifact\n"
    "    /// return. It remains inert until transport teardown crosses the real terminal\n"
    "    /// CoreBluetooth callback and a producer-created fresh recorder is installed.\n"
    "    private var pendingTerminalQueueResolution: PassiveCoreBluetoothTerminalQueueResolution.Receipt?\n"
    "    private var targetState = PassiveCoreBluetoothTargetState()\n",
    "pending terminal receipt",
)
once(
    "    public func teardownActiveConnectionAfterFinalization() throws {\n        guard activePeripheral != nil else { return }\n",
    "    public func teardownActiveConnectionAfterFinalization() throws {\n"
    "        guard activePeripheral != nil else {\n"
    "            _ = try completeTerminalFreshTargetSessionIfReady()\n"
    "            return\n"
    "        }\n",
    "teardown idle recovery",
)
once(
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
once(
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

# Current flagship contracts must survive the stale-base terminal composition.
assert "func connectUsingExperimentOneAdmission(" in s
assert "receivedAtUptimeNanoseconds >= payload.issuedAtUptimeNanoseconds" in s
assert s.count("try self.requireForegroundEvidenceIntegrity()") >= 4
assert "PassiveCoreBluetoothTerminalFreshTargetSession.create" in s
assert "pendingTerminalQueueResolution" in s

g = GATE.read_text()
assert "reopenAfterTerminalFreshTargetSession" in g
run("git", "diff", "--cached", "--check")

# Leave only product/test changes in the durable commit.
run("git", "rm", ".github/workflows/agent-terminal-fresh-session-v14.yml", ".github/agent_terminal_fresh_session_v14.py")
run("git", "config", "user.name", "github-actions[bot]")
run("git", "config", "user.email", "41898282+github-actions[bot]@users.noreply.github.com")
run("git", "add", "-u")
run("git", "commit", "-m", "[Capture terminal] Restack exact fresh recorder handoff")
run("git", "push", "origin", "HEAD:agent/capture-terminal-fresh-session-v14-current")
