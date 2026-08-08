import NembraCore

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
struct PassiveCoreBluetoothObservationBoundaryQueueGate: Equatable, Sendable {
    enum StateError: Error, Equatable, Sendable {
        case invalidTransition
        case transactionRevisionExhausted
        case staleTransaction
        case authorityChanged
        case cutoffNotDrained
        case horizonArtifactNotReady
    }

    struct Transaction: Equatable, Sendable {
        let boundaryKind: PassiveBluetoothObservationBoundaryKind
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
    mutating func begin(
        _ boundaryKind: PassiveBluetoothObservationBoundaryKind,
        through queueCutoff: UInt64,
        authority: PassiveCoreBluetoothArtifactAuthorityContext
    ) throws -> Transaction {
        guard nextRevision != UInt64.max else {
            throw StateError.transactionRevisionExhausted
        }

        let transaction = Transaction(
            boundaryKind: boundaryKind,
            queueCutoff: queueCutoff,
            authority: authority,
            revision: nextRevision
        )

        switch (phase, boundaryKind) {
        case (.awaitingReady, .finiteAcquisitionReady):
            phase = .drainingReady(transaction)
        case (.observing, .observationHorizon):
            phase = .drainingHorizon(transaction)
        default:
            throw StateError.invalidTransition
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
        case .drainingReady(transaction):
            self.phase = .observing
        case .drainingHorizon(transaction):
            self.phase = .horizonBoundaryRecorded(transaction)
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
        guard case .horizonBoundaryRecorded(transaction) = phase else {
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

    /// A fresh durable target session receives a fresh lifecycle grammar. This is
    /// an explicit controller action; terminal evidence never silently reopens.
    mutating func resetForNewCaptureSession() {
        phase = .awaitingReady
    }
}
