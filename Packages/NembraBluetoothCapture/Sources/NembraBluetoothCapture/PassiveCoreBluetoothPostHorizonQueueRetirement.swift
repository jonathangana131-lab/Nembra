/// Package-internal proof that a terminal observation-horizon transaction owns
/// the exact recorder/FIFO authority whose withheld post-horizon callbacks may
/// be retired before a later capture lifecycle is allowed to reopen.
///
/// This type does not decide whether a CoreBluetooth callback physically
/// occurred before or after the horizon. `queueSequence` is only the controller's
/// accepted MainActor FIFO chronology. Retiring an item removes it from the old
/// immutable recorder generation; transport-state handling must continue through
/// the controller's normal CoreBluetooth lifecycle.
///
/// The proof is intentionally bound to the queue gate's exact terminal
/// transaction. A stale transaction, a pre-freeze transaction, or a different
/// artifact authority cannot authorize retirement. This is the bridge required
/// before the controller can safely prove that no old-generation evidence remains
/// queued and then perform a separate lifecycle-reset operation.
struct PassiveCoreBluetoothPostHorizonQueueRetirement: Equatable, Sendable {
    enum StateError: Error, Equatable, Sendable {
        case horizonTransactionRequired
        case terminalTransactionMismatch
        case retiredAuthorityStillQueued(queueSequence: UInt64)
    }

    enum Disposition: Equatable, Sendable {
        /// Evidence from another target-session/artifact-authority generation is
        /// not owned by this retirement proof and must be preserved.
        case preserveDifferentAuthority

        /// Same-authority evidence accepted strictly after the terminal horizon
        /// cutoff belongs outside the frozen artifact and may be removed from the
        /// old recorder FIFO generation.
        case retirePostHorizonEvidence

        /// Same-authority evidence at or before the horizon cutoff should already
        /// have been recorder-complete before the boundary was committed. Its
        /// continued presence blocks lifecycle reopen instead of being discarded.
        case blocksRetirement
    }

    struct QueuedEvidenceIdentity: Equatable, Sendable {
        let queueSequence: UInt64
        let authority: PassiveCoreBluetoothArtifactAuthorityContext
    }

    let horizonQueueCutoff: UInt64
    let retiredAuthority: PassiveCoreBluetoothArtifactAuthorityContext

    private let horizonTransaction: PassiveCoreBluetoothObservationBoundaryQueueGate.Transaction

    init(
        horizonTransaction: PassiveCoreBluetoothObservationBoundaryQueueGate.Transaction,
        terminalGate: PassiveCoreBluetoothObservationBoundaryQueueGate
    ) throws {
        guard horizonTransaction.boundaryKind == .observationHorizon else {
            throw StateError.horizonTransactionRequired
        }
        guard terminalGate.phase == .terminal(horizonTransaction) else {
            throw StateError.terminalTransactionMismatch
        }

        self.horizonTransaction = horizonTransaction
        horizonQueueCutoff = horizonTransaction.queueCutoff
        retiredAuthority = horizonTransaction.authority
    }

    /// Classifies one queued evidence envelope under the still-current terminal
    /// gate. Revalidating the gate on every use prevents a retained proof object
    /// from becoming authority after the queue gate has moved to another state.
    func disposition(
        for queuedEvidence: QueuedEvidenceIdentity,
        terminalGate: PassiveCoreBluetoothObservationBoundaryQueueGate
    ) throws -> Disposition {
        try validateTerminalTransaction(terminalGate)

        guard queuedEvidence.authority == retiredAuthority else {
            return .preserveDifferentAuthority
        }
        guard queuedEvidence.queueSequence > horizonQueueCutoff else {
            return .blocksRetirement
        }

        // Keep the existing gate as the final discard authority. This proof does
        // not duplicate or weaken its terminal-horizon predicate.
        guard terminalGate.shouldDiscardQueuedEvidenceAfterTerminalHorizon(
            queueSequence: queuedEvidence.queueSequence,
            authority: queuedEvidence.authority
        ) else {
            throw StateError.terminalTransactionMismatch
        }
        return .retirePostHorizonEvidence
    }

    /// Proves the old artifact authority is absent from the remaining FIFO after
    /// the caller has removed only `.retirePostHorizonEvidence` items.
    ///
    /// A same-authority prefix item is a stronger failure than a normal post-H
    /// retirement candidate: it means an item that should have been inside the
    /// committed prefix is still queued. Either case blocks lifecycle reopen.
    func validateQueueCanReopen(
        remainingQueuedEvidence: [QueuedEvidenceIdentity],
        terminalGate: PassiveCoreBluetoothObservationBoundaryQueueGate
    ) throws {
        try validateTerminalTransaction(terminalGate)

        if let remaining = remainingQueuedEvidence.first(where: {
            $0.authority == retiredAuthority
        }) {
            throw StateError.retiredAuthorityStillQueued(
                queueSequence: remaining.queueSequence
            )
        }
    }

    private func validateTerminalTransaction(
        _ terminalGate: PassiveCoreBluetoothObservationBoundaryQueueGate
    ) throws {
        guard terminalGate.phase == .terminal(horizonTransaction) else {
            throw StateError.terminalTransactionMismatch
        }
    }
}
