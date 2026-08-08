from pathlib import Path

path = Path(
    "Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/"
    "ForegroundCoreBluetoothCaptureController.swift"
)
source = path.read_text()

old = """        do {
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
"""

new = """        do {
            // Preflight every remaining fallible gate condition on a value copy before
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
"""

count = source.count(old)
if count != 1:
    raise SystemExit(f"expected exactly one reviewed abort-recovery block, found {count}")

path.write_text(source.replace(old, new))
