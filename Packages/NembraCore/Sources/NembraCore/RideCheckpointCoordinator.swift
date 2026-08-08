import Foundation

public enum RideCheckpointCoordinatorError: Error, Equatable, Sendable {
    case invalidCadence
    case completedRideAwaitingCommit(UUID)
    case noMatchingPendingCompletion
}

/// Controls how often a confirmed ride refreshes its durable recovery journal.
/// There is deliberately no production default until device write-cost and ride
/// recovery requirements are measured on iPhone hardware.
public struct RideCheckpointCadence: Equatable, Sendable {
    public let minimumIntervalNanoseconds: UInt64

    public init(minimumIntervalNanoseconds: UInt64) throws {
        guard minimumIntervalNanoseconds > 0 else {
            throw RideCheckpointCoordinatorError.invalidCadence
        }
        self.minimumIntervalNanoseconds = minimumIntervalNanoseconds
    }
}

/// Serializes ride-state mutation with durable checkpoint writes.
///
/// Significant confirmed-ride transitions are journaled immediately. Stable
/// in-progress updates are journaled at the injected cadence, avoiding a disk
/// transaction per telemetry frame. A ride-end event is first persisted as
/// `completedPendingCommit`; only the future completed-ride ledger may acknowledge
/// that handoff and clear the recovery journal.
public actor RideCheckpointCoordinator {
    private enum MutationPermitOutcome: Sendable {
        case admitted
        case cancelled
    }

    private struct MutationWaiter {
        let id: UUID
        let continuation: CheckedContinuation<MutationPermitOutcome, Never>
    }

    private var engine: RideEngine
    private let store: any RideCheckpointStore
    private let cadence: RideCheckpointCadence
    private var lastSuccessfulCheckpointUptimeNanoseconds: UInt64?
    private var pendingCompletedRide: CompletedRideEvidence?

    // Swift actors are reentrant at `await`. A durable save/clear therefore needs
    // a separate transaction boundary so a later mutation cannot stage from an
    // older engine/pending-completion snapshot while the first write is suspended.
    // Read-only accessors intentionally remain outside this permit and expose only
    // already-committed actor state.
    private var mutationInFlight = false
    private var mutationWaiters: [MutationWaiter] = []

    public init(
        engine: RideEngine,
        store: any RideCheckpointStore,
        cadence: RideCheckpointCadence
    ) {
        self.engine = engine
        self.store = store
        self.cadence = cadence
    }

    private init(
        engine: RideEngine,
        store: any RideCheckpointStore,
        cadence: RideCheckpointCadence,
        lastSuccessfulCheckpointUptimeNanoseconds: UInt64?,
        pendingCompletedRide: CompletedRideEvidence?
    ) {
        self.engine = engine
        self.store = store
        self.cadence = cadence
        self.lastSuccessfulCheckpointUptimeNanoseconds = lastSuccessfulCheckpointUptimeNanoseconds
        self.pendingCompletedRide = pendingCompletedRide
    }

    /// Reconstructs the coordinator from the newest durable journal generation.
    /// In-progress rides are re-anchored to the new process uptime and return as
    /// temporarily disconnected. A completed-pending record blocks new ride input
    /// until the history layer durably commits it and acknowledges the handoff.
    public static func restoring(
        policy: RideDetectionPolicy,
        store: any RideCheckpointStore,
        cadence: RideCheckpointCadence,
        recoveredAtUptimeNanoseconds: UInt64,
        recoveredAtDate: Date,
        makeSessionID: @escaping @Sendable () -> UUID = { UUID() }
    ) async throws -> RideCheckpointCoordinator {
        switch try await store.load() {
        case nil:
            return RideCheckpointCoordinator(
                engine: RideEngine(policy: policy, makeSessionID: makeSessionID),
                store: store,
                cadence: cadence,
                lastSuccessfulCheckpointUptimeNanoseconds: nil,
                pendingCompletedRide: nil
            )

        case let .inProgress(checkpoint):
            return RideCheckpointCoordinator(
                engine: try RideEngine.restoring(
                    from: checkpoint,
                    policy: policy,
                    recoveredAtUptimeNanoseconds: recoveredAtUptimeNanoseconds,
                    recoveredAtDate: recoveredAtDate,
                    makeSessionID: makeSessionID
                ),
                store: store,
                cadence: cadence,
                lastSuccessfulCheckpointUptimeNanoseconds: recoveredAtUptimeNanoseconds,
                pendingCompletedRide: nil
            )

        case let .completedPendingCommit(evidence):
            return RideCheckpointCoordinator(
                engine: RideEngine(policy: policy, makeSessionID: makeSessionID),
                store: store,
                cadence: cadence,
                lastSuccessfulCheckpointUptimeNanoseconds: nil,
                pendingCompletedRide: evidence
            )
        }
    }

    public func ingest(_ observation: RideObservation) async throws -> RideEngineUpdate {
        try await acquireMutationPermit()
        defer { releaseMutationPermit() }

        if let pendingCompletedRide {
            throw RideCheckpointCoordinatorError.completedRideAwaitingCommit(pendingCompletedRide.sessionID)
        }

        // Work on a copy. If a required durable write fails, the in-memory engine
        // remains at its prior state and the same observation can be retried.
        var nextEngine = engine
        let update = try nextEngine.ingest(observation)

        if let completed = update.completedRideEvidence {
            try await store.save(.completedPendingCommit(completed))
            engine = nextEngine
            pendingCompletedRide = completed
            lastSuccessfulCheckpointUptimeNanoseconds = observation.receivedAtUptimeNanoseconds
            return update
        }

        if let checkpoint = try nextEngine.recoveryCheckpoint(
            checkpointedAtDate: observation.receivedAtDate
        ), shouldPersistInProgress(update: update, observation: observation) {
            try await store.save(.inProgress(checkpoint))
            lastSuccessfulCheckpointUptimeNanoseconds = observation.receivedAtUptimeNanoseconds
        }

        engine = nextEngine
        return update
    }

    public func currentPhase() -> RideEnginePhase {
        engine.phase
    }

    public func pendingCompletedRideEvidence() -> CompletedRideEvidence? {
        pendingCompletedRide
    }

    /// Called only after the completed-ride ledger has durably committed the same
    /// session. Clearing first would reopen the exact crash-loss window this layer
    /// exists to close.
    public func acknowledgeCompletedRideCommitted(sessionID: UUID) async throws {
        try await acquireMutationPermit()
        defer { releaseMutationPermit() }

        guard pendingCompletedRide?.sessionID == sessionID else {
            throw RideCheckpointCoordinatorError.noMatchingPendingCompletion
        }
        try await store.clear()
        pendingCompletedRide = nil
        lastSuccessfulCheckpointUptimeNanoseconds = nil
    }

    /// Acquires one FIFO mutation transaction permit across external store awaits.
    ///
    /// Cancellation before admission removes/drops the queued mutation. Once the
    /// permit has been transferred, cancellation no longer pretends a durable
    /// transaction can be rolled back: a cancellation racing with handoff releases
    /// the transferred permit before throwing; cancellation after this method
    /// returns is past the admission boundary and the mutation completes normally.
    private func acquireMutationPermit() async throws {
        try Task.checkCancellation()

        guard mutationInFlight else {
            mutationInFlight = true
            return
        }

        let waiterID = UUID()
        let outcome: MutationPermitOutcome = await withTaskCancellationHandler {
            await withCheckedContinuation {
                (continuation: CheckedContinuation<MutationPermitOutcome, Never>) in
                if Task.isCancelled {
                    continuation.resume(returning: .cancelled)
                    return
                }
                mutationWaiters.append(
                    MutationWaiter(id: waiterID, continuation: continuation)
                )
            }
        } onCancel: {
            Task {
                await self.cancelMutationWaiter(id: waiterID)
            }
        }

        switch outcome {
        case .cancelled:
            throw CancellationError()
        case .admitted:
            do {
                try Task.checkCancellation()
            } catch {
                // `releaseMutationPermit()` already transferred ownership to this
                // waiter. Cancellation that raced with that handoff must return the
                // permit before propagating or the FIFO would remain locked forever.
                releaseMutationPermit()
                throw error
            }
        }
    }

    private func cancelMutationWaiter(id: UUID) {
        guard let index = mutationWaiters.firstIndex(where: { $0.id == id }) else {
            // Release may already have admitted this waiter. The resumed task's
            // post-handoff cancellation check owns the corresponding permit return.
            return
        }
        let waiter = mutationWaiters.remove(at: index)
        waiter.continuation.resume(returning: .cancelled)
    }

    private func releaseMutationPermit() {
        guard !mutationWaiters.isEmpty else {
            mutationInFlight = false
            return
        }

        // Ownership transfers directly; `mutationInFlight` intentionally remains
        // true so a later caller cannot overtake this FIFO waiter.
        let next = mutationWaiters.removeFirst()
        next.continuation.resume(returning: .admitted)
    }

    private func shouldPersistInProgress(
        update: RideEngineUpdate,
        observation: RideObservation
    ) -> Bool {
        if update.events.containsConfirmedRideTransition {
            return true
        }
        guard let lastSuccessfulCheckpointUptimeNanoseconds else {
            return true
        }
        return observation.receivedAtUptimeNanoseconds - lastSuccessfulCheckpointUptimeNanoseconds
            >= cadence.minimumIntervalNanoseconds
    }
}

private extension RideEngineUpdate {
    var completedRideEvidence: CompletedRideEvidence? {
        for event in events {
            if case let .rideEnded(evidence) = event {
                return evidence
            }
        }
        return nil
    }
}

private extension Array where Element == RideEngineEvent {
    var containsConfirmedRideTransition: Bool {
        contains { event in
            switch event {
            case .rideStarted,
                 .rideTemporarilyDisconnected,
                 .rideResumed,
                 .endingCandidateStarted:
                return true
            case .candidateStarted,
                 .candidateCancelled,
                 .rideEnded:
                return false
            }
        }
    }
}
