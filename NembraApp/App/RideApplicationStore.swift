import Dispatch
import Foundation
import Observation

struct RideApplicationConfiguration: Sendable {
    let detectionPolicy: RideDetectionPolicy
    let checkpointCadence: RideCheckpointCadence

    /// Explicit Simulator QA policy only. These thresholds exist so the real
    /// application/recovery path can be exercised deterministically; they are
    /// not AOVOPRO ES80 hardware timing or speed claims.
    static func simulatorQA() throws -> RideApplicationConfiguration {
        RideApplicationConfiguration(
            detectionPolicy: try RideDetectionPolicy(
                candidateSpeedKilometersPerHour: 1,
                confirmationSpeedKilometersPerHour: 3,
                confirmationDurationNanoseconds: 0,
                confirmationOdometerDeltaKilometers: 0.001,
                confirmationGPSDistanceMeters: 1,
                endingDurationNanoseconds: 450_000_000,
                maximumSpeedSampleAgeNanoseconds: 750_000_000
            ),
            checkpointCadence: try RideCheckpointCadence(
                minimumIntervalNanoseconds: 500_000_000
            )
        )
    }
}

enum RideApplicationStatus: Equatable, Sendable {
    case disabled
    case restoring
    case idle
    case candidate
    case active
    case temporarilyDisconnected
    case endingCandidate
    case saving
    case persistenceUnavailable
    case failed
}

/// Root-lifetime session boundary for subsystems that must follow the exact ride
/// identity rather than a SwiftUI screen. Disconnect/ending phases deliberately
/// retain the same session and therefore do not manufacture stop/start events.
enum RideApplicationSessionEvent: Equatable, Sendable {
    case becameActive(UUID)
    case ended(UUID)
}

/// Root-owned application bridge from scooter evidence into the already-tested
/// ride engine, crash-recovery journal, and completed-history handoff.
///
/// This object intentionally outlives SwiftUI screens. It never promotes the
/// cached `VehicleState.speedKilometersPerHour` into fresh ride evidence. A raw
/// authoritative speed packet is consumed at most once. If the independent
/// state stream is still catching up through connecting/reconnecting, only the
/// newest unconsumed packet is held briefly and freshness remains enforced by
/// `RideEngine` when the connected state arrives.
@MainActor
@Observable
final class RideApplicationStore {
    typealias RideCompletionBarrier = @MainActor @Sendable (_ sessionID: UUID) async -> Void

    private let service: any ScooterService
    private let configuration: RideApplicationConfiguration?
    private let checkpointStore: (any RideCheckpointStore)?
    private let historyStore: (any RideHistoryStore)?
    private let startupPersistenceError: String?

    private(set) var status: RideApplicationStatus
    private(set) var activeSessionID: UUID?
    private(set) var continuity: RideSessionContinuity?
    private(set) var lastCompletedSessionID: UUID?
    private(set) var lastErrorMessage: String?

    @ObservationIgnored private var coordinator: RideCheckpointCoordinator?
    @ObservationIgnored private var stateTask: Task<Void, Never>?
    @ObservationIgnored private var speedTask: Task<Void, Never>?
    @ObservationIgnored private var sessionEventContinuation: AsyncStream<RideApplicationSessionEvent>.Continuation?
    @ObservationIgnored private var rideCompletionBarrier: RideCompletionBarrier?
    @ObservationIgnored private var didStart = false
    @ObservationIgnored private var latestVehicleState: VehicleState
    @ObservationIgnored private var pendingAuthoritativeSpeedSample: SpeedTelemetrySample?
    @ObservationIgnored private var lastObservationUptimeNanoseconds: UInt64?

    init(
        service: any ScooterService,
        initialState: VehicleState,
        configuration: RideApplicationConfiguration?,
        checkpointStore: (any RideCheckpointStore)?,
        historyStore: (any RideHistoryStore)?,
        startupPersistenceError: String? = nil
    ) {
        self.service = service
        self.configuration = configuration
        self.checkpointStore = checkpointStore
        self.historyStore = historyStore
        self.startupPersistenceError = startupPersistenceError
        self.latestVehicleState = initialState
        self.status = configuration == nil ? .disabled : .restoring
        self.lastErrorMessage = startupPersistenceError
    }

    deinit {
        stateTask?.cancel()
        speedTask?.cancel()
        sessionEventContinuation?.finish()
    }

    var shouldPresentStatus: Bool {
        switch status {
        case .disabled, .idle:
            false
        case .restoring, .candidate, .active, .temporarilyDisconnected,
             .endingCandidate, .saving, .persistenceUnavailable, .failed:
            true
        }
    }

    var statusText: String {
        switch status {
        case .disabled:
            "Automatic ride tracking unavailable"
        case .restoring:
            "Restoring ride"
        case .idle:
            "Ready"
        case .candidate:
            "Detecting ride"
        case .active:
            continuity == .recoveredCheckpoint ? "Ride resumed" : "Riding automatically"
        case .temporarilyDisconnected:
            "Ride protected during reconnect"
        case .endingCandidate:
            "Checking ride end"
        case .saving:
            "Saving ride"
        case .persistenceUnavailable:
            "Ride tracking unavailable"
        case .failed:
            "Ride tracking needs attention"
        }
    }

    /// One root-level lifecycle stream. Replacing the consumer closes the older
    /// stream; AppRuntime is the intended owner. If a ride was restored before
    /// the consumer attaches, its current UUID is replayed once so location
    /// capture can join the durable session without polling published state.
    func rideSessionEvents() -> AsyncStream<RideApplicationSessionEvent> {
        sessionEventContinuation?.finish()
        let pair = AsyncStream<RideApplicationSessionEvent>.makeStream()
        sessionEventContinuation = pair.continuation
        if let activeSessionID {
            pair.continuation.yield(.becameActive(activeSessionID))
        }
        return pair.stream
    }

    /// Installs an application/root-owned barrier for additive ride-scoped work
    /// that must be finalized before the completed ride is committed/published.
    /// Production currently leaves this nil until a legitimate location policy
    /// and lifecycle are enabled; the Simulator QA runtime uses it for route
    /// manifest finalization only.
    func setRideCompletionBarrier(_ barrier: RideCompletionBarrier?) {
        rideCompletionBarrier = barrier
    }

    func start() async {
        guard !didStart else { return }
        didStart = true

        guard let configuration else {
            setStatus(.disabled)
            return
        }
        guard startupPersistenceError == nil,
              let checkpointStore,
              let historyStore else {
            setStatus(.persistenceUnavailable)
            if lastErrorMessage == nil {
                lastErrorMessage = "Local ride recovery storage could not be opened."
            }
            return
        }

        setStatus(.restoring)
        let recoveredAtUptimeNanoseconds = DispatchTime.now().uptimeNanoseconds
        let recoveredAtDate = Date.now

        do {
            let restored = try await RideCheckpointCoordinator.restoring(
                policy: configuration.detectionPolicy,
                store: checkpointStore,
                cadence: configuration.checkpointCadence,
                recoveredAtUptimeNanoseconds: recoveredAtUptimeNanoseconds,
                recoveredAtDate: recoveredAtDate
            )
            coordinator = restored
            lastObservationUptimeNanoseconds = recoveredAtUptimeNanoseconds

            if await restored.pendingCompletedRideEvidence() != nil {
                try await commitPendingRide(using: restored, historyStore: historyStore)
            }

            updatePublishedState(from: await restored.currentPhase())
            await subscribeToEvidenceStreams()
        } catch {
            fail(error, persistence: true)
        }
    }

    func stop() {
        stateTask?.cancel()
        speedTask?.cancel()
        stateTask = nil
        speedTask = nil
        pendingAuthoritativeSpeedSample = nil
        sessionEventContinuation?.finish()
        sessionEventContinuation = nil
        rideCompletionBarrier = nil
    }

    /// Candidate-level/internal entry for already screened GPS evidence. This is
    /// intentionally not the production ride-location lifecycle API because an
    /// unscoped delayed delta could otherwise be assigned to a later ride.
    func ingestQualityScreenedGPSDistanceDelta(
        _ meters: Double,
        receivedAtUptimeNanoseconds: UInt64
    ) async {
        await ingestObservation(
            speedSample: nil,
            qualityScreenedGPSDistanceDeltaMeters: meters,
            minimumUptimeNanoseconds: receivedAtUptimeNanoseconds
        )
    }

    /// Ride-scoped GPS evidence entry used by the phone-location capture path.
    /// The capture owns the UUID it began with. If that ride has ended or a new
    /// ride has taken over, a late coordinate delta is dropped instead of being
    /// allowed to seed movement for the wrong `RideEngine` session.
    func ingestQualityScreenedGPSDistanceDelta(
        _ meters: Double,
        receivedAtUptimeNanoseconds: UInt64,
        for sessionID: UUID
    ) async {
        guard activeSessionID == sessionID else { return }
        await ingestQualityScreenedGPSDistanceDelta(
            meters,
            receivedAtUptimeNanoseconds: receivedAtUptimeNanoseconds
        )
    }

    private func subscribeToEvidenceStreams() async {
        guard stateTask == nil, speedTask == nil else { return }

        // Resolve both actor-backed streams before start() returns. AsyncStream
        // then buffers any evidence emitted before the consumer Tasks receive
        // their first scheduling slice, eliminating launch-order packet loss.
        let stateStream = await service.stateUpdates()
        let speedStream = await service.speedTelemetryUpdates()

        stateTask = Task { [weak self] in
            for await state in stateStream {
                guard !Task.isCancelled else { break }
                await self?.receiveVehicleState(state)
            }
        }

        speedTask = Task { [weak self] in
            for await sample in speedStream {
                guard !Task.isCancelled else { break }
                await self?.receiveSpeedSample(sample)
            }
        }
    }

    private func receiveVehicleState(_ state: VehicleState) async {
        let previousState = latestVehicleState
        latestVehicleState = state

        if state.connection == .disconnected {
            // A packet that never reached a confirmed connected state is not
            // allowed to survive into some later connection generation.
            pendingAuthoritativeSpeedSample = nil
        }

        let connectionChanged = state.connection != previousState.connection
        let odometerAdvanced: Bool
        if let previousOdometer = previousState.odometerKilometers,
           let currentOdometer = state.odometerKilometers {
            odometerAdvanced = currentOdometer > previousOdometer
        } else {
            odometerAdvanced = false
        }

        // State and raw-speed streams are independent actor streams. A fresh
        // packet can legitimately be consumed by this MainActor before the
        // connected state publication. Use the newest packet exactly once when
        // that connected state catches up; RideEngine still rejects it if stale.
        if state.connection == .connected,
           let pendingAuthoritativeSpeedSample {
            self.pendingAuthoritativeSpeedSample = nil
            await ingestObservation(speedSample: pendingAuthoritativeSpeedSample)
            return
        }

        // State publications are useful ride evidence only when they carry a
        // transport transition or a real odometer advance. Mode/light/lock UI
        // acknowledgements must not masquerade as a fresh zero-speed sample.
        guard connectionChanged || odometerAdvanced else { return }
        await ingestObservation(speedSample: nil)
    }

    private func receiveSpeedSample(_ sample: SpeedTelemetrySample) async {
        guard sample.isAuthoritativeMeasurement else { return }

        switch latestVehicleState.connection {
        case .connected:
            await ingestObservation(speedSample: sample)
        case .connecting, .reconnecting:
            // Keep only the newest unconsumed packet. Dropping an older packet
            // is safer than replaying or assigning it to an unconfirmed link;
            // this application bridge is not the raw telemetry benchmark log.
            pendingAuthoritativeSpeedSample = sample
        case .disconnected:
            pendingAuthoritativeSpeedSample = nil
        }
    }

    private func ingestObservation(
        speedSample: SpeedTelemetrySample?,
        qualityScreenedGPSDistanceDeltaMeters: Double? = nil,
        minimumUptimeNanoseconds: UInt64 = 0
    ) async {
        guard let coordinator,
              let historyStore,
              configuration != nil else { return }

        let minimumUptime = max(
            speedSample?.receivedAtUptimeNanoseconds ?? 0,
            minimumUptimeNanoseconds
        )
        guard let observationUptime = nextObservationUptime(minimum: minimumUptime) else {
            fail(RideEngineError.nonMonotonicObservation, persistence: false)
            return
        }

        do {
            let observation = try RideObservation(
                receivedAtUptimeNanoseconds: observationUptime,
                receivedAtDate: .now,
                connection: latestVehicleState.connection,
                speedSample: speedSample,
                odometerKilometers: latestVehicleState.odometerKilometers,
                qualityScreenedGPSDistanceDeltaMeters: qualityScreenedGPSDistanceDeltaMeters,
                motionIndicatesMovement: false
            )
            let update = try await coordinator.ingest(observation)
            let completedSessionID = update.events.compactMap { event -> UUID? in
                guard case let .rideEnded(evidence) = event else { return nil }
                return evidence.sessionID
            }.first

            // Keep the durable session identity valid until additive ride-scoped
            // capture has flushed/finalized. This prevents a completed-history UI
            // refresh from racing ahead of its route manifest, and it lets any
            // already-buffered screened GPS evidence retain the correct UUID.
            if let completedSessionID {
                await rideCompletionBarrier?(completedSessionID)
            }

            updatePublishedState(from: update.phase)

            if let completedSessionID {
                setStatus(.saving)
                try await commitPendingRide(using: coordinator, historyStore: historyStore)
                if lastCompletedSessionID != completedSessionID {
                    lastCompletedSessionID = completedSessionID
                }
                updatePublishedState(from: await coordinator.currentPhase())
            }
        } catch RideCheckpointCoordinatorError.completedRideAwaitingCommit(_) {
            do {
                setStatus(.saving)
                try await commitPendingRide(using: coordinator, historyStore: historyStore)
                updatePublishedState(from: await coordinator.currentPhase())
            } catch {
                fail(error, persistence: true)
            }
        } catch {
            fail(error, persistence: false)
        }
    }

    private func commitPendingRide(
        using coordinator: RideCheckpointCoordinator,
        historyStore: any RideHistoryStore
    ) async throws {
        setStatus(.saving)
        let pendingID = await coordinator.pendingCompletedRideEvidence()?.sessionID
        let commitCoordinator = RideHistoryCommitCoordinator(
            recoveryCoordinator: coordinator,
            historyStore: historyStore
        )
        _ = try await commitCoordinator.commitPendingRide()
        if let pendingID, lastCompletedSessionID != pendingID {
            lastCompletedSessionID = pendingID
        }
    }

    private func updatePublishedState(from phase: RideEnginePhase) {
        if lastErrorMessage != nil {
            lastErrorMessage = nil
        }

        switch phase {
        case .idle:
            applyPublishedState(status: .idle, sessionID: nil, continuity: nil)
        case .candidate:
            applyPublishedState(status: .candidate, sessionID: nil, continuity: nil)
        case let .active(session):
            applyPublishedState(
                status: .active,
                sessionID: session.id,
                continuity: session.continuity
            )
        case let .temporarilyDisconnected(disconnected):
            applyPublishedState(
                status: .temporarilyDisconnected,
                sessionID: disconnected.session.id,
                continuity: disconnected.session.continuity
            )
        case let .endingCandidate(ending):
            applyPublishedState(
                status: .endingCandidate,
                sessionID: ending.session.id,
                continuity: ending.session.continuity
            )
        }
    }

    private func applyPublishedState(
        status newStatus: RideApplicationStatus,
        sessionID newSessionID: UUID?,
        continuity newContinuity: RideSessionContinuity?
    ) {
        let previousSessionID = activeSessionID
        if previousSessionID != newSessionID {
            if let previousSessionID {
                sessionEventContinuation?.yield(.ended(previousSessionID))
            }
            activeSessionID = newSessionID
            if let newSessionID {
                sessionEventContinuation?.yield(.becameActive(newSessionID))
            }
        }
        if continuity != newContinuity {
            continuity = newContinuity
        }
        setStatus(newStatus)
    }

    private func setStatus(_ newStatus: RideApplicationStatus) {
        if status != newStatus {
            status = newStatus
        }
    }

    private func nextObservationUptime(minimum: UInt64) -> UInt64? {
        var candidate = max(DispatchTime.now().uptimeNanoseconds, minimum)
        if let lastObservationUptimeNanoseconds,
           candidate <= lastObservationUptimeNanoseconds {
            guard lastObservationUptimeNanoseconds < UInt64.max else { return nil }
            candidate = lastObservationUptimeNanoseconds + 1
        }
        lastObservationUptimeNanoseconds = candidate
        return candidate
    }

    private func fail(_ error: Error, persistence: Bool) {
        let newStatus: RideApplicationStatus = persistence ? .persistenceUnavailable : .failed
        let message = "\(error)"
        if lastErrorMessage != message {
            lastErrorMessage = message
        }
        setStatus(newStatus)
    }
}