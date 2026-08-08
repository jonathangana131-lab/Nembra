from pathlib import Path

p = Path('Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/ForegroundCoreBluetoothCaptureController.swift')
s = p.read_text()

def one(old: str, new: str) -> None:
    global s
    count = s.count(old)
    if count != 1:
        raise SystemExit(f'expected one match, found {count}: {old[:140]!r}')
    s = s.replace(old, new, 1)

one(
'''    private var lastEnqueuedEventSequence: UInt64 = 0
    private var lastProcessedEventSequence: UInt64 = 0
    private var artifactReadBarrier = PassiveCoreBluetoothArtifactReadBarrier()
''',
'''    private var lastEnqueuedEventSequence: UInt64 = 0
    /// Furthest global FIFO position whose event was handed to its captured recorder.
    /// Terminal retirement must never advance this recorder-written frontier.
    private var lastProcessedEventSequence: UInt64 = 0
    /// Furthest global FIFO position intentionally settled by either recorder drain
    /// or an accepted retirement producer. This may advance beyond the recorder-
    /// written frontier only after terminal post-H evidence is retired explicitly.
    private var lastResolvedEventSequence: UInt64 = 0
    private var artifactReadBarrier = PassiveCoreBluetoothArtifactReadBarrier()
'''
)

one(
'''                self.lastProcessedEventSequence = max(
                    self.lastProcessedEventSequence,
                    next.queueSequence
                )
                if shouldStop { break }
''',
'''                self.lastProcessedEventSequence = max(
                    self.lastProcessedEventSequence,
                    next.queueSequence
                )
                // Normal drain resolves the same queue position by recorder handoff.
                // Terminal retirement may later move only the distinct resolved
                // frontier beyond this recorder-written value.
                self.lastResolvedEventSequence = max(
                    self.lastResolvedEventSequence,
                    next.queueSequence
                )
                if shouldStop { break }
'''
)

old_final = '''            retireQueuedEvidenceAfterTerminalHorizon()
            lastFinalizedArtifactAuthority = committedHorizon.authority
            return data
'''
new_final = '''            // The artifact is already immutable and authority-validated here.
            // Record that truth before fallible post-freeze lifecycle cleanup so a
            // queue-recovery fault cannot relabel a legitimate sealed artifact as
            // if H itself never finalized.
            lastFinalizedArtifactAuthority = committedHorizon.authority
            do {
                _ = try resolveQueuedEvidenceAfterTerminalHorizon()
            } catch {
                // Post-H queue cleanup is lifecycle authority, not artifact content.
                // Preserve the already-sealed data for export while failing the live
                // controller closed so no new capture session can reuse unresolved
                // FIFO state.
                failCapture(
                    error,
                    fallback: "Capture artifact sealed, but terminal queue resolution failed. Start a fresh app session before another capture."
                )
            }
            return data
'''
if old_final not in s:
    # The pre-freeze successor may already place lastFinalized after retirement.
    old_final = '''            retireQueuedEvidenceAfterTerminalHorizon()
            lastFinalizedArtifactAuthority = committedHorizon.authority
            return data
'''
one(old_final, new_final)

one(
'''    private func retireQueuedEvidenceAfterTerminalHorizon() {
        pendingEvents.removeAll { pending in
            observationBoundaryQueueGate.shouldDiscardQueuedEvidenceAfterTerminalHorizon(
                queueSequence: pending.queueSequence,
                authority: pending.authority
            )
        }
    }
''',
'''    private func resolveQueuedEvidenceAfterTerminalHorizon() throws
        -> PassiveCoreBluetoothTerminalQueueResolution.Receipt {
        // Retirement validates the complete global H+1...tail suffix and removes
        // only evidence carrying the exact terminal artifact authority. The
        // projection uses authority captured on each queued event, never whichever
        // controller generation happens to be current at cleanup time.
        let retirement = try PassiveCoreBluetoothTerminalQueueRetirement.retire(
            from: &pendingEvents,
            currentLastEnqueuedEventSequence: lastEnqueuedEventSequence,
            terminalGate: observationBoundaryQueueGate
        ) { pending in
            PassiveCoreBluetoothTerminalQueueRetirement.PendingEvidenceIdentity(
                queueSequence: pending.queueSequence,
                authority: pending.authority
            )
        }

        // Convert accepted retirement into explicit resolved-FIFO authority without
        // laundering discarded callbacks into the recorder-written frontier. This
        // consumer is synchronous on MainActor, immediately after retirement, so a
        // new callback cannot make the receipt stale between the two producers.
        let resolution = try PassiveCoreBluetoothTerminalQueueResolution.resolve(
            currentResolvedThroughQueueSequence: lastResolvedEventSequence,
            currentLastEnqueuedEventSequence: lastEnqueuedEventSequence,
            retirementReceipt: retirement,
            terminalGate: observationBoundaryQueueGate
        )
        lastResolvedEventSequence = resolution.resolvedThroughQueueSequence
        return resolution
    }
'''
)

if 'retireQueuedEvidenceAfterTerminalHorizon()' in s:
    raise SystemExit('ad-hoc terminal queue wipe remains')

p.write_text(s)
