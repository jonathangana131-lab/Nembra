/// MainActor-only retirement proof for abandoning an incomplete Ready -> Horizon
/// capture lifecycle after artifact authority is lost.
///
/// This is deliberately separate from terminal-Horizon retirement. A terminal
/// artifact may preserve foreign/newer queued evidence after H and reopen only
/// through the stronger terminal receipt contract. Here the old *entire target
/// session* is being abandoned before a usable terminal artifact exists, so no
/// pending callback from that target-session generation may survive into the
/// genuinely fresh recorder/gate/session that follows.
///
/// The helper never mutates the boundary gate and never creates the replacement
/// session. It proves only that the controller's global FIFO has no hidden/in-flight
/// gap, that every still-pending item belongs to the exact abandoned target session,
/// and that those pending items were synchronously removed. The controller must
/// consume the receipt without an `await`, reject it if the global FIFO tail changes,
/// then mint exactly the next target-session generation with a fresh recorder and
/// fresh boundary gate before accepting new evidence.
///
/// Queue chronology here is software callback-order evidence only. It proves no
/// BLE/RF completeness, scooter identity, or protocol semantics.
struct PassiveCoreBluetoothPreHorizonSessionRetirement: Sendable {
    enum AbortedPhase: Equatable, Sendable {
        case drainingReady
        case observing
        case drainingHorizon
        case horizonBoundaryRecorded
    }

    struct PendingEvidenceIdentity: Equatable, Sendable {
        let queueSequence: UInt64
        let targetSessionGeneration: UInt64
    }

    struct Receipt: Equatable, Sendable {
        let abortedPhase: AbortedPhase
        let abortedTargetSessionGeneration: UInt64
        let validatedProcessedQueueSequence: UInt64
        let validatedQueueTailSequence: UInt64
        let retiredEvidenceCount: Int
        let firstRetiredQueueSequence: UInt64?
        let lastRetiredQueueSequence: UInt64?

        fileprivate init(
            abortedPhase: AbortedPhase,
            abortedTargetSessionGeneration: UInt64,
            validatedProcessedQueueSequence: UInt64,
            validatedQueueTailSequence: UInt64,
            retiredEvidenceCount: Int,
            firstRetiredQueueSequence: UInt64?,
            lastRetiredQueueSequence: UInt64?
        ) {
            self.abortedPhase = abortedPhase
            self.abortedTargetSessionGeneration = abortedTargetSessionGeneration
            self.validatedProcessedQueueSequence = validatedProcessedQueueSequence
            self.validatedQueueTailSequence = validatedQueueTailSequence
            self.retiredEvidenceCount = retiredEvidenceCount
            self.firstRetiredQueueSequence = firstRetiredQueueSequence
            self.lastRetiredQueueSequence = lastRetiredQueueSequence
        }
    }

    enum StateError: Error, Equatable, Sendable {
        case preHorizonLifecycleRequired
        case invalidAbortedSessionGeneration
        case processedFrontierBeyondQueueTail(processedThrough: UInt64, queueTail: UInt64)
        case unaccountedQueueRange(processedThrough: UInt64, queueTail: UInt64)
        case invalidQueueSequence(UInt64)
        case nonContiguousQueueSequence(expected: UInt64, actual: UInt64)
        case queueTailMismatch(expected: UInt64, actual: UInt64)
        case foreignSessionEvidence(queueSequence: UInt64, targetSessionGeneration: UInt64)
        case staleRetirementReceipt(expectedQueueTail: UInt64, currentQueueTail: UInt64)
        case invalidFreshSessionGeneration(aborted: UInt64, proposed: UInt64)
    }

    /// Synchronously retires the complete still-pending suffix of one abandoned
    /// target session. Validation completes before mutation so every failure leaves
    /// `pendingEvents` byte-for-byte/order-for-order unchanged.
    ///
    /// `lastProcessedQueueSequence` is the controller's recorder-completed global
    /// FIFO frontier. `lastEnqueuedQueueSequence` is the controller's global FIFO
    /// tail. Requiring the pending array to be the exact contiguous suffix between
    /// those two values is what detects an event already removed by an asynchronous
    /// drain but not yet reflected in the completed frontier.
    @MainActor
    static func retire<Event>(
        from pendingEvents: inout [Event],
        boundaryGate: PassiveCoreBluetoothObservationBoundaryQueueGate,
        abortedTargetSessionGeneration: UInt64,
        lastProcessedQueueSequence: UInt64,
        lastEnqueuedQueueSequence: UInt64,
        identity: (Event) -> PendingEvidenceIdentity
    ) throws -> Receipt {
        let abortedPhase: AbortedPhase
        switch boundaryGate.phase {
        case .drainingReady:
            abortedPhase = .drainingReady
        case .observing:
            abortedPhase = .observing
        case .drainingHorizon:
            abortedPhase = .drainingHorizon
        case .horizonBoundaryRecorded:
            abortedPhase = .horizonBoundaryRecorded
        case .awaitingReady, .terminal:
            throw StateError.preHorizonLifecycleRequired
        }

        guard abortedTargetSessionGeneration > 0 else {
            throw StateError.invalidAbortedSessionGeneration
        }
        guard lastProcessedQueueSequence <= lastEnqueuedQueueSequence else {
            throw StateError.processedFrontierBeyondQueueTail(
                processedThrough: lastProcessedQueueSequence,
                queueTail: lastEnqueuedQueueSequence
            )
        }

        if pendingEvents.isEmpty {
            guard lastProcessedQueueSequence == lastEnqueuedQueueSequence else {
                throw StateError.unaccountedQueueRange(
                    processedThrough: lastProcessedQueueSequence,
                    queueTail: lastEnqueuedQueueSequence
                )
            }

            return Receipt(
                abortedPhase: abortedPhase,
                abortedTargetSessionGeneration: abortedTargetSessionGeneration,
                validatedProcessedQueueSequence: lastProcessedQueueSequence,
                validatedQueueTailSequence: lastEnqueuedQueueSequence,
                retiredEvidenceCount: 0,
                firstRetiredQueueSequence: nil,
                lastRetiredQueueSequence: nil
            )
        }

        guard lastProcessedQueueSequence != UInt64.max else {
            throw StateError.unaccountedQueueRange(
                processedThrough: lastProcessedQueueSequence,
                queueTail: lastEnqueuedQueueSequence
            )
        }

        var expectedQueueSequence = lastProcessedQueueSequence + 1
        var firstRetiredQueueSequence: UInt64?
        var lastRetiredQueueSequence: UInt64?

        for event in pendingEvents {
            let evidence = identity(event)
            guard evidence.queueSequence > 0 else {
                throw StateError.invalidQueueSequence(evidence.queueSequence)
            }
            guard evidence.queueSequence == expectedQueueSequence else {
                throw StateError.nonContiguousQueueSequence(
                    expected: expectedQueueSequence,
                    actual: evidence.queueSequence
                )
            }
            guard evidence.targetSessionGeneration == abortedTargetSessionGeneration else {
                throw StateError.foreignSessionEvidence(
                    queueSequence: evidence.queueSequence,
                    targetSessionGeneration: evidence.targetSessionGeneration
                )
            }

            firstRetiredQueueSequence = firstRetiredQueueSequence ?? evidence.queueSequence
            lastRetiredQueueSequence = evidence.queueSequence

            if evidence.queueSequence != UInt64.max {
                expectedQueueSequence = evidence.queueSequence + 1
            }
        }

        guard let lastRetiredQueueSequence else {
            throw StateError.unaccountedQueueRange(
                processedThrough: lastProcessedQueueSequence,
                queueTail: lastEnqueuedQueueSequence
            )
        }
        guard lastRetiredQueueSequence == lastEnqueuedQueueSequence else {
            throw StateError.queueTailMismatch(
                expected: lastEnqueuedQueueSequence,
                actual: lastRetiredQueueSequence
            )
        }

        let retiredEvidenceCount = pendingEvents.count
        pendingEvents.removeAll(keepingCapacity: true)

        return Receipt(
            abortedPhase: abortedPhase,
            abortedTargetSessionGeneration: abortedTargetSessionGeneration,
            validatedProcessedQueueSequence: lastProcessedQueueSequence,
            validatedQueueTailSequence: lastEnqueuedQueueSequence,
            retiredEvidenceCount: retiredEvidenceCount,
            firstRetiredQueueSequence: firstRetiredQueueSequence,
            lastRetiredQueueSequence: lastRetiredQueueSequence
        )
    }

    /// Validates the immediate no-await handoff from an abandoned target session
    /// to its genuinely fresh successor. A callback admitted after retirement makes
    /// the receipt stale by advancing the global FIFO tail. Skipping/reusing target
    /// session generations is rejected so a receipt cannot authorize the wrong
    /// lifecycle even if a later queue tail happens to match by construction.
    static func validateFreshSessionAdmission(
        receipt: Receipt,
        currentLastEnqueuedQueueSequence: UInt64,
        proposedTargetSessionGeneration: UInt64
    ) throws {
        guard currentLastEnqueuedQueueSequence == receipt.validatedQueueTailSequence else {
            throw StateError.staleRetirementReceipt(
                expectedQueueTail: receipt.validatedQueueTailSequence,
                currentQueueTail: currentLastEnqueuedQueueSequence
            )
        }
        guard receipt.abortedTargetSessionGeneration != UInt64.max,
              proposedTargetSessionGeneration == receipt.abortedTargetSessionGeneration + 1 else {
            throw StateError.invalidFreshSessionGeneration(
                aborted: receipt.abortedTargetSessionGeneration,
                proposed: proposedTargetSessionGeneration
            )
        }
    }
}
