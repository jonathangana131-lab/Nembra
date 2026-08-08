import Foundation

/// MainActor-facing ordering state for recording lifecycle boundaries against the
/// controller's existing raw-event FIFO.
///
/// Queue sequence is software callback-order evidence only. It is not BLE/RF
/// emission time, a CoreBluetooth generation, or physical scooter proof.
struct PassiveCoreBluetoothObservationBoundaryQueueGate: Equatable, Sendable {
    enum BoundaryKind: Equatable, Sendable {
        case finiteAcquisitionReady
        case observationHorizon
    }

    enum StateError: Error, Equatable, Sendable {
        case invalidTransition
        case transactionRevisionExhausted
        case staleTransaction
        case authorityChanged
        case horizonProcessedPrefixRequired
        case processedPrefixPrecedesReady
        case horizonCutoffPrecedesReady
        case horizonCutoffPrecedesProcessedPrefix
        case cutoffNotDrained
        case cutoffOverrun
        case horizonArtifactNotReady
        case freshTargetSessionRequired
        case resolvedQueueTailChanged(expected: UInt64, actual: UInt64)
    }

    struct Transaction: Equatable, Sendable {
        let boundaryKind: BoundaryKind
        let queueCutoff: UInt64
        let authority: PassiveCoreBluetoothArtifactAuthorityContext
        let revision: UInt64
        /// Opaque process-local identity for this exact gate transaction. It is not
        /// persisted evidence and carries no BLE/RF or scooter meaning.
        let identity: UUID

        /// Only this gate source may construct raw queue transactions. Other package
        /// files must consume the producer-issued typestate projected by #440.
        fileprivate init(
            boundaryKind: BoundaryKind,
            queueCutoff: UInt64,
            authority: PassiveCoreBluetoothArtifactAuthorityContext,
            revision: UInt64,
            identity: UUID = UUID()
        ) {
            self.boundaryKind = boundaryKind
            self.queueCutoff = queueCutoff
            self.authority = authority
            self.revision = revision
            self.identity = identity
        }
    }

    /// Producer-issued proof that one Ready/Horizon attempt or observation epoch was
    /// intentionally abandoned before terminal artifact freeze. The abandoned recorder
    /// remains incomplete evidence; this receipt never upgrades it into a terminal artifact.
    struct ObservationEpochAbortReceipt: Equatable, Sendable {
        enum Origin: Equatable, Sendable {
            case uncommittedReadyRejectedBeforeRecorderMutation
            case recordedReadyInvalidatedBeforeGateCommit
            case committedReadyInvalidated
            case uncommittedHorizonRejectedBeforeRecorderMutation
            case recordedHorizonInvalidatedBeforeGateCommit
            case committedHorizonInvalidatedBeforeArtifactFreeze
        }

        let abandonedReadyAuthority: PassiveCoreBluetoothArtifactAuthorityContext
        let abandonedReadyQueueCutoff: UInt64
        let abandonedReadyTransactionRevision: UInt64
        let abandonedReadyTransactionIdentity: UUID
        let abandonedTargetSessionGeneration: UInt64
        /// Exact Horizon transaction abandoned after canonical mutation-point rejection
        /// but before any H recorder mutation. These fields are lifecycle provenance
        /// only and must not extend `abandonedEvidenceQueueCutoff`.
        let abandonedUnrecordedHorizonQueueCutoff: UInt64?
        let abandonedUnrecordedHorizonTransactionRevision: UInt64?
        let abandonedUnrecordedHorizonTransactionIdentity: UUID?
        /// Exact Horizon transaction whose recorder mutation succeeded durably before
        /// queue commit failed, or whose queue commit succeeded before artifact freeze
        /// was intentionally abandoned. Presence here extends durable evidence through H.
        let abandonedHorizonQueueCutoff: UInt64?
        let abandonedHorizonTransactionRevision: UInt64?
        let abandonedHorizonTransactionIdentity: UUID?
        let origin: Origin

        /// Furthest queue prefix already represented by durable lifecycle evidence in
        /// this abandoned epoch. Recorded/committed Horizon extends it through H; a
        /// zero-mutation Horizon rejection deliberately leaves Ready as the boundary.
        var abandonedEvidenceQueueCutoff: UInt64 {
            abandonedHorizonQueueCutoff ?? abandonedReadyQueueCutoff
        }

        fileprivate init(
            abandonedReadyTransaction: Transaction,
            origin: Origin,
            abandonedUnrecordedHorizonTransaction: Transaction? = nil,
            abandonedHorizonTransaction: Transaction? = nil
        ) {
            abandonedReadyAuthority = abandonedReadyTransaction.authority
            abandonedReadyQueueCutoff = abandonedReadyTransaction.queueCutoff
            abandonedReadyTransactionRevision = abandonedReadyTransaction.revision
            abandonedReadyTransactionIdentity = abandonedReadyTransaction.identity
            abandonedTargetSessionGeneration = abandonedReadyTransaction.authority.targetSessionGeneration
            abandonedUnrecordedHorizonQueueCutoff = abandonedUnrecordedHorizonTransaction?.queueCutoff
            abandonedUnrecordedHorizonTransactionRevision = abandonedUnrecordedHorizonTransaction?.revision
            abandonedUnrecordedHorizonTransactionIdentity = abandonedUnrecordedHorizonTransaction?.identity
            abandonedHorizonQueueCutoff = abandonedHorizonTransaction?.queueCutoff
            abandonedHorizonTransactionRevision = abandonedHorizonTransaction?.revision
            abandonedHorizonTransactionIdentity = abandonedHorizonTransaction?.identity
            self.origin = origin
        }
    }

    enum Phase: Equatable, Sendable {
        case awaitingReady
        case drainingReady(Transaction)
        case observing
        case abortQuarantined(ObservationEpochAbortReceipt)
        case drainingHorizon(Transaction)
        case horizonBoundaryRecorded(Transaction)
        case terminal(Transaction)
    }

    private(set) var phase: Phase = .awaitingReady
    private var nextRevision: UInt64 = 1
    private var committedReadyTransaction: Transaction?
    // Recovery binds exactly one already-created fresh durable target session.
    // Normal reset cannot erase this admission requirement.
    private var requiredReadyTargetSessionGeneration: UInt64?

    var isTerminal: Bool {
        if case .terminal = phase { return true }
        return false
    }

    var isAbortQuarantined: Bool {
        if case .abortQuarantined = phase { return true }
        return false
    }

    var activeTransaction: Transaction? {
        switch phase {
        case let .drainingReady(transaction),
             let .drainingHorizon(transaction),
             let .horizonBoundaryRecorded(transaction):
            transaction
        case .awaitingReady, .observing, .abortQuarantined, .terminal:
            nil
        }
    }

    var terminalQueueCutoff: UInt64? {
        guard case let .terminal(transaction) = phase else { return nil }
        return transaction.queueCutoff
    }

    /// Begins Ready only. Horizon has a separate producer-identity entry below so a
    /// structurally identical but foreign committed Ready epoch cannot open H.
    mutating func begin(
        _ boundaryKind: BoundaryKind,
        through queueCutoff: UInt64,
        processedThrough processedQueueSequence: UInt64? = nil,
        authority: PassiveCoreBluetoothArtifactAuthorityContext
    ) throws -> Transaction {
        guard boundaryKind == .finiteAcquisitionReady,
              phase == .awaitingReady else {
            throw StateError.invalidTransition
        }
        guard processedQueueSequence == nil else {
            throw StateError.invalidTransition
        }
        if let requiredReadyTargetSessionGeneration {
            guard authority.targetSessionGeneration == requiredReadyTargetSessionGeneration else {
                throw StateError.freshTargetSessionRequired
            }
        }
        guard nextRevision != UInt64.max else {
            throw StateError.transactionRevisionExhausted
        }

        let transaction = Transaction(
            boundaryKind: .finiteAcquisitionReady,
            queueCutoff: queueCutoff,
            authority: authority,
            revision: nextRevision
        )
        requiredReadyTargetSessionGeneration = nil
        phase = .drainingReady(transaction)
        nextRevision += 1
        return transaction
    }

    /// Opens Horizon only when the caller carries the exact process-local identity of
    /// the Ready transaction that this gate committed. Authority/cutoff equality alone
    /// is deliberately insufficient.
    mutating func beginObservationHorizon(
        through queueCutoff: UInt64,
        processedThrough processedQueueSequence: UInt64,
        authority: PassiveCoreBluetoothArtifactAuthorityContext,
        establishedByReadyRevision readyRevision: UInt64,
        establishedByReadyIdentity readyIdentity: UUID
    ) throws -> Transaction {
        guard phase == .observing,
              let ready = committedReadyTransaction else {
            throw StateError.invalidTransition
        }
        guard ready.revision == readyRevision,
              ready.identity == readyIdentity else {
            throw StateError.staleTransaction
        }
        guard authority == ready.authority else {
            throw StateError.authorityChanged
        }
        guard queueCutoff >= ready.queueCutoff else {
            throw StateError.horizonCutoffPrecedesReady
        }
        guard processedQueueSequence >= ready.queueCutoff else {
            throw StateError.processedPrefixPrecedesReady
        }
        guard queueCutoff >= processedQueueSequence else {
            throw StateError.horizonCutoffPrecedesProcessedPrefix
        }
        guard nextRevision != UInt64.max else {
            throw StateError.transactionRevisionExhausted
        }

        let transaction = Transaction(
            boundaryKind: .observationHorizon,
            queueCutoff: queueCutoff,
            authority: authority,
            revision: nextRevision
        )
        phase = .drainingHorizon(transaction)
        nextRevision += 1
        return transaction
    }

    func permittedDrainUpperBound(
        firstPending: UInt64,
        pendingTail: UInt64
    ) -> UInt64? {
        guard firstPending <= pendingTail else { return nil }
        switch phase {
        case let .drainingReady(transaction),
             let .drainingHorizon(transaction),
             let .horizonBoundaryRecorded(transaction):
            let upperBound = min(transaction.queueCutoff, pendingTail)
            return firstPending <= upperBound ? upperBound : nil
        case .abortQuarantined, .terminal:
            return nil
        case .awaitingReady, .observing:
            return pendingTail
        }
    }

    mutating func markBoundaryRecorded(
        _ transaction: Transaction,
        lastProcessedQueueSequence: UInt64,
        currentAuthority: PassiveCoreBluetoothArtifactAuthorityContext
    ) throws {
        switch phase {
        case let .drainingReady(current), let .drainingHorizon(current):
            guard current == transaction else { throw StateError.staleTransaction }
        default:
            throw StateError.staleTransaction
        }
        guard transaction.authority == currentAuthority else {
            throw StateError.authorityChanged
        }
        guard lastProcessedQueueSequence >= transaction.queueCutoff else {
            throw StateError.cutoffNotDrained
        }
        guard lastProcessedQueueSequence == transaction.queueCutoff else {
            throw StateError.cutoffOverrun
        }

        switch phase {
        case .drainingReady:
            committedReadyTransaction = transaction
            phase = .observing
        case .drainingHorizon:
            phase = .horizonBoundaryRecorded(transaction)
        default:
            throw StateError.staleTransaction
        }
    }

    mutating func completeHorizonArtifactFreeze(
        _ transaction: Transaction,
        currentAuthority: PassiveCoreBluetoothArtifactAuthorityContext
    ) throws {
        guard transaction.authority == currentAuthority else {
            throw StateError.authorityChanged
        }
        guard case let .horizonBoundaryRecorded(current) = phase,
              current == transaction else {
            throw StateError.horizonArtifactNotReady
        }
        phase = .terminal(transaction)
    }

    func shouldDiscardQueuedEvidenceAfterTerminalHorizon(
        queueSequence: UInt64,
        authority: PassiveCoreBluetoothArtifactAuthorityContext
    ) -> Bool {
        guard case let .terminal(transaction) = phase,
              transaction.authority == authority else { return false }
        return queueSequence > transaction.queueCutoff
    }

    /// Abandons an already-committed Ready epoch using #440's producer-issued token.
    @discardableResult
    mutating func abortObservationEpoch(
        _ committedReadyEpoch: PassiveCoreBluetoothObservationBoundaryTransactionDecision.CommittedReadyEpoch
    ) throws -> ObservationEpochAbortReceipt {
        guard phase == .observing,
              let current = committedReadyTransaction else {
            throw StateError.invalidTransition
        }
        guard current.authority == committedReadyEpoch.authority,
              current.queueCutoff == committedReadyEpoch.queueCutoff,
              current.revision == committedReadyEpoch.transactionRevision,
              current.identity == committedReadyEpoch.transactionIdentity else {
            throw StateError.staleTransaction
        }
        let receipt = ObservationEpochAbortReceipt(
            abandonedReadyTransaction: current,
            origin: .committedReadyInvalidated
        )
        committedReadyTransaction = nil
        phase = .abortQuarantined(receipt)
        return receipt
    }

    /// Abandons Ready only when #440 proves its authority-fenced recorder mutation was
    /// rejected before the mutation body executed.
    @discardableResult
    mutating func abortUncommittedReady(
        after rejection: PassiveCoreBluetoothObservationBoundaryTransactionDecision.ReadyRecorderMutationRejectionReceipt
    ) throws -> ObservationEpochAbortReceipt {
        guard case let .drainingReady(current) = phase else {
            throw StateError.invalidTransition
        }
        guard current.authority == rejection.authority,
              current.queueCutoff == rejection.queueCutoff,
              current.revision == rejection.transactionRevision,
              current.identity == rejection.transactionIdentity else {
            throw StateError.staleTransaction
        }
        let receipt = ObservationEpochAbortReceipt(
            abandonedReadyTransaction: current,
            origin: .uncommittedReadyRejectedBeforeRecorderMutation
        )
        phase = .abortQuarantined(receipt)
        return receipt
    }

    /// Covers the distinct interlock where the Ready recorder append succeeded but
    /// MainActor lifecycle authority invalidated before immediate queue commit. The
    /// producer-issued `RecordedReadyBoundary` proves durable Ready evidence exists;
    /// quarantine therefore does not mislabel it as a zero-mutation rejection.
    @discardableResult
    mutating func abortRecordedReadyBeforeGateCommit(
        _ recordedReady: PassiveCoreBluetoothObservationBoundaryTransactionDecision.RecordedReadyBoundary
    ) throws -> ObservationEpochAbortReceipt {
        guard case let .drainingReady(current) = phase else {
            throw StateError.invalidTransition
        }
        guard current.authority == recordedReady.authority,
              current.queueCutoff == recordedReady.queueCutoff,
              current.revision == recordedReady.transactionRevision,
              current.identity == recordedReady.transactionIdentity else {
            throw StateError.staleTransaction
        }
        let receipt = ObservationEpochAbortReceipt(
            abandonedReadyTransaction: current,
            origin: .recordedReadyInvalidatedBeforeGateCommit
        )
        phase = .abortQuarantined(receipt)
        return receipt
    }

    /// Abandons an exact Horizon admission only when the canonical mutation-point
    /// fence proves authority changed before the recorder mutation body executed. The
    /// Ready boundary remains the furthest durable lifecycle boundary; the H transaction
    /// is preserved separately as zero-mutation lifecycle provenance.
    @discardableResult
    mutating func abortUncommittedHorizon(
        after rejection: PassiveCoreBluetoothObservationBoundaryTransactionDecision.HorizonRecorderMutationRejectionReceipt
    ) throws -> ObservationEpochAbortReceipt {
        guard case let .drainingHorizon(currentHorizon) = phase,
              let ready = committedReadyTransaction else {
            throw StateError.invalidTransition
        }
        guard currentHorizon.authority == rejection.authority,
              currentHorizon.queueCutoff == rejection.queueCutoff,
              currentHorizon.revision == rejection.transactionRevision,
              currentHorizon.identity == rejection.transactionIdentity else {
            throw StateError.staleTransaction
        }
        let receipt = ObservationEpochAbortReceipt(
            abandonedReadyTransaction: ready,
            origin: .uncommittedHorizonRejectedBeforeRecorderMutation,
            abandonedUnrecordedHorizonTransaction: currentHorizon
        )
        committedReadyTransaction = nil
        phase = .abortQuarantined(receipt)
        return receipt
    }

    /// A Horizon recorder append may win under valid authority, then its queue commit
    /// can fail before terminal freeze. Preserve that durable H as incomplete historical
    /// evidence and quarantine the exact producer-issued epoch; never promote it to
    /// terminal/frozen authority merely because the recorder mutation succeeded.
    @discardableResult
    mutating func abortRecordedHorizonBeforeGateCommit(
        _ recordedHorizon: PassiveCoreBluetoothObservationBoundaryTransactionDecision.RecordedHorizonBoundary
    ) throws -> ObservationEpochAbortReceipt {
        guard case let .drainingHorizon(currentHorizon) = phase,
              let ready = committedReadyTransaction else {
            throw StateError.invalidTransition
        }
        guard currentHorizon.authority == recordedHorizon.authority,
              currentHorizon.queueCutoff == recordedHorizon.queueCutoff,
              currentHorizon.revision == recordedHorizon.transactionRevision,
              currentHorizon.identity == recordedHorizon.transactionIdentity else {
            throw StateError.staleTransaction
        }
        let receipt = ObservationEpochAbortReceipt(
            abandonedReadyTransaction: ready,
            origin: .recordedHorizonInvalidatedBeforeGateCommit,
            abandonedHorizonTransaction: currentHorizon
        )
        committedReadyTransaction = nil
        phase = .abortQuarantined(receipt)
        return receipt
    }

    /// Abandons an already durable and queue-committed H when artifact creation,
    /// integrity validation, or final authority validation fails before terminal
    /// freeze. H remains durable incomplete evidence; this transition never retries
    /// under a newer authority and never fabricates terminal artifact success.
    @discardableResult
    mutating func abortCommittedHorizonBeforeArtifactFreeze(
        _ committedHorizon: PassiveCoreBluetoothObservationBoundaryTransactionDecision.CommittedHorizonBoundary
    ) throws -> ObservationEpochAbortReceipt {
        guard case let .horizonBoundaryRecorded(currentHorizon) = phase,
              let ready = committedReadyTransaction else {
            throw StateError.invalidTransition
        }
        guard currentHorizon.authority == committedHorizon.authority,
              currentHorizon.queueCutoff == committedHorizon.queueCutoff,
              currentHorizon.revision == committedHorizon.transactionRevision,
              currentHorizon.identity == committedHorizon.transactionIdentity else {
            throw StateError.staleTransaction
        }
        let receipt = ObservationEpochAbortReceipt(
            abandonedReadyTransaction: ready,
            origin: .committedHorizonInvalidatedBeforeArtifactFreeze,
            abandonedHorizonTransaction: currentHorizon
        )
        committedReadyTransaction = nil
        phase = .abortQuarantined(receipt)
        return receipt
    }

    /// Reopens an abandoned Ready/Horizon lifecycle only after the separate
    /// retirement producer has been converted into explicit globally-resolved FIFO
    /// authority. Retired positions remain resolved-by-retirement, never recorder writes.
    /// A callback accepted after resolution invalidates the receipt before mutation.
    ///
    /// The controller must create the fresh durable recorder/target session first, then
    /// resolve and consume this receipt synchronously on MainActor with no intervening await.
    mutating func reopenAfterAbortedQueueResolution(
        _ resolution: PassiveCoreBluetoothAbortedQueueResolution.Receipt,
        currentLastEnqueuedEventSequence: UInt64,
        freshTargetSessionGeneration: UInt64
    ) throws {
        guard case let .abortQuarantined(currentAbort) = phase else {
            throw StateError.invalidTransition
        }
        guard resolution.abortReceipt == currentAbort else {
            throw StateError.staleTransaction
        }
        guard resolution.resolvedThroughQueueSequence == currentLastEnqueuedEventSequence else {
            throw StateError.resolvedQueueTailChanged(
                expected: resolution.resolvedThroughQueueSequence,
                actual: currentLastEnqueuedEventSequence
            )
        }
        guard freshTargetSessionGeneration > currentAbort.abandonedTargetSessionGeneration else {
            throw StateError.freshTargetSessionRequired
        }

        committedReadyTransaction = nil
        requiredReadyTargetSessionGeneration = freshTargetSessionGeneration
        phase = .awaitingReady
    }

    /// Reopens after a successful terminal Horizon only from producer-issued terminal
    /// resolution proof for the exact sealed transaction and an unchanged global tail.
    /// The next Ready is bound to one exact strictly newer durable target session.
    mutating func reopenAfterTerminalQueueResolution(
        _ resolution: PassiveCoreBluetoothTerminalQueueResolution.Receipt,
        currentLastEnqueuedEventSequence: UInt64,
        freshTargetSessionGeneration: UInt64
    ) throws {
        guard case let .terminal(transaction) = phase else {
            throw StateError.invalidTransition
        }
        guard resolution.terminalTransactionRevision == transaction.revision,
              resolution.horizonQueueCutoff == transaction.queueCutoff,
              resolution.previouslyResolvedThroughQueueSequence == transaction.queueCutoff else {
            throw StateError.staleTransaction
        }
        guard resolution.terminalAuthority == transaction.authority else {
            throw StateError.authorityChanged
        }
        guard resolution.resolvedThroughQueueSequence == currentLastEnqueuedEventSequence else {
            throw StateError.resolvedQueueTailChanged(
                expected: resolution.resolvedThroughQueueSequence,
                actual: currentLastEnqueuedEventSequence
            )
        }
        guard freshTargetSessionGeneration > transaction.authority.targetSessionGeneration else {
            throw StateError.freshTargetSessionRequired
        }

        committedReadyTransaction = nil
        requiredReadyTargetSessionGeneration = freshTargetSessionGeneration
        phase = .awaitingReady
    }

    /// Reset is intentionally weak: it can only act while already awaiting Ready and
    /// cannot erase an exact fresh-session binding installed by either recovery path.
    @discardableResult
    mutating func resetForNewCaptureSession() -> Bool {
        guard phase == .awaitingReady else { return false }
        committedReadyTransaction = nil
        return true
    }
}
