import Foundation

/// Converts an accepted terminal-retirement receipt into explicit controller-FIFO
/// resolution authority without relabeling retired callbacks as recorder writes.
///
/// The foreground controller currently tracks one numeric processed frontier. That
/// is sufficient while every accepted queue position is actually drained to its
/// captured recorder. Terminal Horizon retirement deliberately changes that: the
/// exact post-H suffix may be discarded because it belongs to the recorder that
/// has already been frozen. Those queue positions are then *resolved*, but they
/// were not recorded and must never be described as recorded evidence.
///
/// This helper is intentionally additive. It does not mutate the queue gate,
/// recorder, pending FIFO, or controller counters. Final controller composition
/// can consume the returned receipt to advance a distinct resolved frontier while
/// preserving its last recorder-written frontier separately.
///
/// Software FIFO chronology only. No BLE/RF timing, scooter identity, telemetry
/// semantics, or physical AOVOPRO ES80 behavior is established here.
struct PassiveCoreBluetoothTerminalQueueResolution: Sendable {
    /// Producer-issued proof that the complete queue interval after terminal H and
    /// through `resolvedThroughQueueSequence` has been intentionally resolved by
    /// accepted retirement rather than recorder mutation.
    struct Receipt: Equatable, Sendable {
        let terminalAuthority: PassiveCoreBluetoothArtifactAuthorityContext
        let terminalTransactionRevision: UInt64
        let terminalTransactionIdentity: UUID
        let horizonQueueCutoff: UInt64
        let previouslyResolvedThroughQueueSequence: UInt64
        let resolvedThroughQueueSequence: UInt64
        let retiredEvidenceCount: Int

        var advancesResolvedFrontier: Bool {
            resolvedThroughQueueSequence > previouslyResolvedThroughQueueSequence
        }

        fileprivate init(
            terminalAuthority: PassiveCoreBluetoothArtifactAuthorityContext,
            terminalTransactionRevision: UInt64,
            terminalTransactionIdentity: UUID,
            horizonQueueCutoff: UInt64,
            previouslyResolvedThroughQueueSequence: UInt64,
            resolvedThroughQueueSequence: UInt64,
            retiredEvidenceCount: Int
        ) {
            self.terminalAuthority = terminalAuthority
            self.terminalTransactionRevision = terminalTransactionRevision
            self.terminalTransactionIdentity = terminalTransactionIdentity
            self.horizonQueueCutoff = horizonQueueCutoff
            self.previouslyResolvedThroughQueueSequence = previouslyResolvedThroughQueueSequence
            self.resolvedThroughQueueSequence = resolvedThroughQueueSequence
            self.retiredEvidenceCount = retiredEvidenceCount
        }
    }

    enum StateError: Error, Equatable, Sendable {
        case terminalHorizonRequired
        case staleTerminalTransaction
        case terminalAuthorityChanged
        case resolvedFrontierDoesNotMatchHorizon(current: UInt64, horizon: UInt64)
        case controllerQueueChangedAfterRetirement(expected: UInt64, actual: UInt64)
        case retainedEvidenceRoutingRequired(retainedCount: Int)
        case invalidRetirementCoverage(
            horizon: UInt64,
            validatedTail: UInt64,
            retiredCount: Int,
            firstRetired: UInt64?,
            lastRetired: UInt64?
        )
    }

    /// Resolves a zero-retained terminal retirement synchronously on MainActor.
    ///
    /// Admission is deliberately strict:
    /// - the supplied queue gate must still be the exact terminal transaction that
    ///   issued the retirement receipt. Resolution cannot be delayed until after a
    ///   reopen or substituted with another terminal authority/revision/H;
    /// - the controller's already-resolved frontier must be *exactly* H. This
    ///   proves the terminal boundary did not leave an unresolved pre-H queue gap
    ///   and makes replay fail once the caller advances its frontier;
    /// - the controller's current global queue tail must still equal the tail #419
    ///   validated at retirement. Any newly accepted callback makes the receipt
    ///   stale even when the old retirement itself was valid;
    /// - no retained pending evidence may remain. Preserved evidence requires the
    ///   separate routing/quarantine/adoption authority owned by #419's contract;
    /// - the retirement receipt must describe the complete contiguous H+1...tail
    ///   suffix as retired. This is redundant with today's #419 producer, but
    ///   keeps this consumer fail-closed if that producer evolves later.
    ///
    /// A successful receipt means queue positions through the validated tail are
    /// intentionally resolved. It does *not* say those callbacks were appended to
    /// any capture recorder.
    @MainActor
    static func resolve(
        currentResolvedThroughQueueSequence: UInt64,
        currentLastEnqueuedEventSequence: UInt64,
        retirementReceipt: PassiveCoreBluetoothTerminalQueueRetirement.Receipt,
        terminalGate: PassiveCoreBluetoothObservationBoundaryQueueGate
    ) throws -> Receipt {
        guard case let .terminal(transaction) = terminalGate.phase else {
            throw StateError.terminalHorizonRequired
        }
        guard transaction.revision == retirementReceipt.terminalTransactionRevision,
              transaction.identity == retirementReceipt.terminalTransactionIdentity,
              transaction.queueCutoff == retirementReceipt.horizonQueueCutoff else {
            throw StateError.staleTerminalTransaction
        }
        guard transaction.authority == retirementReceipt.terminalAuthority else {
            throw StateError.terminalAuthorityChanged
        }

        let horizon = retirementReceipt.horizonQueueCutoff
        guard currentResolvedThroughQueueSequence == horizon else {
            throw StateError.resolvedFrontierDoesNotMatchHorizon(
                current: currentResolvedThroughQueueSequence,
                horizon: horizon
            )
        }

        guard currentLastEnqueuedEventSequence == retirementReceipt.validatedQueueTailSequence else {
            throw StateError.controllerQueueChangedAfterRetirement(
                expected: retirementReceipt.validatedQueueTailSequence,
                actual: currentLastEnqueuedEventSequence
            )
        }

        guard !retirementReceipt.requiresRetainedEvidenceRoutingBeforeReopen else {
            throw StateError.retainedEvidenceRoutingRequired(
                retainedCount: retirementReceipt.retainedPendingEvidenceCount
            )
        }

        let tail = retirementReceipt.validatedQueueTailSequence
        let coverageIsValid: Bool
        if tail == horizon {
            coverageIsValid = retirementReceipt.retiredEvidenceCount == 0
                && retirementReceipt.firstRetiredQueueSequence == nil
                && retirementReceipt.lastRetiredQueueSequence == nil
        } else if tail > horizon,
                  let expectedRetiredCount = Int(exactly: tail - horizon) {
            coverageIsValid = retirementReceipt.retiredEvidenceCount == expectedRetiredCount
                && retirementReceipt.firstRetiredQueueSequence == horizon + 1
                && retirementReceipt.lastRetiredQueueSequence == tail
        } else {
            coverageIsValid = false
        }

        guard coverageIsValid else {
            throw StateError.invalidRetirementCoverage(
                horizon: horizon,
                validatedTail: tail,
                retiredCount: retirementReceipt.retiredEvidenceCount,
                firstRetired: retirementReceipt.firstRetiredQueueSequence,
                lastRetired: retirementReceipt.lastRetiredQueueSequence
            )
        }

        return Receipt(
            terminalAuthority: retirementReceipt.terminalAuthority,
            terminalTransactionRevision: retirementReceipt.terminalTransactionRevision,
            terminalTransactionIdentity: retirementReceipt.terminalTransactionIdentity,
            horizonQueueCutoff: horizon,
            previouslyResolvedThroughQueueSequence: currentResolvedThroughQueueSequence,
            resolvedThroughQueueSequence: tail,
            retiredEvidenceCount: retirementReceipt.retiredEvidenceCount
        )
    }
}
