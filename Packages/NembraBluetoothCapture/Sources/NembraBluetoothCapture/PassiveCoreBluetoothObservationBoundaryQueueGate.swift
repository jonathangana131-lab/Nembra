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
            case uncommittedReadyAbandonedBeforeRecorderMutation
            case uncommittedReadyRejectedBeforeRecorderMutation
            case recordedReadyInvalidatedBeforeGateCommit
            case committedReadyInvalidated
            case uncommittedHorizonAbandonedBeforeRecorderMutation
            case uncommittedHorizonRejectedBeforeRecorderMutation
            case recordedHorizonInvalidatedBeforeGateCommit
            case committedHorizonInvalidatedBeforeArtifactFreeze
        }

        let abandonedReadyAuthority: PassiveCoreBluetoothArtifactAuthorityContext
        let abandonedReadyQueueCutoff: UInt64
        let abandonedReadyTransactionRevision: UInt64
        let abandonedReadyTransactionIdentity: UUID
        let abandonedTargetSessionGeneration: UInt64
        /// Exact Horizon transaction abandoned before any H recorder mutation. These
        /// fields are lifecycle provenance only and must not extend
        /// `abandonedEvidenceQueueCutoff`.
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

        /// Furthest queue prefix already represented by durable capture evidence in
        /// this abandoned epoch. A pre-mutation Ready abandonment may preserve raw FIFO
        /// evidence through the Ready cutoff without fabricating a durable Ready marker;
        /// recorded/committed Horizon extends the evidence prefix through H.
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
        guard nextRevision != UInt64.max else {
            throw StateError.transactionRevisionExhausted
        }

        let transaction = Transaction(
            boundaryKind: .finiteAcquisitionReady,
            queueCutoff: queueCutoff,
            authority: authority,
            revision: nextRevision
        )
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

    /// Abandons an exact Ready admission before any recorder attempt only when the
    /// admission itself proves the shared one-shot mutation permit was still unused and
    /// is now permanently consumed. Raw FIFO evidence through the Ready cutoff remains
    /// historical evidence, but no Ready lifecycle marker is fabricated.
    @discardableResult
    mutating func abortUncommittedReady(
        after abandonment: PassiveCoreBluetoothObservationBoundaryTransactionDecision.ReadyRecorderMutationAbandonmentReceipt
    ) throws -> ObservationEpochAbortReceipt {
        guard case let .drainingReady(current) = phase else {
            throw StateError.invalidTransition
        }
        guard current.authority == abandonment.authority,
              current.queueCutoff == abandonment.queueCutoff,
              current.revision == abandonment.transactionRevision,
              current.identity == abandonment.transactionIdentity else {
            throw StateError.staleTransaction
        }
        let receipt = ObservationEpochAbortReceipt(
            abandonedReadyTransaction: current,
            origin: .uncommittedReadyAbandonedBeforeRecorderMutation
        )
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

    /// Abandons an exact Horizon admission before any recorder attempt only when the
    /// admission itself proves its shared one-shot mutation permit was still unused and
    /// is now permanently consumed. This is deliberate fail-closed abandonment, not an
    /// authority-rejection claim and not durable H evidence.
    @discardableResult
    mutating func abortUncommittedHorizon(
        after abandonment: PassiveCoreBluetoothObservationBoundaryTransactionDecision.HorizonRecorderMutationAbandonmentReceipt
    ) throws -> ObservationEpochAbortReceipt {
        guard case let .drainingHorizon(currentHorizon) = phase,
              let ready = committedReadyTransaction else {
            throw StateError.invalidTransition
        }
        guard currentHorizon.authority == abandonment.authority,
              currentHorizon.queueCutoff == abandonment.queueCutoff,
              currentHorizon.revision == abandonment.transactionRevision,
              currentHorizon.identity == abandonment.transactionIdentity else {
            throw StateError.staleTransaction
        }
        let receipt = ObservationEpochAbortReceipt(
            abandonedReadyTransaction: ready,
            origin: .uncommittedHorizonAbandonedBeforeRecorderMutation,
            abandonedUnrecordedHorizonTransaction: currentHorizon
        )
        committedReadyTransaction = nil
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

    /// Abort quarantine is intentionally irreversible in this slice. Raw FIFO
    /// retirement alone cannot reopen lifecycle admission because retired positions
    /// still need a separate globally-resolved frontier update. #450 owns that
    /// producer and its successor integration must make fresh-session reopen consume
    /// the producer-issued resolution receipt. Until then reset and Ready both fail.
    @discardableResult
    mutating func resetForNewCaptureSession() -> Bool {
        guard phase == .awaitingReady else { return false }
        committedReadyTransaction = nil
        return true
    }
}