import Foundation

/// MainActor-only retirement of the complete post-H FIFO suffix after an immutable
/// Horizon artifact is terminally frozen.
///
/// This is software queue authority only. It neither reopens the lifecycle nor
/// upgrades retired callbacks into recorder-written evidence.
struct PassiveCoreBluetoothTerminalQueueRetirement: Sendable {
    struct PendingEvidenceIdentity: Equatable, Sendable {
        let queueSequence: UInt64
        let authority: PassiveCoreBluetoothArtifactAuthorityContext
    }

    /// Producer-issued proof of one exact terminal transaction's validated FIFO
    /// retirement. Revision alone is not sufficient on the modern Ready/H lineage:
    /// `terminalTransactionIdentity` binds the receipt to the gate-issued process-local
    /// UUID so an equal-scalar foreign terminal cannot substitute authority.
    struct Receipt: Equatable, Sendable {
        let terminalAuthority: PassiveCoreBluetoothArtifactAuthorityContext
        let terminalTransactionRevision: UInt64
        let terminalTransactionIdentity: UUID
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
            terminalTransactionIdentity: UUID,
            horizonQueueCutoff: UInt64,
            validatedQueueTailSequence: UInt64,
            retiredEvidenceCount: Int,
            firstRetiredQueueSequence: UInt64?,
            lastRetiredQueueSequence: UInt64?,
            retainedPendingEvidenceCount: Int
        ) {
            self.terminalAuthority = terminalAuthority
            self.terminalTransactionRevision = terminalTransactionRevision
            self.terminalTransactionIdentity = terminalTransactionIdentity
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

    /// Validates the whole withheld terminal FIFO before mutating it. While the gate
    /// is terminal, every accepted post-H callback is withheld, so a non-empty queue
    /// must be the complete contiguous global suffix H+1...controllerTail. Any
    /// residue at/before H, missing sequence, truncation, or tail drift fails atomically.
    ///
    /// Only events carrying the exact terminal artifact authority are removed.
    /// Foreign/newer authority events are retained and therefore keep reopen blocked
    /// until a separately accepted routing/adoption contract exists.
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
                throw StateError.terminalPrefixStillPending(queueSequence: evidence.queueSequence)
            }

            let expectedQueueSequence: UInt64
            if let previousQueueSequence {
                // Strict increase above proves `previousQueueSequence < UInt64.max`.
                expectedQueueSequence = previousQueueSequence + 1
            } else {
                guard transaction.queueCutoff < UInt64.max else {
                    throw StateError.pendingQueueTailMismatch(
                        expectedControllerTail: currentLastEnqueuedEventSequence,
                        actualPendingTail: nil
                    )
                }
                expectedQueueSequence = transaction.queueCutoff + 1
            }
            guard evidence.queueSequence == expectedQueueSequence else {
                throw StateError.nonContiguousPendingQueueSequence(
                    expected: expectedQueueSequence,
                    actual: evidence.queueSequence
                )
            }
            previousQueueSequence = evidence.queueSequence

            guard evidence.authority == transaction.authority else { continue }
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
            terminalTransactionIdentity: transaction.identity,
            horizonQueueCutoff: transaction.queueCutoff,
            validatedQueueTailSequence: currentLastEnqueuedEventSequence,
            retiredEvidenceCount: retiredEvidenceCount,
            firstRetiredQueueSequence: firstRetiredQueueSequence,
            lastRetiredQueueSequence: lastRetiredQueueSequence,
            retainedPendingEvidenceCount: pendingEvents.count
        )
    }
}
