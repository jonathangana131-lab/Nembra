/// MainActor-only, one-shot retirement of queued evidence that belongs to the
/// exact artifact authority already sealed by a terminal observation horizon.
///
/// The controller's boundary gate deliberately stays terminal after the immutable
/// Horizon artifact is frozen. Reopening that lifecycle is unsafe until every
/// callback accepted after H under the *same* artifact authority has been removed
/// from the pending recorder FIFO. A newer authority or another target session is
/// not collateral damage and must remain queued for its own lifecycle.
///
/// This helper performs validation and mutation synchronously on MainActor so a
/// CoreBluetooth callback cannot interleave between the queue snapshot and the
/// removal. It does not itself reopen the boundary gate; the future controller
/// integration must consume the returned producer-issued receipt immediately,
/// without an `await`, when adding the terminal -> fresh-session transition.
struct PassiveCoreBluetoothTerminalQueueRetirement: Sendable {
    struct PendingEvidenceIdentity: Equatable, Sendable {
        let queueSequence: UInt64
        let authority: PassiveCoreBluetoothArtifactAuthorityContext
    }

    /// Proof emitted only after this helper has validated the whole pending FIFO
    /// and removed every post-H item carrying the terminal transaction's exact
    /// artifact authority. This is software queue authority only, not RF proof.
    ///
    /// `terminalTransactionRevision` binds the receipt to one exact terminal gate
    /// transaction. `validatedQueueTailSequence` binds it to the exact FIFO tail
    /// observed while retirement executed. A future terminal -> fresh transition
    /// must require both bindings and must reject the receipt if the controller's
    /// current `lastEnqueuedEventSequence` has advanced in the meantime.
    struct Receipt: Equatable, Sendable {
        let terminalAuthority: PassiveCoreBluetoothArtifactAuthorityContext
        let terminalTransactionRevision: UInt64
        let horizonQueueCutoff: UInt64
        let validatedQueueTailSequence: UInt64
        let retiredEvidenceCount: Int
        let firstRetiredQueueSequence: UInt64?
        let lastRetiredQueueSequence: UInt64?
        let retainedPendingEvidenceCount: Int

        fileprivate init(
            terminalAuthority: PassiveCoreBluetoothArtifactAuthorityContext,
            terminalTransactionRevision: UInt64,
            horizonQueueCutoff: UInt64,
            validatedQueueTailSequence: UInt64,
            retiredEvidenceCount: Int,
            firstRetiredQueueSequence: UInt64?,
            lastRetiredQueueSequence: UInt64?,
            retainedPendingEvidenceCount: Int
        ) {
            self.terminalAuthority = terminalAuthority
            self.terminalTransactionRevision = terminalTransactionRevision
            self.horizonQueueCutoff = horizonQueueCutoff
            self.validatedQueueTailSequence = validatedQueueTailSequence
            self.retiredEvidenceCount = retiredEvidenceCount
            self.firstRetiredQueueSequence = firstRetiredQueueSequence
            self.lastRetiredQueueSequence = lastRetiredQueueSequence
            self.retainedPendingEvidenceCount = retainedPendingEvidenceCount
        }
    }

    enum StateError: Error, Equatable, Sendable {
        case terminalHorizonRequired
        case invalidQueueSequence(UInt64)
        case nonIncreasingQueueSequence(previous: UInt64, current: UInt64)
        case terminalPrefixStillPending(queueSequence: UInt64)
    }

    /// Retires only evidence that satisfies both:
    /// - exact terminal artifact authority; and
    /// - queue sequence strictly after the immutable Horizon cutoff.
    ///
    /// Validation is fail-closed and atomic. The terminal transaction's H is a
    /// global controller-FIFO cutoff: every callback at or before H was required to
    /// drain before that boundary could commit. Therefore *any* still-pending item
    /// at/before H is an impossible prefix residue, regardless of artifact authority,
    /// and leaves the caller's array unchanged. Newer/foreign authority events after
    /// H are retained even when interleaved with the old terminal generation.
    ///
    /// The identity closure must project immutable authority captured on the queued
    /// event itself. It must never synthesize authority from whichever controller
    /// generation happens to be current when retirement runs.
    @MainActor
    static func retire<Event>(
        from pendingEvents: inout [Event],
        terminalGate: PassiveCoreBluetoothObservationBoundaryQueueGate,
        identity: (Event) -> PendingEvidenceIdentity
    ) throws -> Receipt {
        guard case let .terminal(transaction) = terminalGate.phase else {
            throw StateError.terminalHorizonRequired
        }

        var previousQueueSequence: UInt64?
        var retirementMask = Array(repeating: false, count: pendingEvents.count)
        var retiredEvidenceCount = 0
        var firstRetiredQueueSequence: UInt64?
        var lastRetiredQueueSequence: UInt64?

        for (index, event) in pendingEvents.enumerated() {
            let evidence = identity(event)
            guard evidence.queueSequence > 0 else {
                throw StateError.invalidQueueSequence(evidence.queueSequence)
            }
            if let previousQueueSequence,
               evidence.queueSequence <= previousQueueSequence {
                throw StateError.nonIncreasingQueueSequence(
                    previous: previousQueueSequence,
                    current: evidence.queueSequence
                )
            }
            previousQueueSequence = evidence.queueSequence

            guard evidence.queueSequence > transaction.queueCutoff else {
                throw StateError.terminalPrefixStillPending(
                    queueSequence: evidence.queueSequence
                )
            }
            guard evidence.authority == transaction.authority else {
                continue
            }

            retirementMask[index] = true
            retiredEvidenceCount += 1
            firstRetiredQueueSequence = firstRetiredQueueSequence ?? evidence.queueSequence
            lastRetiredQueueSequence = evidence.queueSequence
        }

        // While terminal, every callback after H is withheld by the queue gate. The
        // pending tail is therefore the controller FIFO tail. If nothing is pending,
        // H itself is the validated tail. This binding lets the future reopen reject
        // a stale receipt after any later callback advances the global queue sequence.
        let validatedQueueTailSequence = previousQueueSequence ?? transaction.queueCutoff

        if retiredEvidenceCount > 0 {
            var retainedEvents: [Event] = []
            retainedEvents.reserveCapacity(pendingEvents.count - retiredEvidenceCount)
            for (index, event) in pendingEvents.enumerated() where !retirementMask[index] {
                retainedEvents.append(event)
            }
            pendingEvents = retainedEvents
        }

        return Receipt(
            terminalAuthority: transaction.authority,
            terminalTransactionRevision: transaction.revision,
            horizonQueueCutoff: transaction.queueCutoff,
            validatedQueueTailSequence: validatedQueueTailSequence,
            retiredEvidenceCount: retiredEvidenceCount,
            firstRetiredQueueSequence: firstRetiredQueueSequence,
            lastRetiredQueueSequence: lastRetiredQueueSequence,
            retainedPendingEvidenceCount: pendingEvents.count
        )
    }
}
