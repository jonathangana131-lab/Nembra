/// Converts a producer-issued abandoned-observation retirement receipt into
/// explicit global FIFO resolution authority without pretending the retired queue
/// positions were appended to a capture recorder.
///
/// `PassiveCoreBluetoothAbortedObservationQueueRetirement` proves that, while the
/// abandoned Ready/Horizon epoch remains quarantined and its drain is idle, the
/// complete still-pending suffix for that target session was validated and removed.
/// Those queue positions are therefore settled by an accepted lifecycle decision,
/// but they are not recorder evidence.
///
/// Final controller composition can consume this receipt to advance a dedicated
/// globally-resolved frontier while preserving recorder-written/processed-through
/// truth separately. This type never mutates the queue gate, FIFO, recorder, or
/// controller counters.
///
/// Software queue chronology only. No BLE/RF emission time, scooter identity,
/// telemetry meaning, command acknowledgement, or physical ES80 behavior is
/// established here.
struct PassiveCoreBluetoothAbortedQueueResolution: Sendable {
    struct Receipt: Equatable, Sendable {
        let abortReceipt: PassiveCoreBluetoothObservationBoundaryQueueGate.ObservationEpochAbortReceipt
        let previouslyResolvedThroughQueueSequence: UInt64
        let resolvedThroughQueueSequence: UInt64
        let retiredEvidenceCount: Int

        var advancesResolvedFrontier: Bool {
            resolvedThroughQueueSequence > previouslyResolvedThroughQueueSequence
        }

        fileprivate init(
            abortReceipt: PassiveCoreBluetoothObservationBoundaryQueueGate.ObservationEpochAbortReceipt,
            previouslyResolvedThroughQueueSequence: UInt64,
            resolvedThroughQueueSequence: UInt64,
            retiredEvidenceCount: Int
        ) {
            self.abortReceipt = abortReceipt
            self.previouslyResolvedThroughQueueSequence = previouslyResolvedThroughQueueSequence
            self.resolvedThroughQueueSequence = resolvedThroughQueueSequence
            self.retiredEvidenceCount = retiredEvidenceCount
        }
    }

    enum StateError: Error, Equatable, Sendable {
        case abortQuarantineRequired
        case abortReceiptMismatch
        case resolvedFrontierDoesNotMatchRetirementSettled(current: UInt64, settled: UInt64)
        case controllerQueueChangedAfterRetirement(expected: UInt64, actual: UInt64)
        case retainedEvidenceUnexpected(retainedCount: Int)
        case settledFrontierPrecedesAbandonedEvidence(settled: UInt64, evidenceCutoff: UInt64)
        case invalidRetirementCoverage(settled: UInt64, tail: UInt64, retiredCount: Int)
    }

    /// Resolves an accepted abandoned-observation retirement synchronously on
    /// MainActor.
    ///
    /// Admission is deliberately strict:
    /// - the queue gate must still be in the exact abort-quarantined epoch that
    ///   produced the retirement proof;
    /// - the controller's current globally-resolved frontier must equal the exact
    ///   settled frontier validated by the retirement producer;
    /// - the controller's global enqueue tail must still equal the retirement tail,
    ///   so any callback accepted after retirement makes this proof stale;
    /// - no pending evidence may remain;
    /// - the retired count must exactly cover `settled + 1 ... tail`, or be zero
    ///   when the tail already equals the settled frontier;
    /// - the settled frontier may not precede the furthest durable lifecycle
    ///   evidence in the abandoned epoch: Ready normally, or Horizon when H was
    ///   durably recorded before its queue commit failed.
    ///
    /// A successful receipt means only that queue positions through the validated
    /// tail are globally resolved. It never relabels retired callbacks as recorder
    /// writes, never upgrades the abandoned recorder into complete evidence, and
    /// never reopens lifecycle admission by itself.
    @MainActor
    static func resolve(
        currentResolvedThroughQueueSequence: UInt64,
        currentLastEnqueuedEventSequence: UInt64,
        retirementReceipt: PassiveCoreBluetoothAbortedObservationQueueRetirement.Receipt,
        abortedGate: PassiveCoreBluetoothObservationBoundaryQueueGate
    ) throws -> Receipt {
        guard case let .abortQuarantined(currentAbort) = abortedGate.phase else {
            throw StateError.abortQuarantineRequired
        }
        guard currentAbort == retirementReceipt.abortReceipt else {
            throw StateError.abortReceiptMismatch
        }

        let settled = retirementReceipt.validatedSettledQueueSequence
        let tail = retirementReceipt.validatedQueueTailSequence
        let evidenceCutoff = retirementReceipt.abortReceipt.abandonedEvidenceQueueCutoff

        guard currentResolvedThroughQueueSequence == settled else {
            throw StateError.resolvedFrontierDoesNotMatchRetirementSettled(
                current: currentResolvedThroughQueueSequence,
                settled: settled
            )
        }

        guard currentLastEnqueuedEventSequence == tail else {
            throw StateError.controllerQueueChangedAfterRetirement(
                expected: tail,
                actual: currentLastEnqueuedEventSequence
            )
        }

        guard retirementReceipt.retainedPendingEvidenceCount == 0 else {
            throw StateError.retainedEvidenceUnexpected(
                retainedCount: retirementReceipt.retainedPendingEvidenceCount
            )
        }

        guard settled >= evidenceCutoff else {
            throw StateError.settledFrontierPrecedesAbandonedEvidence(
                settled: settled,
                evidenceCutoff: evidenceCutoff
            )
        }

        let coverageIsValid: Bool
        if tail == settled {
            coverageIsValid = retirementReceipt.retiredEvidenceCount == 0
        } else if tail > settled,
                  let expectedRetiredCount = Int(exactly: tail - settled) {
            coverageIsValid = retirementReceipt.retiredEvidenceCount == expectedRetiredCount
        } else {
            coverageIsValid = false
        }

        guard coverageIsValid else {
            throw StateError.invalidRetirementCoverage(
                settled: settled,
                tail: tail,
                retiredCount: retirementReceipt.retiredEvidenceCount
            )
        }

        return Receipt(
            abortReceipt: retirementReceipt.abortReceipt,
            previouslyResolvedThroughQueueSequence: settled,
            resolvedThroughQueueSequence: tail,
            retiredEvidenceCount: retirementReceipt.retiredEvidenceCount
        )
    }
}