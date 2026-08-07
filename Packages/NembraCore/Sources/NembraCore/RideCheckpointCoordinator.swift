import Foundation

public enum RideCheckpointCoordinatorError: Error, Equatable, Sendable {
    case invalidCadence
    case completedRideAwaitingCommit(UUID)
    case noMatchingPendingCompletion
}

/// Durable provenance describing what Nembra can truthfully say about scooter
/// transport continuity during one confirmed ride.
///
/// This is intentionally tri-state. It records observed non-connected vehicle
/// transport states and known observation-coverage loss; it never claims that
/// Bluetooth was continuously healthy merely because no gap state was received.
public enum RideTransportGapEvidence: String, Codable, Equatable, Sendable {
    /// Nembra cannot classify the whole ride's transport-gap history because
    /// required provenance is legacy/missing or a known process interval was
    /// not observed.
    case unknown

    /// Among vehicle transport states Nembra actually received for this
    /// uninterrupted current-process ride, every post-confirmation state was
    /// `.connected`; no `.disconnected`, `.connecting`, or `.reconnecting` state
    /// was observed. This does not assert packet cadence or complete Bluetooth
    /// notification/state-observation coverage.
    case noneObserved

    /// At least one post-confirmation vehicle transport state was observed while
    /// it was not `.connected` (`.disconnected`, `.connecting`, or
    /// `.reconnecting`). Once observed, this evidence is never downgraded.
    case observed

    /// Process recovery itself is not a vehicle transport-state observation.
    /// However, an unobserved process interval means a previous `noneObserved`
    /// classification can no longer cover the whole ride. Direct evidence stays.
    var afterProcessRecovery: RideTransportGapEvidence {
        switch self {
        case .observed:
            return .observed
        case .noneObserved, .unknown:
            return .unknown
        }
    }
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
    private var engine: RideEngine
    private let store: any RideCheckpointStore
    private let cadence: RideCheckpointCadence
    private var lastSuccessfulCheckpointUptimeNanoseconds: UInt64?
    private var pendingCompletedRide: CompletedRideEvidence?

    /// Actors are reentrant at `await`. Checkpoint writes therefore need an
    /// explicit transaction permit so a second ingest cannot stage from the old
    /// engine while the first ingest is waiting for durable storage. The permit
    /// is handed directly to the next FIFO waiter and remains held across the
    /// external store await; read-only actor methods may still observe the last
    /// fully committed state while a write transaction is pending.
    private var mutationInFlight = false
    private var mutationWaiters: [CheckedContinuation<Void, Never>] = []

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
    /// In-progress rides are re-anchored to fresh observation uptime and return as
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
        await acquireMutationPermit()
        defer { releaseMutationPermit() }

        if let pendingCompletedRide {
            throw RideCheckpointCoordinatorError.completedRideAwaitingCommit(pendingCompletedRide.sessionID)
        }

        // Work on a copy. If a required durable write fails, the in-memory engine
        // remains at its prior state and the same observation can be retried.
        // Snapshot the prior durable transport classification before mutation so
        // newly direct gap evidence can force a write even when the ride phase is
        // already `temporarilyDisconnected` after process recovery.
        let priorTransportGapEvidence = try engine.recoveryCheckpoint(
            checkpointedAtDate: observation.receivedAtDate
        )?.transportGapEvidence

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
        ) {
            let transportGapEvidenceBecameObserved = priorTransportGapEvidence != .observed
                && checkpoint.transportGapEvidence == .observed

            if shouldPersistInProgress(
                update: update,
                observation: observation,
                transportGapEvidenceBecameObserved: transportGapEvidenceBecameObserved
            ) {
                try await store.save(.inProgress(checkpoint))
                lastSuccessfulCheckpointUptimeNanoseconds = observation.receivedAtUptimeNanoseconds
            }
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
    /// exists to close. This mutation shares the same transaction permit as ingest
    /// so a newly arriving observation cannot race the journal clear.
    public func acknowledgeCompletedRideCommitted(sessionID: UUID) async throws {
        await acquireMutationPermit()
        defer { releaseMutationPermit() }

        guard pendingCompletedRide?.sessionID == sessionID else {
            throw RideCheckpointCoordinatorError.noMatchingPendingCompletion
        }
        try await store.clear()
        pendingCompletedRide = nil
        lastSuccessfulCheckpointUptimeNanoseconds = nil
    }

    private func shouldPersistInProgress(
        update: RideEngineUpdate,
        observation: RideObservation,
        transportGapEvidenceBecameObserved: Bool
    ) -> Bool {
        if transportGapEvidenceBecameObserved || update.events.containsConfirmedRideTransition {
            return true
        }
        guard let lastSuccessfulCheckpointUptimeNanoseconds else {
            return true
        }
        return observation.receivedAtUptimeNanoseconds - lastSuccessfulCheckpointUptimeNanoseconds
            >= cadence.minimumIntervalNanoseconds
    }

    private func acquireMutationPermit() async {
        guard mutationInFlight else {
            mutationInFlight = true
            return
        }

        await withCheckedContinuation { continuation in
            mutationWaiters.append(continuation)
        }
    }

    private func releaseMutationPermit() {
        guard !mutationWaiters.isEmpty else {
            mutationInFlight = false
            return
        }

        let next = mutationWaiters.removeFirst()
        // Keep `mutationInFlight` true: ownership transfers directly to the
        // resumed waiter rather than opening a race window for a later caller.
        next.resume()
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
