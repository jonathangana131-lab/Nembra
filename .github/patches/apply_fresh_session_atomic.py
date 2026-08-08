from pathlib import Path

path = Path(
    "Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/"
    "ForegroundCoreBluetoothCaptureController.swift"
)
source = path.read_text()

terminal_old = """        do {
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
"""

terminal_new = """        do {
            // Validate every remaining fallible terminal-gate condition on a value copy before
            // advancing the reference-backed canonical artifact-authority fence.
            var reopenedGate = observationBoundaryQueueGate
            try reopenedGate.reopenAfterTerminalFreshTargetSession(
                freshSession.receipt,
                installedRecorder: freshSession.recorder,
                currentResolvedThroughQueueSequence: lastResolvedEventSequence,
                currentLastEnqueuedEventSequence: lastEnqueuedEventSequence
            )

            // Final throwing install step. Everything after this transition is synchronous,
            // non-failable publication of the already-validated fresh durable session.
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
            observationBoundaryQueueGate = reopenedGate
        } catch {
            failCapture(error)
            throw ControllerError.captureFailed
        }
"""

abort_old = """        do {
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

            try observationBoundaryQueueGate.reopenAfterAbortedFreshTargetSession(
                freshSession.receipt,
                installedRecorder: freshSession.recorder,
                currentResolvedThroughQueueSequence: lastResolvedEventSequence,
                currentLastEnqueuedEventSequence: lastEnqueuedEventSequence
            )
        } catch {
            lastDiagnostic = Self.diagnostic(
                error,
                fallback: "Abort recovery failed while installing exact fresh capture authority."
            )
            throw ControllerError.captureFailed
        }
"""

abort_new = """        do {
            // Validate every remaining fallible abort-gate condition on a value copy before
            // advancing the reference-backed canonical artifact-authority fence.
            var reopenedGate = observationBoundaryQueueGate
            try reopenedGate.reopenAfterAbortedFreshTargetSession(
                freshSession.receipt,
                installedRecorder: freshSession.recorder,
                currentResolvedThroughQueueSequence: lastResolvedEventSequence,
                currentLastEnqueuedEventSequence: lastEnqueuedEventSequence
            )

            // Final throwing install step. Everything after this transition is synchronous,
            // non-failable publication of the already-validated fresh durable session.
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
            observationBoundaryQueueGate = reopenedGate
        } catch {
            lastDiagnostic = Self.diagnostic(
                error,
                fallback: "Abort recovery failed while installing exact fresh capture authority."
            )
            throw ControllerError.captureFailed
        }
"""

if source.count(terminal_old) != 1:
    raise SystemExit(f"expected one terminal install block, found {source.count(terminal_old)}")
source = source.replace(terminal_old, terminal_new)

if source.count(abort_old) != 1:
    raise SystemExit(f"expected one abort install block, found {source.count(abort_old)}")
source = source.replace(abort_old, abort_new)

path.write_text(source)
