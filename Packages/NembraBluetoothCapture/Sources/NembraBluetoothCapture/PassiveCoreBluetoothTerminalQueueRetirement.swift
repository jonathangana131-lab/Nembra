/// MainActor-only, one-shot retirement of queued evidence that belongs to the
/// exact artifact authority already sealed by a terminal observation horizon.
///
/// The controller's boundary gate deliberately stays terminal after the immutable
/// Horizon artifact is frozen. Reopening that lifecycle is unsafe until every
/// callback accepted after H under the *same* artifact authority has been removed
/// from the pending recorder FIFO. A newer authority or another target session is
/// not collateral damage and must remain queued for its own lifecycle, but merely
/// preserving it is not proof that its captured recorder is safe to drain.
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
    /// transaction. `validatedQueueTailSequence` binds it to the controller-owned
    /// global FIFO tail supplied at retirement time. A future terminal -> fresh
    /// transition must require both bindings and reject the receipt if the current
    /// `lastEnqueuedEventSequence` has advanced in the meantime.
    ///
    /// A receipt with retained pending evidence is deliberately *not* standalone
    /// reopen authority. Before normal draining can resume, the controller must
    /// synchronously prove that every retained event is routed/quarantined/adopted
    /// by a valid nonterminal recorder lifecycle. Otherwise it must remain closed.
    struct Receipt: Equatable, Sendable {
        let terminalAuthority: PassiveCoreBluetoothArtifactAuthorityContext
        let terminalTransactionRevision: UInt64
        let horizonQueueCutoff: UInt64
        let validatedQueueTailSequence: UInt64
        let retiredEvidenceCount: Int
        let firstRetiredQueueSequence: UInt64?
        let lastRetiredQueueSequence: UInt64?
        let retainedPendingEvidenceCount: Int

        var requiresRetainedEvidenceRoutingBeforeReopen: Bool {
            retainedPendingEvidenceCount > 0
        }

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
        case controllerQueueTailBeforeHorizon(tail: UInt64, horizon: UInt64)
        case invalidQueueSequence(UInt64)
        case nonIncreasingQueueSequence(previous: UInt64, current: UInt64)
        case terminalPrefixStillPending(queueSequence: UInt64)
        case nonContiguousPendingQueueSequence(expected: UInt64, actual: UInt64)
        case pendingQueueTailMismatch(expectedControllerTail: UInt64, actualPendingTail: UInt64?)
    }

    /// Retires only evidence that satisfies both:
    /// - exact terminal artifact authority; and
    /// - queue sequence strictly after the immutable Horizon cutoff.
    ///
    /// `currentLastEnqueuedEventSequence` must be read from the controller's
    /// MainActor-owned monotonic queue counter in the same synchronous operation.
    /// The helper never reconstructs that authority from the pending array. While
    /// the gate is terminal, every callback after H is withheld, so a non-empty
    /// pending FIFO must contain the complete contiguous suffix H+1...controllerTail;
    /// an empty FIFO can be authoritative only when the controller tail is exactly H.
    /// This rejects missing interior/prefix entries, truncated queues, manual
    /// pre-retirement deletion, and accidental reuse after a prior retirement removed
    /// the old global tail.
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
        currentLastEnqueuedEventSequence: UInt64,
        terminalGate: PassiveCoreBluetoothObservationBoundaryQueueGate,
        identity: (Event) -> PendingEvidenceIdentity
    ) throws -> Receipt {
        guard case let .terminal(transaction) = terminalGate.phase else {
            throw StateError.terminalHorizonRequired
        }
        guard currentLastEnqueuedEventSequence >= transaction.queueCutoff else {
            throw StateError.controllerQueueTailBeforeHorizon(
                tail: currentLastEnqueuedEventSequence,
                horizon: transaction.queueCutoff
            )
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

            guard evidence.queueSequence > transaction.queueCutoff else {
                throw StateError.terminalPrefixStillPending(
                    queueSequence: evidence.queueSequence
                )
            }

            // A terminal gate withholds every accepted callback after H. Therefore
            // the pending queue is not merely sorted: it must be the complete global
            // FIFO suffix H+1...lastEnqueuedEventSequence with no missing sequence.
            // The strict-increase check above guarantees these additions cannot
            // overflow: a first post-H event implies H < UInt64.max, and a successor
            // greater than `previousQueueSequence` implies the previous value < max.
            let expectedQueueSequence = previousQueueSequence.map { $0 + 1 }
                ?? (transaction.queueCutoff + 1)
            guard evidence.queueSequence == expectedQueueSequence else {
                throw StateError.nonContiguousPendingQueueSequence(
                    expected: expectedQueueSequence,
                    actual: evidence.queueSequence
                )
            }
            previousQueueSequence = evidence.queueSequence

            guard evidence.authority == transaction.authority else {
                continue
            }

            retirementMask[index] = true
            retiredEvidenceCount += 1
            firstRetiredQueueSequence = firstRetiredQueueSequence ?? evidence.queueSequence
            lastRetiredQueueSequence = evidence.queueSequence
        }

        guard previousQueueSequence == currentLastEnqueuedEventSequence
                || (previousQueueSequence == nil
                    && currentLastEnqueuedEventSequence == transaction.queueCutoff) else {
            throw StateError.pendingQueueTailMismatch(
                expectedControllerTail: currentLastEnqueuedEventSequence,
                actualPendingTail: previousQueueSequence
            )
        }

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
            validatedQueueTailSequence: currentLastEnqueuedEventSequence,
            retiredEvidenceCount: retiredEvidenceCount,
            firstRetiredQueueSequence: firstRetiredQueueSequence,
            lastRetiredQueueSequence: lastRetiredQueueSequence,
            retainedPendingEvidenceCount: pendingEvents.count
        )
    }
}
