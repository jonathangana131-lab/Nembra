/// MainActor-facing ordering state for recording lifecycle boundaries against the
/// controller's existing raw-event FIFO.
///
/// This type does not record evidence itself. It freezes recorder draining at an
/// exact queue cutoff so a controller can:
/// 1. drain every callback already accepted through that cutoff;
/// 2. record the lifecycle boundary on the recorder actor;
/// 3. for a terminal horizon, keep later callbacks withheld until the immutable
///    artifact is frozen.
///
/// Queue sequence is software callback-order evidence only. It is not BLE/RF
/// emission time, a CoreBluetooth scan generation, or physical scooter proof.
/// `BoundaryKind` is deliberately queue-local: the accepted #379 capture-schema
/// boundary type is downstream of this PR's #383 base and is mapped only after
/// those lineages are intentionally composed.
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
        case abortQueueRetirementRequired
        case abortRetirementReceiptMismatch
        case abortQueueTailChanged
    }

    struct Transaction: Equatable, Sendable {
        let boundaryKind: BoundaryKind
        let queueCutoff: UInt64
        let authority: PassiveCoreBluetoothArtifactAuthorityContext
        let revision: UInt64
    }

    /// Producer-issued proof that one Ready attempt/epoch was intentionally
    /// abandoned before Horizon. The abandoned recorder remains incomplete
    /// evidence; this receipt never upgrades it into a terminal artifact and
    /// carries no physical scooter meaning.
    struct ObservationEpochAbortReceipt: Equatable, Sendable {
        enum Origin: Equatable, Sendable {
            case uncommittedReadyRejectedBeforeRecorderMutation
            case committedReadyInvalidated
        }

        let abandonedReadyAuthority: PassiveCoreBluetoothArtifactAuthorityContext
        let abandonedReadyQueueCutoff: UInt64
        let abandonedReadyTransactionRevision: UInt64
        let abandonedTargetSessionGeneration: UInt64
        let origin: Origin

        fileprivate init(
            abandonedReadyTransaction: Transaction,
            origin: Origin
        ) {
            abandonedReadyAuthority = abandonedReadyTransaction.authority
            abandonedReadyQueueCutoff = abandonedReadyTransaction.queueCutoff
            abandonedReadyTransactionRevision = abandonedReadyTransaction.revision
            abandonedTargetSessionGeneration =
                abandonedReadyTransaction.authority.targetSessionGeneration
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

    /// The exact ready transaction that established the observation epoch.
    ///
    /// `phase == .observing` deliberately remains lightweight for callers, but the
    /// committed ready cutoff and authority must survive that phase internally. A
    /// later horizon may reuse neither an older raw-event prefix nor another artifact
    /// authority merely because the public phase name is the same.
    private var committedReadyTransaction: Transaction?

    /// After abort retirement has proven the old recorder/session queue empty, the
    /// controller supplies the exact newly-created durable target-session generation.
    /// The next Ready must belong to that exact session; reset cannot erase this bind.
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

    /// Starts the one legal next boundary transaction for this capture session.
    /// Ready may occur once. Horizon may occur once and only after ready.
    ///
    /// `processedThrough` is required for a horizon and must be the controller's
    /// exact recorder-completed queue frontier at the instant the horizon cutoff is
    /// captured. This keeps a stale horizon cutoff from moving behind evidence that
    /// the recorder already accepted while ordinary observation draining was open.
    /// It is software FIFO chronology only, not a BLE/RF timestamp or physical claim.
    ///
    /// Cross-boundary invariants are validated before allocating a transaction
    /// revision or mutating phase so rejected horizon attempts are fully atomic.
    mutating func begin(
        _ boundaryKind: BoundaryKind,
        through queueCutoff: UInt64,
        processedThrough processedQueueSequence: UInt64? = nil,
        authority: PassiveCoreBluetoothArtifactAuthorityContext
    ) throws -> Transaction {
        switch (phase, boundaryKind) {
        case (.awaitingReady, .finiteAcquisitionReady):
            if let requiredReadyTargetSessionGeneration {
                guard authority.targetSessionGeneration == requiredReadyTargetSessionGeneration else {
                    throw StateError.freshTargetSessionRequired
                }
            }

        case (.observing, .observationHorizon):
            guard let ready = committedReadyTransaction else {
                throw StateError.invalidTransition
            }
            guard authority == ready.authority else {
                throw StateError.authorityChanged
            }
            guard queueCutoff >= ready.queueCutoff else {
                throw StateError.horizonCutoffPrecedesReady
            }
            guard let processedQueueSequence else {
                throw StateError.horizonProcessedPrefixRequired
            }
            guard processedQueueSequence >= ready.queueCutoff else {
                throw StateError.processedPrefixPrecedesReady
            }
            guard queueCutoff >= processedQueueSequence else {
                throw StateError.horizonCutoffPrecedesProcessedPrefix
            }

        default:
            throw StateError.invalidTransition
        }

        guard nextRevision != UInt64.max else {
            throw StateError.transactionRevisionExhausted
        }

        let transaction = Transaction(
            boundaryKind: boundaryKind,
            queueCutoff: queueCutoff,
            authority: authority,
            revision: nextRevision
        )

        switch boundaryKind {
        case .finiteAcquisitionReady:
            requiredReadyTargetSessionGeneration = nil
            phase = .drainingReady(transaction)
        case .observationHorizon:
            phase = .drainingHorizon(transaction)
        }

        nextRevision += 1
        return transaction
    }

    /// Applies the active boundary cutoff to the controller's normal FIFO drain.
    /// Events accepted after the cutoff remain queued rather than being dropped.
    /// Once a pre-H epoch is abandoned, ordinary draining remains quarantined until
    /// the old session queue is synchronously retired and a fresh durable target
    /// session is bound. A terminal horizon likewise admits no further draining.
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

    /// Commits the lifecycle boundary only when the controller reports the exact
    /// recorder-completed queue frontier owned by this transaction. Under-drain
    /// means the cutoff is not complete; overrun means evidence already crossed the
    /// supposedly exact barrier. Neither may be retroactively blessed as a boundary.
    /// Ready releases the drain barrier immediately; horizon intentionally keeps it
    /// closed until the caller freezes the immutable artifact.
    mutating func markBoundaryRecorded(
        _ transaction: Transaction,
        lastProcessedQueueSequence: UInt64,
        currentAuthority: PassiveCoreBluetoothArtifactAuthorityContext
    ) throws {
        switch phase {
        case let .drainingReady(current):
            guard current == transaction else {
                throw StateError.staleTransaction
            }
        case let .drainingHorizon(current):
            guard current == transaction else {
                throw StateError.staleTransaction
            }
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
            // Current-transaction identity was proven above and no mutation occurs
            // between the two switches, so this is unreachable under value semantics.
            throw StateError.staleTransaction
        }
    }

    /// Seals the terminal horizon only after the exact horizon transaction has
    /// recorded its boundary and the caller has frozen the corresponding artifact.
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

    /// After terminal artifact freeze, callbacks accepted later than the horizon
    /// cutoff belong outside the immutable evidence artifact and may be discarded
    /// from this recorder generation. This says nothing about their physical/RF
    /// meaning and must not suppress transport-state handling elsewhere.
    func shouldDiscardQueuedEvidenceAfterTerminalHorizon(
        queueSequence: UInt64,
        authority: PassiveCoreBluetoothArtifactAuthorityContext
    ) -> Bool {
        guard case let .terminal(transaction) = phase,
              transaction.authority == authority else {
            return false
        }
        return queueSequence > transaction.queueCutoff
    }

    /// Abandons an already-committed Ready epoch before Horizon begins. The old
    /// recorder/session becomes incomplete evidence and normal FIFO draining is
    /// immediately quarantined. Queue retirement + fresh durable session binding
    /// are separate required steps; abort itself never reopens `.awaitingReady`.
    @discardableResult
    mutating func abortObservationEpoch(
        expectedReadyAuthority: PassiveCoreBluetoothArtifactAuthorityContext,
        expectedReadyQueueCutoff: UInt64
    ) throws -> ObservationEpochAbortReceipt {
        guard case .observing = phase else {
            throw StateError.invalidTransition
        }
        guard let committedReadyTransaction else {
            throw StateError.staleTransaction
        }
        guard committedReadyTransaction.boundaryKind == .finiteAcquisitionReady,
              committedReadyTransaction.authority == expectedReadyAuthority,
              committedReadyTransaction.queueCutoff == expectedReadyQueueCutoff else {
            throw StateError.staleTransaction
        }

        let receipt = ObservationEpochAbortReceipt(
            abandonedReadyTransaction: committedReadyTransaction,
            origin: .committedReadyInvalidated
        )
        self.committedReadyTransaction = nil
        phase = .abortQuarantined(receipt)
        return receipt
    }

    /// Abandons an uncommitted Ready transaction only after the sealed boundary
    /// producer proves its authority-fenced recorder mutation was rejected before
    /// append. A caller cannot mint that rejection receipt directly.
    ///
    /// This is intentionally distinct from committed-Ready abort above. Generic
    /// caller-asserted rollback from `.drainingReady` would be unsafe because the
    /// queue gate cannot independently know whether a Ready boundary is already
    /// durable on the recorder actor.
    @discardableResult
    mutating func abortUncommittedReady(
        after rejection: PassiveCoreBluetoothObservationBoundaryRecorderMutationRejectionReceipt
    ) throws -> ObservationEpochAbortReceipt {
        guard case let .drainingReady(current) = phase else {
            throw StateError.invalidTransition
        }
        guard rejection.queueKind == .finiteAcquisitionReady,
              current.boundaryKind == .finiteAcquisitionReady,
              current.authority == rejection.authority,
              current.queueCutoff == rejection.queueCutoff else {
            throw StateError.staleTransaction
        }

        let receipt = ObservationEpochAbortReceipt(
            abandonedReadyTransaction: current,
            origin: .uncommittedReadyRejectedBeforeRecorderMutation
        )
        committedReadyTransaction = nil
        phase = .abortQuarantined(receipt)
        return receipt
    }

    /// Reopens boundary admission only after a producer-issued pre-H queue
    /// retirement receipt proves the quarantined old target-session FIFO was fully
    /// retired while ordinary draining was stopped, the controller queue tail has
    /// not advanced since that retirement, and the controller has already created
    /// a strictly newer durable target session/recorder generation.
    ///
    /// The exact fresh target-session generation is retained until its first Ready
    /// begins, so an unrelated later session cannot silently consume this recovery.
    mutating func completeAbortedObservationRecovery(
        _ retirement: PassiveCoreBluetoothAbortedObservationQueueRetirement.Receipt,
        currentLastEnqueuedEventSequence: UInt64,
        freshTargetSessionGeneration: UInt64
    ) throws {
        guard case let .abortQuarantined(currentAbort) = phase else {
            throw StateError.abortQueueRetirementRequired
        }
        guard retirement.abortReceipt == currentAbort else {
            throw StateError.abortRetirementReceiptMismatch
        }
        guard retirement.validatedQueueTailSequence == currentLastEnqueuedEventSequence else {
            throw StateError.abortQueueTailChanged
        }
        guard retirement.retainedPendingEvidenceCount == 0 else {
            throw StateError.abortQueueRetirementRequired
        }
        guard freshTargetSessionGeneration > currentAbort.abandonedTargetSessionGeneration else {
            throw StateError.freshTargetSessionRequired
        }

        requiredReadyTargetSessionGeneration = freshTargetSessionGeneration
        phase = .awaitingReady
    }

    /// Requests a fresh lifecycle grammar only when no observation transaction has
    /// begun yet. Once Ready starts, this gate remains closed through terminal freeze
    /// unless the explicit pre-H abort -> queue-retirement -> fresh-session recovery
    /// transaction completes.
    ///
    /// `resetForNewCaptureSession()` never escapes abort quarantine and never clears
    /// the exact fresh-session generation retained after a completed abort recovery.
    /// Terminal artifact freeze likewise stays closed until its separate post-H
    /// retirement/reopen authority is accepted and integrated.
    @discardableResult
    mutating func resetForNewCaptureSession() -> Bool {
        guard phase == .awaitingReady else {
            return false
        }
        committedReadyTransaction = nil
        return true
    }
}
