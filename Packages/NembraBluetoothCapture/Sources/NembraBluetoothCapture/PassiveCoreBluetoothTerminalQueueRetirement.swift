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
    struct Receipt: Equatable, Sendable {
        let terminalAuthority: PassiveCoreBluetoothArtifactAuthorityContext
        let horizonQueueCutoff: UInt64
        let retiredEvidenceCount: Int
        let firstRetiredQueueSequence: UInt64?
        let lastRetiredQueueSequence: UInt64?
        let retainedPendingEvidenceCount: Int

        fileprivate init(
            terminalAuthority: PassiveCoreBluetoothArtifactAuthorityContext,
            horizonQueueCutoff: UInt64,
            retiredEvidenceCount: Int,
            firstRetiredQueueSequence: UInt64?,
            lastRetiredQueueSequence: UInt64?,
            retainedPendingEvidenceCount: Int
        ) {
            self.terminalAuthority = terminalAuthority
            self.horizonQueueCutoff = horizonQueueCutoff
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
    /// Validation is fail-closed and atomic. A malformed FIFO or any still-pending
    /// terminal-authority item at/before H leaves the caller's array unchanged.
    /// Newer/foreign authority events are retained even when interleaved with the
    /// old terminal generation.
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

            guard evidence.authority == transaction.authority else {
                continue
            }
            guard evidence.queueSequence > transaction.queueCutoff else {
                throw StateError.terminalPrefixStillPending(
                    queueSequence: evidence.queueSequence
                )
            }

            retirementMask[index] = true
            retiredEvidenceCount += 1
            firstRetiredQueueSequence = firstRetiredQueueSequence ?? evidence.queueSequence
            lastRetiredQueueSequence = evidence.queueSequence
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
            horizonQueueCutoff: transaction.queueCutoff,
            retiredEvidenceCount: retiredEvidenceCount,
            firstRetiredQueueSequence: firstRetiredQueueSequence,
            lastRetiredQueueSequence: lastRetiredQueueSequence,
            retainedPendingEvidenceCount: pendingEvents.count
        )
    }
}
