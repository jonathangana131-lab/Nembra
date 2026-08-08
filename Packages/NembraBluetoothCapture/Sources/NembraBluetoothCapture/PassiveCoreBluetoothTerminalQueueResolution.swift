import Foundation

/// Converts an accepted terminal-retirement receipt into explicit global FIFO
/// resolution authority without pretending retired callbacks were recorder writes.
struct PassiveCoreBluetoothTerminalQueueResolution: Sendable {
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

    /// Requires the live gate to remain the exact terminal transaction that issued
    /// retirement, including its process-local UUID. The controller's global
    /// resolved frontier must still be exactly H, its enqueue tail must not have
    /// advanced, and zero preserved pending evidence may remain.
    ///
    /// Success means H+1...tail is resolved *by retirement*. It says nothing about
    /// those callbacks being persisted in a capture artifact.
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
