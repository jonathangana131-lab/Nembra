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
    }

    struct Transaction: Equatable, Sendable {
        let boundaryKind: BoundaryKind
        let queueCutoff: UInt64
        let authority: PassiveCoreBluetoothArtifactAuthorityContext
        let revision: UInt64
    }

    /// Producer-issued proof that one committed Ready observation epoch was
    /// intentionally abandoned before Horizon. The abandoned recorder is
    /// incomplete evidence; this receipt never upgrades it into a terminal
    /// artifact and carries no physical scooter meaning.
    struct ObservationEpochAbortReceipt: Equatable, Sendable {
        let abandonedReadyTransaction: Transaction
        let abandonedTargetSessionGeneration: UInt64

        fileprivate init(abandonedReadyTransaction: Transaction) {
            self.abandonedReadyTransaction = abandonedReadyTransaction
            abandonedTargetSessionGeneration =
                abandonedReadyTransaction.authority.targetSessionGeneration
        }
    }

    enum Phase: Equatable, Sendable {
        case awaitingReady
        case drainingReady(Transaction)
        case observing
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

    /// A pre-H abort may reopen only the lifecycle grammar, never the old
    /// durable capture session. Until a Ready transaction arrives under a
    /// strictly newer target-session generation, this fence prevents the
    /// abandoned recorder/session from earning a second Ready boundary.
    private var abandonedTargetSessionGeneration: UInt64?

    var isTerminal: Bool {
        if case .terminal = phase { return true }
        return false
    }

    var activeTransaction: Transaction? {
        switch phase {
        case let .drainingReady(transaction),
             let .drainingHorizon(transaction),
             let .horizonBoundaryRecorded(transaction):
            transaction
        case .awaitingReady, .observing, .terminal:
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
            if let abandonedTargetSessionGeneration {
                guard authority.targetSessionGeneration > abandonedTargetSessionGeneration else {
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
            abandonedTargetSessionGeneration = nil
            phase = .drainingReady(transaction)
        case .observationHorizon:
            phase = .drainingHorizon(transaction)
        }

        nextRevision += 1
        return transaction
    }

    /// Applies the active boundary cutoff to the controller's normal FIFO drain.
    /// Events accepted after the cutoff remain queued rather than being dropped.
    /// Once a terminal horizon artifact is frozen, no more evidence drains under
    /// this capture-session gate.
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
        case .terminal:
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

    /// Intentionally abandons one already-committed Ready epoch before
    /// Horizon begins. This is a recovery transition for an incomplete
    /// observation artifact, not a successful finalization path.
    ///
    /// The caller must present the exact Ready transaction that established
    /// `.observing`; stale/wrong transactions cannot reset another epoch.
    /// After abort, a later Ready is admitted only under a strictly newer
    /// `targetSessionGeneration`, mechanically requiring controller-level
    /// durable session/recorder rotation rather than reusing the abandoned
    /// recorder under a newer authority generation.
    ///
    /// The transition is deliberately unavailable during Ready drain, after
    /// Horizon begins, or after terminal freeze. Those states retain their
    /// existing fail-closed queue barriers and must be resolved by their own
    /// accepted transaction/retirement contracts.
    @discardableResult
    mutating func abortObservationEpoch(
        establishedBy readyTransaction: Transaction
    ) throws -> ObservationEpochAbortReceipt {
        guard case .observing = phase else {
            throw StateError.invalidTransition
        }
        guard let committedReadyTransaction,
              committedReadyTransaction == readyTransaction else {
            throw StateError.staleTransaction
        }
        guard readyTransaction.boundaryKind == .finiteAcquisitionReady else {
            throw StateError.staleTransaction
        }

        let receipt = ObservationEpochAbortReceipt(
            abandonedReadyTransaction: readyTransaction
        )
        abandonedTargetSessionGeneration =
            readyTransaction.authority.targetSessionGeneration
        self.committedReadyTransaction = nil
        phase = .awaitingReady
        return receipt
    }

    /// Requests a fresh lifecycle grammar only when no observation transaction has
    /// begun yet. Once Ready starts, this gate remains closed through terminal freeze.
    ///
    /// A pre-H abort is the one explicit exception: it may return the gate to
    /// `.awaitingReady`, but its fresh-target-session fence survives this no-op
    /// reset and requires a strictly newer durable target session before Ready.
    ///
    /// Terminal artifact freeze proves the immutable artifact is sealed; it does NOT
    /// prove callbacks intentionally withheld after Horizon have been retired from
    /// the controller FIFO. Reopening here would erase their terminal quarantine and
    /// make old-generation post-cut evidence drainable again. Terminal -> fresh still
    /// requires the separate controller-owned post-H retirement/reopen authority.
    @discardableResult
    mutating func resetForNewCaptureSession() -> Bool {
        guard phase == .awaitingReady else {
            return false
        }
        committedReadyTransaction = nil
        return true
    }
}
