/// Synchronous MainActor retirement of queued evidence after a pre-H Ready
/// attempt/epoch has been intentionally abandoned.
///
/// Abort quarantine stops ordinary draining, but an already-abandoned recorder must
/// not be reopened merely because controller authority or target-session counters
/// advance. This helper validates the complete still-pending FIFO suffix and retires
/// it only when every pending event belongs to the exact abandoned target session.
///
/// The controller must also prove its existing event-drain task is idle. An event
/// already removed from `pendingEvents` and suspended on the recorder actor is not
/// visible to this helper; admitting retirement while that task is active would make
/// the queue snapshot incomplete. The final controller integration must therefore
/// freeze abort quarantine first, await any already-started drain outside this
/// synchronous operation, and then call this helper with `drainIsIdle == true`.
///
/// Software queue/session chronology only. No physical scooter or RF claim is made.
struct PassiveCoreBluetoothAbortedObservationQueueRetirement: Sendable {
    struct PendingEvidenceIdentity: Equatable, Sendable {
        let queueSequence: UInt64
        let authority: PassiveCoreBluetoothArtifactAuthorityContext
    }

    /// Producer-issued proof that the complete pending FIFO suffix for one aborted
    /// target session was validated and removed while normal draining was stopped.
    ///
    /// `validatedQueueTailSequence` binds the receipt to the controller's global
    /// enqueue counter at retirement time. The queue gate will not reopen if that
    /// counter advances before a fresh durable target session is bound.
    struct Receipt: Equatable, Sendable {
        let abortReceipt: PassiveCoreBluetoothObservationBoundaryQueueGate.ObservationEpochAbortReceipt
        let validatedQueueTailSequence: UInt64
        let validatedSettledQueueSequence: UInt64
        let retiredEvidenceCount: Int
        let retainedPendingEvidenceCount: Int

        fileprivate init(
            abortReceipt: PassiveCoreBluetoothObservationBoundaryQueueGate.ObservationEpochAbortReceipt,
            validatedQueueTailSequence: UInt64,
            validatedSettledQueueSequence: UInt64,
            retiredEvidenceCount: Int,
            retainedPendingEvidenceCount: Int
        ) {
            self.abortReceipt = abortReceipt
            self.validatedQueueTailSequence = validatedQueueTailSequence
            self.validatedSettledQueueSequence = validatedSettledQueueSequence
            self.retiredEvidenceCount = retiredEvidenceCount
            self.retainedPendingEvidenceCount = retainedPendingEvidenceCount
        }
    }

    enum StateError: Error, Equatable, Sendable {
        case abortQuarantineRequired
        case eventDrainStillActive
        case settledQueueSequenceAfterTail(settled: UInt64, tail: UInt64)
        case readyPrefixNotSettled(settled: UInt64, readyCutoff: UInt64)
        case invalidQueueSequence(UInt64)
        case nonContiguousQueueSequence(expected: UInt64, actual: UInt64)
        case pendingQueueTailMismatch(expectedControllerTail: UInt64, actualPendingTail: UInt64?)
        case readyPrefixStillPending(queueSequence: UInt64, readyCutoff: UInt64)
        case foreignTargetSessionPending(expected: UInt64, actual: UInt64)
    }

    /// Validates and removes the complete pending suffix for the gate's exact
    /// quarantined target session.
    ///
    /// `currentSettledQueueSequence` is the controller's monotonic queue frontier
    /// whose entries are no longer in flight: successfully recorder-processed or
    /// explicitly retired by a prior accepted lifecycle operation. With the drain
    /// idle and this gate quarantined, a non-empty pending FIFO must be the contiguous
    /// suffix `settled + 1 ... lastEnqueued`; an empty FIFO requires
    /// `settled == lastEnqueued`. This catches a callback already popped by an active
    /// drain, manual/truncated retirement, and hidden sequence holes before mutation.
    ///
    /// All pending entries must belong to the abandoned `targetSessionGeneration`.
    /// Different authority generations inside that same target session are retired
    /// together because the durable recorder/session itself is being abandoned.
    /// Foreign/next target-session evidence is never collateral damage and causes an
    /// atomic failure instead of being preserved and accidentally released later.
    @MainActor
    static func retire<Event>(
        from pendingEvents: inout [Event],
        currentLastEnqueuedEventSequence: UInt64,
        currentSettledQueueSequence: UInt64,
        drainIsIdle: Bool,
        abortedGate: PassiveCoreBluetoothObservationBoundaryQueueGate,
        identity: (Event) -> PendingEvidenceIdentity
    ) throws -> Receipt {
        guard case let .abortQuarantined(abortReceipt) = abortedGate.phase else {
            throw StateError.abortQuarantineRequired
        }
        guard drainIsIdle else {
            throw StateError.eventDrainStillActive
        }
        guard currentSettledQueueSequence <= currentLastEnqueuedEventSequence else {
            throw StateError.settledQueueSequenceAfterTail(
                settled: currentSettledQueueSequence,
                tail: currentLastEnqueuedEventSequence
            )
        }
        guard currentSettledQueueSequence >= abortReceipt.abandonedReadyQueueCutoff else {
            throw StateError.readyPrefixNotSettled(
                settled: currentSettledQueueSequence,
                readyCutoff: abortReceipt.abandonedReadyQueueCutoff
            )
        }

        var previousSequence = currentSettledQueueSequence
        for event in pendingEvents {
            let evidence = identity(event)
            guard evidence.queueSequence > 0 else {
                throw StateError.invalidQueueSequence(evidence.queueSequence)
            }
            guard previousSequence != UInt64.max else {
                throw StateError.nonContiguousQueueSequence(
                    expected: UInt64.max,
                    actual: evidence.queueSequence
                )
            }
            let expectedSequence = previousSequence + 1
            guard evidence.queueSequence == expectedSequence else {
                throw StateError.nonContiguousQueueSequence(
                    expected: expectedSequence,
                    actual: evidence.queueSequence
                )
            }
            guard evidence.queueSequence > abortReceipt.abandonedReadyQueueCutoff else {
                throw StateError.readyPrefixStillPending(
                    queueSequence: evidence.queueSequence,
                    readyCutoff: abortReceipt.abandonedReadyQueueCutoff
                )
            }
            guard evidence.authority.targetSessionGeneration
                    == abortReceipt.abandonedTargetSessionGeneration else {
                throw StateError.foreignTargetSessionPending(
                    expected: abortReceipt.abandonedTargetSessionGeneration,
                    actual: evidence.authority.targetSessionGeneration
                )
            }
            previousSequence = evidence.queueSequence
        }

        guard previousSequence == currentLastEnqueuedEventSequence else {
            throw StateError.pendingQueueTailMismatch(
                expectedControllerTail: currentLastEnqueuedEventSequence,
                actualPendingTail: pendingEvents.last.map { identity($0).queueSequence }
            )
        }

        let retiredEvidenceCount = pendingEvents.count
        pendingEvents.removeAll(keepingCapacity: true)

        return Receipt(
            abortReceipt: abortReceipt,
            validatedQueueTailSequence: currentLastEnqueuedEventSequence,
            validatedSettledQueueSequence: currentSettledQueueSequence,
            retiredEvidenceCount: retiredEvidenceCount,
            retainedPendingEvidenceCount: pendingEvents.count
        )
    }
}
