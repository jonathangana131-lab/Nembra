/// Synchronous MainActor retirement of queued evidence after a pre-terminal
/// observation epoch has been intentionally abandoned.
///
/// Abort quarantine stops ordinary draining, but an abandoned recorder must not be
/// reopened merely because controller authority counters advance. This helper
/// validates the complete still-pending FIFO suffix and removes it only when every
/// pending event belongs to the exact abandoned target session.
///
/// Retired positions are globally resolved-by-retirement, not recorder-written
/// evidence. Final controller composition must keep those frontiers distinct.
struct PassiveCoreBluetoothAbortedObservationQueueRetirement: Sendable {
    struct PendingEvidenceIdentity: Equatable, Sendable {
        let queueSequence: UInt64
        let authority: PassiveCoreBluetoothArtifactAuthorityContext
    }

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
    /// quarantined target session. `currentSettledQueueSequence` is a controller
    /// chronology frontier: queue positions before it are no longer in flight. It is
    /// explicitly not a claim that every resolved position was written to a recorder.
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
        let abandonedEvidenceCutoff = abortReceipt.abandonedEvidenceQueueCutoff
        guard currentSettledQueueSequence >= abandonedEvidenceCutoff else {
            throw StateError.readyPrefixNotSettled(
                settled: currentSettledQueueSequence,
                readyCutoff: abandonedEvidenceCutoff
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
            guard evidence.queueSequence > abandonedEvidenceCutoff else {
                throw StateError.readyPrefixStillPending(
                    queueSequence: evidence.queueSequence,
                    readyCutoff: abandonedEvidenceCutoff
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
