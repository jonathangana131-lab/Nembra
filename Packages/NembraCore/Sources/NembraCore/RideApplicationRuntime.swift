import Dispatch
import Foundation

public enum RideApplicationRuntimeFailure: String, Equatable, Sendable {
    case processing
    case historyCommit
}

public enum RideApplicationRuntimeStartError: Error, Equatable, Sendable {
    case initialObservationFailed
}

public struct RideApplicationRuntimeSnapshot: Equatable, Sendable {
    public let phase: RideEnginePhase
    public let pendingCompletedRideID: UUID?
    public let failure: RideApplicationRuntimeFailure?

    public init(
        phase: RideEnginePhase,
        pendingCompletedRideID: UUID?,
        failure: RideApplicationRuntimeFailure?
    ) {
        self.phase = phase
        self.pendingCompletedRideID = pendingCompletedRideID
        self.failure = failure
    }

    public var isTrackingBlocked: Bool { failure != nil || pendingCompletedRideID != nil }
}

/// Application-level bridge from one scooter service into the existing ride,
/// recovery-journal and permanent-history contracts.
///
/// Vehicle state and raw speed are separate broadcasts. This actor serializes
/// them into one monotonic observation stream so two subscriber tasks cannot race
/// the ride engine. A state-only update is never interpreted as a zero-speed
/// measurement. The latest authoritative raw sample may accompany a state/ODO
/// transition and the RideEngine itself applies the injected freshness policy.
public actor RideApplicationRuntime {
    public typealias UptimeClock = @Sendable () -> UInt64
    public typealias DateClock = @Sendable () -> Date

    private let service: any ScooterService
    private let recoveryCoordinator: RideCheckpointCoordinator
    private let historyCommitCoordinator: RideHistoryCommitCoordinator
    private let uptimeClock: UptimeClock
    private let dateClock: DateClock

    private var latestVehicleState: VehicleState?
    private var latestSpeedSample: SpeedTelemetrySample?
    private var lastObservationUptimeNanoseconds: UInt64?
    private var publishedPhase: RideEnginePhase
    private var pendingCompletedRideID: UUID?
    private var failure: RideApplicationRuntimeFailure?
    private var started = false
    private var stateTask: Task<Void, Never>?
    private var speedTask: Task<Void, Never>?
    private var continuations: [UUID: AsyncStream<RideApplicationRuntimeSnapshot>.Continuation] = [:]

    private init(
        service: any ScooterService,
        recoveryCoordinator: RideCheckpointCoordinator,
        historyStore: any RideHistoryStore,
        initialPhase: RideEnginePhase,
        pendingCompletedRideID: UUID?,
        uptimeClock: @escaping UptimeClock,
        dateClock: @escaping DateClock
    ) {
        self.service = service
        self.recoveryCoordinator = recoveryCoordinator
        self.historyCommitCoordinator = RideHistoryCommitCoordinator(
            recoveryCoordinator: recoveryCoordinator,
            historyStore: historyStore
        )
        self.publishedPhase = initialPhase
        self.pendingCompletedRideID = pendingCompletedRideID
        self.uptimeClock = uptimeClock
        self.dateClock = dateClock
    }

    deinit {
        stateTask?.cancel()
        speedTask?.cancel()
    }

    public static func restoring(
        service: any ScooterService,
        detectionPolicy: RideDetectionPolicy,
        checkpointStore: any RideCheckpointStore,
        checkpointCadence: RideCheckpointCadence,
        historyStore: any RideHistoryStore,
        uptimeClock: @escaping UptimeClock = { DispatchTime.now().uptimeNanoseconds },
        dateClock: @escaping DateClock = { Date() },
        makeSessionID: @escaping @Sendable () -> UUID = { UUID() }
    ) async throws -> RideApplicationRuntime {
        let recoveredUptime = uptimeClock()
        let recoveredDate = dateClock()
        let recovery = try await RideCheckpointCoordinator.restoring(
            policy: detectionPolicy,
            store: checkpointStore,
            cadence: checkpointCadence,
            recoveredAtUptimeNanoseconds: recoveredUptime,
            recoveredAtDate: recoveredDate,
            makeSessionID: makeSessionID
        )
        let initialPhase = await recovery.currentPhase()
        let pendingID = await recovery.pendingCompletedRideEvidence()?.sessionID

        return RideApplicationRuntime(
            service: service,
            recoveryCoordinator: recovery,
            historyStore: historyStore,
            initialPhase: initialPhase,
            pendingCompletedRideID: pendingID,
            uptimeClock: uptimeClock,
            dateClock: dateClock
        )
    }

    public func updates() -> AsyncStream<RideApplicationRuntimeSnapshot> {
        let id = UUID()
        let current = makeSnapshot()
        return AsyncStream { continuation in
            continuations[id] = continuation
            continuation.yield(current)
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeContinuation(id) }
            }
        }
    }

    /// Recovery completion is flushed into permanent history before accepting any
    /// new scooter evidence. If that durable handoff fails, startup fails instead
    /// of opening a second ride while the previous one is still pending.
    public func start() async throws {
        guard !started else { return }

        if pendingCompletedRideID != nil {
            do {
                _ = try await historyCommitCoordinator.commitPendingRide()
                pendingCompletedRideID = nil
                publishedPhase = await recoveryCoordinator.currentPhase()
            } catch {
                failure = .historyCommit
                publish()
                throw error
            }
        }

        // Reconcile restored state against the scooter snapshot once before
        // subscriptions begin. This lets a recovered ride observe that the scooter
        // is already reconnected / has newer ODO evidence without waiting for an
        // unrelated later state mutation. It still carries no fabricated speed.
        latestVehicleState = nil
        await acceptVehicleState(await service.snapshot())
        guard failure == nil else {
            throw RideApplicationRuntimeStartError.initialObservationFailed
        }

        // Register both broadcast streams before start returns. Creating the
        // streams synchronously installs their continuations inside the scooter
        // service; spawning tasks first would allow the first post-launch speed
        // packets to arrive before the raw subscriber existed and silently drop
        // ride-start evidence.
        let stateStream = await service.stateUpdates()
        let speedStream = await service.speedTelemetryUpdates()

        started = true
        publish()

        stateTask = Task { [weak self] in
            for await state in stateStream {
                guard !Task.isCancelled else { break }
                await self?.acceptVehicleState(state)
            }
        }

        speedTask = Task { [weak self] in
            for await sample in speedStream {
                guard !Task.isCancelled else { break }
                await self?.acceptSpeedSample(sample)
            }
        }
    }

    public func stop() {
        stateTask?.cancel()
        speedTask?.cancel()
        stateTask = nil
        speedTask = nil
        started = false
    }

    public func snapshot() -> RideApplicationRuntimeSnapshot {
        makeSnapshot()
    }

    private func acceptVehicleState(_ state: VehicleState) async {
        guard failure == nil else { return }

        let previous = latestVehicleState
        latestVehicleState = state

        let connectionChanged = previous?.connection != state.connection
        let odometerChanged = previous?.odometerKilometers != state.odometerKilometers
        guard connectionChanged || odometerChanged else { return }

        do {
            try await ingest(
                state: state,
                speedSample: latestSpeedSample,
                preferredUptimeNanoseconds: nil
            )
        } catch {
            block(.processing)
        }
    }

    private func acceptSpeedSample(_ sample: SpeedTelemetrySample) async {
        guard failure == nil else { return }
        guard sample.isAuthoritativeMeasurement else { return }

        latestSpeedSample = sample
        let state = await service.snapshot()
        // The service publishes raw speed immediately before the matching state
        // broadcast. Cache that snapshot now so the following state event does not
        // feed the same ODO movement into the engine as a second observation.
        latestVehicleState = state

        do {
            try await ingest(
                state: state,
                speedSample: sample,
                preferredUptimeNanoseconds: sample.receivedAtUptimeNanoseconds
            )
        } catch {
            block(.processing)
        }
    }

    private func ingest(
        state: VehicleState,
        speedSample: SpeedTelemetrySample?,
        preferredUptimeNanoseconds: UInt64?
    ) async throws {
        let observationUptime = nextObservationUptime(preferred: preferredUptimeNanoseconds)
        let usableSample: SpeedTelemetrySample?
        if let speedSample,
           speedSample.isAuthoritativeMeasurement,
           speedSample.receivedAtUptimeNanoseconds <= observationUptime {
            usableSample = speedSample
        } else {
            usableSample = nil
        }

        let observation = try RideObservation(
            receivedAtUptimeNanoseconds: observationUptime,
            receivedAtDate: dateClock(),
            connection: state.connection,
            speedSample: usableSample,
            odometerKilometers: state.odometerKilometers,
            qualityScreenedGPSDistanceDeltaMeters: nil,
            motionIndicatesMovement: false
        )

        let update = try await recoveryCoordinator.ingest(observation)
        lastObservationUptimeNanoseconds = observationUptime
        publishedPhase = update.phase

        if let completed = completedEvidence(in: update.events) {
            pendingCompletedRideID = completed.sessionID
            publish()
            do {
                _ = try await historyCommitCoordinator.commitPendingRide()
                pendingCompletedRideID = nil
                publishedPhase = await recoveryCoordinator.currentPhase()
                publish()
            } catch {
                block(.historyCommit)
            }
        } else {
            publish()
        }
    }

    private func nextObservationUptime(preferred: UInt64?) -> UInt64 {
        var candidate = max(uptimeClock(), preferred ?? 0)
        if let lastObservationUptimeNanoseconds, candidate <= lastObservationUptimeNanoseconds {
            candidate = lastObservationUptimeNanoseconds == UInt64.max
                ? UInt64.max
                : lastObservationUptimeNanoseconds + 1
        }
        return candidate
    }

    private func completedEvidence(in events: [RideEngineEvent]) -> CompletedRideEvidence? {
        for event in events {
            if case let .rideEnded(evidence) = event {
                return evidence
            }
        }
        return nil
    }

    private func block(_ reason: RideApplicationRuntimeFailure) {
        failure = reason
        stateTask?.cancel()
        speedTask?.cancel()
        publish()
    }

    private func makeSnapshot() -> RideApplicationRuntimeSnapshot {
        RideApplicationRuntimeSnapshot(
            phase: publishedPhase,
            pendingCompletedRideID: pendingCompletedRideID,
            failure: failure
        )
    }

    private func publish() {
        let value = makeSnapshot()
        for continuation in continuations.values {
            continuation.yield(value)
        }
    }

    private func removeContinuation(_ id: UUID) {
        continuations[id] = nil
    }
}
