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
        case horizonCutoffPrecedesReady
        case cutoffNotDrained
        case horizonArtifactNotReady
    }

    struct Transaction: Equatable, Sendable {
        let boundaryKind: BoundaryKind
        let queueCutoff: UInt64
        let authority: PassiveCoreBluetoothArtifactAuthorityContext
        let revision: UInt64
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
    /// Cross-boundary invariants are validated before allocating a transaction
    /// revision or mutating phase so rejected horizon attempts are fully atomic.
    mutating func begin(
        _ boundaryKind: BoundaryKind,
        through queueCutoff: UInt64,
        authority: PassiveCoreBluetoothArtifactAuthorityContext
    ) throws -> Transaction {
        switch (phase, boundaryKind) {
        case (.awaitingReady, .finiteAcquisitionReady):
            break

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

    /// Commits the lifecycle boundary only after every queued event through the
    /// transaction cutoff has finished its recorder hop under the same authority.
    /// Ready releases the drain barrier immediately; horizon intentionally keeps
    /// it closed until the caller freezes the immutable artifact.
    mutating func markBoundaryRecorded(
        _ transaction: Transaction,
        lastProcessedQueueSequence: UInt64,
        currentAuthority: PassiveCoreBluetoothArtifactAuthorityContext
    ) throws {
        guard transaction.authority == currentAuthority else {
            throw StateError.authorityChanged
        }
        guard lastProcessedQueueSequence >= transaction.queueCutoff else {
            throw StateError.cutoffNotDrained
        }

        switch phase {
        case let .drainingReady(current) where current == transaction:
            committedReadyTransaction = transaction
            phase = .observing
        case let .drainingHorizon(current) where current == transaction:
            phase = .horizonBoundaryRecorded(transaction)
        default:
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

    /// Requests a fresh lifecycle grammar after the previous capture has either not
    /// started its ready transaction or has reached terminal immutable-artifact freeze.
    ///
    /// An unresolved ready/horizon transaction must never lose its cutoff merely
    /// because another capture session is being prepared. Likewise, `.observing`
    /// retains the committed ready authority until a terminal horizon is established.
    /// A future explicit abort/detach contract may add another authorized reset path;
    /// absent that authority, refusing the reset is the fail-closed behavior.
    @discardableResult
    mutating func resetForNewCaptureSession() -> Bool {
        switch phase {
        case .awaitingReady:
            committedReadyTransaction = nil
            return true

        case .terminal:
            committedReadyTransaction = nil
            phase = .awaitingReady
            return true

        case .drainingReady, .observing, .drainingHorizon, .horizonBoundaryRecorded:
            return false
        }
    }
}
