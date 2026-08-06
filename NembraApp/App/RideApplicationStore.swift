import Dispatch
import Foundation
import Observation

struct RideApplicationConfiguration: Sendable {
    let detectionPolicy: RideDetectionPolicy
    let checkpointCadence: RideCheckpointCadence

    /// Explicit Simulator QA policy only. These thresholds exist so the real
    /// application/recovery path can be exercised deterministically; they are
    /// not MAXSHOT hardware timing or speed claims.
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

/// Root-owned application bridge from scooter evidence into the already-tested
/// ride engine, crash-recovery journal, and completed-history handoff.
///
/// This object intentionally outlives SwiftUI screens. It never promotes the
/// cached `VehicleState.speedKilometersPerHour` into fresh ride evidence; only
/// raw authoritative speed samples can fill `RideObservation.speedSample`.
@MainActor
@Observable
final class RideApplicationStore {
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
    @ObservationIgnored private var didStart = false
    @ObservationIgnored private var latestVehicleState: VehicleState
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

    func start() async {
        guard !didStart else { return }
        didStart = true

        guard let configuration else {
            status = .disabled
            return
        }
        guard startupPersistenceError == nil,
              let checkpointStore,
              let historyStore else {
            status = .persistenceUnavailable
            if lastErrorMessage == nil {
                lastErrorMessage = "Local ride recovery storage could not be opened."
            }
            return
        }

        status = .restoring
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

        let connectionChanged = state.connection != previousState.connection
        let odometerAdvanced: Bool
        if let previousOdometer = previousState.odometerKilometers,
           let currentOdometer = state.odometerKilometers {
            odometerAdvanced = currentOdometer > previousOdometer
        } else {
            odometerAdvanced = false
        }

        // State publications are useful ride evidence only when they carry a
        // transport transition or a real odometer advance. Mode/light/lock UI
        // acknowledgements must not masquerade as a fresh zero-speed sample,
        // and the last raw speed packet is never replayed here.
        guard connectionChanged || odometerAdvanced else { return }
        await ingestObservation(speedSample: nil)
    }

    private func receiveSpeedSample(_ sample: SpeedTelemetrySample) async {
        guard sample.isAuthoritativeMeasurement else { return }
        await ingestObservation(speedSample: sample)
    }

    private func ingestObservation(speedSample: SpeedTelemetrySample?) async {
        guard let coordinator,
              let historyStore,
              configuration != nil else { return }

        let minimumUptime = speedSample?.receivedAtUptimeNanoseconds ?? 0
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
                qualityScreenedGPSDistanceDeltaMeters: nil,
                motionIndicatesMovement: false
            )
            let update = try await coordinator.ingest(observation)
            updatePublishedState(from: update.phase)

            if update.events.contains(where: { event in
                if case .rideEnded = event { return true }
                return false
            }) {
                status = .saving
                try await commitPendingRide(using: coordinator, historyStore: historyStore)
                lastCompletedSessionID = update.events.compactMap { event -> UUID? in
                    guard case let .rideEnded(evidence) = event else { return nil }
                    return evidence.sessionID
                }.first
                updatePublishedState(from: await coordinator.currentPhase())
            }
        } catch RideCheckpointCoordinatorError.completedRideAwaitingCommit(_) {
            do {
                status = .saving
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
        status = .saving
        let pendingID = await coordinator.pendingCompletedRideEvidence()?.sessionID
        let commitCoordinator = RideHistoryCommitCoordinator(
            recoveryCoordinator: coordinator,
            historyStore: historyStore
        )
        _ = try await commitCoordinator.commitPendingRide()
        if let pendingID {
            lastCompletedSessionID = pendingID
        }
    }

    private func updatePublishedState(from phase: RideEnginePhase) {
        lastErrorMessage = nil

        switch phase {
        case .idle:
            status = .idle
            activeSessionID = nil
            continuity = nil
        case .candidate:
            status = .candidate
            activeSessionID = nil
            continuity = nil
        case let .active(session):
            status = .active
            activeSessionID = session.id
            continuity = session.continuity
        case let .temporarilyDisconnected(disconnected):
            status = .temporarilyDisconnected
            activeSessionID = disconnected.session.id
            continuity = disconnected.session.continuity
        case let .endingCandidate(ending):
            status = .endingCandidate
            activeSessionID = ending.session.id
            continuity = ending.session.continuity
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
        status = persistence ? .persistenceUnavailable : .failed
        lastErrorMessage = "\(error)"
    }
}
