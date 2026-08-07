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

/// The core checkpoint coordinator is an actor, but actor isolation alone does
/// not make one async method non-reentrant across its durable-store awaits. This
/// application gate keeps every coordinator mutation/read that matters to ride
/// admission behind one explicit async mutex. It protects the existing core
/// contract without modifying the independently owned NembraCore lane.
private actor RideCheckpointCoordinatorAccessGate {
    private let coordinator: RideCheckpointCoordinator
    private var isLocked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(coordinator: RideCheckpointCoordinator) {
        self.coordinator = coordinator
    }

    func ingest(_ observation: RideObservation) async throws -> RideEngineUpdate {
        await acquire()
        defer { release() }
        return try await coordinator.ingest(observation)
    }

    func pendingCompletedRideEvidence() async -> CompletedRideEvidence? {
        await acquire()
        defer { release() }
        return await coordinator.pendingCompletedRideEvidence()
    }

    func currentPhase() async -> RideEnginePhase {
        await acquire()
        defer { release() }
        return await coordinator.currentPhase()
    }

    func commitPendingRide(historyStore: any RideHistoryStore) async throws {
        await acquire()
        defer { release() }
        let commitCoordinator = RideHistoryCommitCoordinator(
            recoveryCoordinator: coordinator,
            historyStore: historyStore
        )
        _ = try await commitCoordinator.commitPendingRide()
    }

    private func acquire() async {
        if !isLocked {
            isLocked = true
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func release() {
        guard !waiters.isEmpty else {
            isLocked = false
            return
        }
        // `isLocked` intentionally stays true. Ownership transfers directly to
        // the resumed waiter so no later caller can overtake it.
        let next = waiters.removeFirst()
        next.resume()
    }
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
    typealias RideCompletionBarrier = @MainActor @Sendable (_ sessionID: UUID) async throws -> Void

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

    @ObservationIgnored private var coordinatorAccessGate: RideCheckpointCoordinatorAccessGate?
    @ObservationIgnored private var stateTask: Task<Void, Never>?
    @ObservationIgnored private var speedTask: Task<Void, Never>?
    @ObservationIgnored private var completionFinalizationTask: Task<Bool, Never>?
    @ObservationIgnored private var sessionEventContinuation: AsyncStream<RideApplicationSessionEvent>.Continuation?
    @ObservationIgnored private var rideCompletionBarrier: RideCompletionBarrier?
    @ObservationIgnored private var isFinalizingCompletedRide = false
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
        completionFinalizationTask?.cancel()
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
    /// that must be durably reconciled before the completed ride is committed.
    /// A throwing barrier intentionally leaves `completedPendingCommit` intact so
    /// a later in-process observation or launch can retry without losing history.
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
            let accessGate = RideCheckpointCoordinatorAccessGate(coordinator: restored)
            coordinatorAccessGate = accessGate
            lastObservationUptimeNanoseconds = recoveredAtUptimeNanoseconds

            // Subscribe even when startup has a pending completion. If a
            // transient route-outcome/history dependency fails, later live
            // evidence can retry the exact pending handoff in the same process
            // instead of requiring a relaunch. While the initial attempt runs,
            // the finalization flag makes those streams fail closed.
            let hasPendingCompletion = await accessGate.pendingCompletedRideEvidence() != nil
            if hasPendingCompletion {
                isFinalizingCompletedRide = true
            }
            await subscribeToEvidenceStreams()

            if hasPendingCompletion {
                let committed = await finalizePendingRide(
                    using: accessGate,
                    historyStore: historyStore
                )
                guard committed else { return }
            }

            updatePublishedState(from: await accessGate.currentPhase())
        } catch {
            isFinalizingCompletedRide = false
            fail(error, persistence: true)
        }
    }

    func stop() {
        stateTask?.cancel()
        speedTask?.cancel()
        completionFinalizationTask?.cancel()
        stateTask = nil
        speedTask = nil
        completionFinalizationTask = nil
        pendingAuthoritativeSpeedSample = nil
        sessionEventContinuation?.finish()
        sessionEventContinuation = nil
        rideCompletionBarrier = nil
        isFinalizingCompletedRide = false
    }

    /// Candidate-level/internal entry for already screened GPS evidence. This is
    /// intentionally not the production ride-location lifecycle API because an
    /// unscoped delayed delta could otherwise be assigned to a later ride.
    @discardableResult
    func ingestQualityScreenedGPSDistanceDelta(
        _ meters: Double,
        receivedAtUptimeNanoseconds: UInt64
    ) async -> Bool {
        await ingestObservation(
            speedSample: nil,
            qualityScreenedGPSDistanceDeltaMeters: meters,
            minimumUptimeNanoseconds: receivedAtUptimeNanoseconds
        )
    }

    /// Ride-scoped GPS evidence entry used by the phone-location capture path.
    /// The capture owns the UUID it began with. The Bool is authoritative for
    /// the matching route point: `false` means this delta did not enter the
    /// active ride and the coordinate must not be persisted as that ride's route.
    @discardableResult
    func ingestQualityScreenedGPSDistanceDelta(
        _ meters: Double,
        receivedAtUptimeNanoseconds: UInt64,
        for sessionID: UUID
    ) async -> Bool {
        await admitQualityScreenedLocationEvidence(
            distanceDeltaMeters: meters,
            receivedAtUptimeNanoseconds: receivedAtUptimeNanoseconds,
            for: sessionID
        )
    }

    /// One application-owned admission boundary for every screened location
    /// point. First-anchor and zero-distance points carry no movement evidence,
    /// but they still serialize behind any in-flight checkpoint mutation and
    /// consult the exact pending-completion UUID before route admission. Positive
    /// GPS deltas must successfully enter RideEngine before their coordinate may
    /// become route evidence.
    ///
    /// Treating zero distance as identity-only is also a deadlock boundary: a
    /// stationary location callback cannot itself end the ride and then wait for
    /// a completion barrier that must drain the callback's own capture task.
    func admitQualityScreenedLocationEvidence(
        distanceDeltaMeters: Double?,
        receivedAtUptimeNanoseconds: UInt64,
        for sessionID: UUID
    ) async -> Bool {
        guard !isFinalizingCompletedRide,
              activeSessionID == sessionID,
              let accessGate = coordinatorAccessGate else { return false }

        if let distanceDeltaMeters, distanceDeltaMeters < 0 {
            return false
        }

        if distanceDeltaMeters == nil || distanceDeltaMeters == 0 {
            if let pending = await accessGate.pendingCompletedRideEvidence(),
               pending.sessionID == sessionID {
                return false
            }
            // MainActor is reentrant across the gate hop above. Re-check the
            // published boundary before admitting an anchor/stationary point.
            guard !isFinalizingCompletedRide,
                  activeSessionID == sessionID else { return false }
            return true
        }

        guard let distanceDeltaMeters else { return false }
        return await ingestQualityScreenedGPSDistanceDelta(
            distanceDeltaMeters,
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

    @discardableResult
    private func ingestObservation(
        speedSample: SpeedTelemetrySample?,
        qualityScreenedGPSDistanceDeltaMeters: Double? = nil,
        minimumUptimeNanoseconds: UInt64 = 0
    ) async -> Bool {
        guard !isFinalizingCompletedRide,
              let accessGate = coordinatorAccessGate,
              let historyStore,
              configuration != nil else { return false }

        let minimumUptime = max(
            speedSample?.receivedAtUptimeNanoseconds ?? 0,
            minimumUptimeNanoseconds
        )
        guard let observationUptime = nextObservationUptime(minimum: minimumUptime) else {
            fail(RideEngineError.nonMonotonicObservation, persistence: false)
            return false
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
            let update = try await accessGate.ingest(observation)
            let completedSessionID = update.events.compactMap { event -> UUID? in
                guard case let .rideEnded(evidence) = event else { return nil }
                return evidence.sessionID
            }.first

            if completedSessionID != nil {
                // The access gate is already released here. Buffered capture
                // callbacks can now observe the durable pending-completion state
                // and fail admission while the barrier drains them, avoiding a
                // cyclic self-await between coordinator.finish() and its sink.
                return await finalizePendingRide(
                    using: accessGate,
                    historyStore: historyStore
                )
            }

            updatePublishedState(from: update.phase)
            return true
        } catch RideCheckpointCoordinatorError.completedRideAwaitingCommit(_) {
            // A second ingress may have queued behind the observation that ended
            // the ride. Whichever MainActor task reaches this branch first owns
            // the shared finalization Task; all others await the same result.
            guard !isFinalizingCompletedRide || completionFinalizationTask != nil else {
                return false
            }
            _ = await finalizePendingRide(
                using: accessGate,
                historyStore: historyStore
            )
            return false
        } catch {
            fail(error, persistence: false)
            return false
        }
    }

    /// Exactly one MainActor task owns the route-outcome/history handoff for the
    /// current pending completion. Callers that raced behind the same checkpoint
    /// ingest await that task instead of starting a second barrier/acknowledgment.
    private func finalizePendingRide(
        using accessGate: RideCheckpointCoordinatorAccessGate,
        historyStore: any RideHistoryStore
    ) async -> Bool {
        if let completionFinalizationTask {
            return await completionFinalizationTask.value
        }

        isFinalizingCompletedRide = true
        let task = Task { @MainActor [weak self] () -> Bool in
            guard let self else { return false }
            do {
                try await self.commitPendingRide(
                    using: accessGate,
                    historyStore: historyStore
                )
                self.isFinalizingCompletedRide = false
                self.updatePublishedState(from: await accessGate.currentPhase())
                return true
            } catch {
                self.isFinalizingCompletedRide = false
                self.fail(error, persistence: true)
                return false
            }
        }
        completionFinalizationTask = task
        let result = await task.value
        completionFinalizationTask = nil
        return result
    }

    private func commitPendingRide(
        using accessGate: RideCheckpointCoordinatorAccessGate,
        historyStore: any RideHistoryStore
    ) async throws {
        setStatus(.saving)
        let pendingID = await accessGate.pendingCompletedRideEvidence()?.sessionID
        if let pendingID {
            try await rideCompletionBarrier?(pendingID)
            try await accessGate.commitPendingRide(historyStore: historyStore)
            if lastCompletedSessionID != pendingID {
                lastCompletedSessionID = pendingID
            }
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
