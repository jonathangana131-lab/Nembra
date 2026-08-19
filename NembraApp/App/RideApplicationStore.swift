import Dispatch
import Foundation
import NembraCore
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
    private enum ObservationTransactionPermitOutcome: Sendable {
        case admitted
        case cancelled
    }

    private struct ObservationTransactionWaiter {
        let id: UUID
        let continuation: CheckedContinuation<ObservationTransactionPermitOutcome, Never>
    }

    private let service: any ScooterService
    private let configuration: RideApplicationConfiguration?
    private let checkpointStore: (any RideCheckpointStore)?
    private let historyStore: (any RideHistoryStore)?
    private let dailyRideStore: SwiftDataDailyRideSegmentStore?
    private let dailyRidePresentationStore: DailyRidePresentationStore?
    private let startupPersistenceError: String?
    private let dailyCalendarProvider: @Sendable () -> Calendar
    private let processGenerationID: UUID

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
    @ObservationIgnored private var pendingAuthoritativeSpeedSample: SpeedTelemetrySample?
    @ObservationIgnored private var lastObservationUptimeNanoseconds: UInt64?
    @ObservationIgnored private var dailyAccumulator: NembraCore.DailyRideSegmentAccumulator?
    @ObservationIgnored private var durationOwner = NembraCore.RideDurationObservationOwner()
    @ObservationIgnored private var durationObservationHasGap = false
    @ObservationIgnored private var durationBaseSeconds: Double?
    @ObservationIgnored private var durationBaseIsPartial = false
    @ObservationIgnored private var pendingCandidateHasGPSEvidence = false
    @ObservationIgnored private var sessionsWithGPSEvidence: Set<UUID> = []
    @ObservationIgnored private var dailyPersistenceFailClosed = false
    @ObservationIgnored private var observationTransactionInFlight = false
    @ObservationIgnored private var observationTransactionWaiters: [ObservationTransactionWaiter] = []

    init(
        service: any ScooterService,
        initialState: VehicleState,
        configuration: RideApplicationConfiguration?,
        checkpointStore: (any RideCheckpointStore)?,
        historyStore: (any RideHistoryStore)?,
        dailyRideStore: SwiftDataDailyRideSegmentStore?,
        dailyRidePresentationStore: DailyRidePresentationStore? = nil,
        dailyCalendarProvider: @escaping @Sendable () -> Calendar = { Calendar.current },
        processGenerationID: UUID = UUID(),
        startupPersistenceError: String? = nil
    ) {
        self.service = service
        self.configuration = configuration
        self.checkpointStore = checkpointStore
        self.historyStore = historyStore
        self.dailyRideStore = dailyRideStore
        self.dailyRidePresentationStore = dailyRidePresentationStore
        self.dailyCalendarProvider = dailyCalendarProvider
        self.processGenerationID = processGenerationID
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

    /// Internal deterministic evidence that a later stream callback is queued
    /// behind the one application-level ride transaction currently in flight.
    /// Production presentation never reads this diagnostic.
    var queuedObservationTransactionCount: Int {
        observationTransactionWaiters.count
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
            setStatus(.disabled)
            return
        }
        guard startupPersistenceError == nil,
              let checkpointStore,
              let historyStore,
              dailyRideStore != nil else {
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

            if let pendingCompletion = await restored.pendingCompletedRideEvidence() {
                try await persistRecoveredCompletionIfNeeded(
                    pendingCompletion,
                    recoveredAtUptimeNanoseconds: recoveredAtUptimeNanoseconds
                )
                try await commitPendingRide(using: restored, historyStore: historyStore)
            }

            let restoredPhase = await restored.currentPhase()
            try await restoreDailyWriterIfNeeded(for: restoredPhase)
            updatePublishedState(from: restoredPhase)
            await refreshDailyPresentation(
                now: recoveredAtDate,
                calendar: dailyCalendarProvider(),
                currentRideSessionID: activeSessionID
            )
            await subscribeToEvidenceStreams()
        } catch {
            failDailyPersistence(error)
        }
    }

    func stop() {
        stateTask?.cancel()
        speedTask?.cancel()
        stateTask = nil
        speedTask = nil
        pendingAuthoritativeSpeedSample = nil
    }

    /// Candidate-level/internal entry for already screened GPS evidence. This is
    /// intentionally not the production ride-location lifecycle API because an
    /// unscoped delayed delta could otherwise be assigned to a later ride.
    func ingestQualityScreenedGPSDistanceDelta(
        _ meters: Double,
        receivedAtUptimeNanoseconds: UInt64,
        receivedAtDate: Date
    ) async {
        await ingestObservation(
            speedSample: nil,
            qualityScreenedGPSDistanceDeltaMeters: meters,
            minimumUptimeNanoseconds: receivedAtUptimeNanoseconds,
            sourceReceivedAtDate: receivedAtDate,
            requiredActiveSessionID: nil
        )
    }

    /// Ride-scoped GPS evidence entry used by the phone-location capture path.
    /// The capture owns the UUID it began with. If that ride has ended or a new
    /// ride has taken over, a late coordinate delta is dropped instead of being
    /// allowed to seed movement for the wrong `RideEngine` session.
    func ingestQualityScreenedGPSDistanceDelta(
        _ meters: Double,
        receivedAtUptimeNanoseconds: UInt64,
        receivedAtDate: Date,
        for sessionID: UUID
    ) async {
        guard activeSessionID == sessionID else { return }
        await ingestObservation(
            speedSample: nil,
            qualityScreenedGPSDistanceDeltaMeters: meters,
            minimumUptimeNanoseconds: receivedAtUptimeNanoseconds,
            sourceReceivedAtDate: receivedAtDate,
            requiredActiveSessionID: sessionID
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
        minimumUptimeNanoseconds: UInt64 = 0,
        sourceReceivedAtDate: Date? = nil,
        requiredActiveSessionID: UUID? = nil
    ) async {
        // Bind this receipt to the vehicle truth visible when its stream callback
        // entered the application bridge. A later queued state publication must
        // not rewrite its connection or odometer chronology while it waits.
        let vehicleStateSnapshot = latestVehicleState
        let bridgeReceivedAtUptimeNanoseconds = DispatchTime.now().uptimeNanoseconds
        let bridgeReceivedAtDate = Date.now

        do {
            try await acquireObservationTransactionPermit()
        } catch is CancellationError {
            return
        } catch {
            return
        }
        defer { releaseObservationTransactionPermit() }

        // Stream-task cancellation may remove an observation while it is still
        // queued, but once admitted the durable transaction must finish as one
        // unit. An unstructured MainActor task does not inherit the caller's
        // cancellation and therefore cannot strand coordinator/daily/history
        // state at an intermediate await boundary.
        let transaction = Task { @MainActor [self] in
            await performObservationTransaction(
                speedSample: speedSample,
                qualityScreenedGPSDistanceDeltaMeters: qualityScreenedGPSDistanceDeltaMeters,
                minimumUptimeNanoseconds: minimumUptimeNanoseconds,
                sourceReceivedAtDate: sourceReceivedAtDate,
                vehicleStateSnapshot: vehicleStateSnapshot,
                bridgeReceivedAtUptimeNanoseconds: bridgeReceivedAtUptimeNanoseconds,
                bridgeReceivedAtDate: bridgeReceivedAtDate,
                requiredActiveSessionID: requiredActiveSessionID
            )
        }
        await transaction.value
    }

    private func performObservationTransaction(
        speedSample: SpeedTelemetrySample?,
        qualityScreenedGPSDistanceDeltaMeters: Double?,
        minimumUptimeNanoseconds: UInt64,
        sourceReceivedAtDate: Date?,
        vehicleStateSnapshot: VehicleState,
        bridgeReceivedAtUptimeNanoseconds: UInt64,
        bridgeReceivedAtDate: Date,
        requiredActiveSessionID: UUID?
    ) async {
        guard let coordinator,
              let historyStore,
              configuration != nil,
              !dailyPersistenceFailClosed else { return }
        if let requiredActiveSessionID,
           activeSessionID != requiredActiveSessionID {
            return
        }

        let minimumUptime = max(
            max(
                speedSample?.receivedAtUptimeNanoseconds ?? 0,
                minimumUptimeNanoseconds
            ),
            bridgeReceivedAtUptimeNanoseconds
        )
        guard let observationUptime = nextObservationUptime(minimum: minimumUptime) else {
            fail(RideEngineError.nonMonotonicObservation, persistence: false)
            return
        }

        do {
            // Source receipt time owns local-day attribution. MainActor delivery
            // latency is processing metadata and must not move accepted evidence
            // across midnight. Transport-only state transitions have no separate
            // source receipt and therefore use their processing boundary.
            let receiptWallDate = speedSample?.receivedAtDate
                ?? sourceReceivedAtDate
                ?? bridgeReceivedAtDate
            let observation = try RideObservation(
                receivedAtUptimeNanoseconds: observationUptime,
                receivedAtDate: receiptWallDate,
                connection: vehicleStateSnapshot.connection,
                speedSample: speedSample,
                odometerKilometers: vehicleStateSnapshot.odometerKilometers,
                qualityScreenedGPSDistanceDeltaMeters: qualityScreenedGPSDistanceDeltaMeters,
                motionIndicatesMovement: false
            )
            let update = try await coordinator.ingest(observation)

            do {
                try await acceptDailyCheckpoint(
                    for: update,
                    observation: observation
                )
            } catch {
                failDailyPersistence(error)
                return
            }

            // Publish engine phase only after the corresponding accepted-day
            // transaction has completed. In particular, callers must never be
            // able to observe `.active` and tear down the store while its daily
            // receipt is still suspended in persistence.
            updatePublishedState(from: update.phase)

            if update.events.contains(where: { event in
                if case .rideEnded = event { return true }
                return false
            }) {
                setStatus(.saving)
                try await commitPendingRide(using: coordinator, historyStore: historyStore)
                let completedSessionID = update.events.compactMap { event -> UUID? in
                    guard case let .rideEnded(evidence) = event else { return nil }
                    return evidence.sessionID
                }.first
                if lastCompletedSessionID != completedSessionID {
                    lastCompletedSessionID = completedSessionID
                }
                updatePublishedState(from: await coordinator.currentPhase())
            }
        } catch RideCheckpointCoordinatorError.completedRideAwaitingCommit(_) {
            do {
                if let pending = await coordinator.pendingCompletedRideEvidence() {
                    try await persistRecoveredCompletionIfNeeded(
                        pending,
                        recoveredAtUptimeNanoseconds: observationUptime
                    )
                }
                setStatus(.saving)
                try await commitPendingRide(using: coordinator, historyStore: historyStore)
                updatePublishedState(from: await coordinator.currentPhase())
            } catch {
                failDailyPersistence(error)
            }
        } catch {
            fail(error, persistence: false)
        }
    }

    /// One FIFO permit spans coordinator mutation, accepted-day persistence,
    /// and completion/history acknowledgement. MainActor isolation alone is not
    /// sufficient because each external persistence `await` is reentrant.
    private func acquireObservationTransactionPermit() async throws {
        try Task.checkCancellation()

        guard observationTransactionInFlight else {
            observationTransactionInFlight = true
            return
        }

        let waiterID = UUID()
        let outcome: ObservationTransactionPermitOutcome = await withTaskCancellationHandler {
            await withCheckedContinuation {
                (continuation: CheckedContinuation<ObservationTransactionPermitOutcome, Never>) in
                if Task.isCancelled {
                    continuation.resume(returning: .cancelled)
                    return
                }
                observationTransactionWaiters.append(
                    ObservationTransactionWaiter(
                        id: waiterID,
                        continuation: continuation
                    )
                )
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancelObservationTransactionWaiter(id: waiterID)
            }
        }

        switch outcome {
        case .cancelled:
            throw CancellationError()
        case .admitted:
            do {
                try Task.checkCancellation()
            } catch {
                // Ownership was already transferred to this waiter. Return the
                // permit before propagating a cancellation racing with handoff.
                releaseObservationTransactionPermit()
                throw error
            }
        }
    }

    private func cancelObservationTransactionWaiter(id: UUID) {
        guard let index = observationTransactionWaiters.firstIndex(where: { $0.id == id }) else {
            return
        }
        let waiter = observationTransactionWaiters.remove(at: index)
        waiter.continuation.resume(returning: .cancelled)
    }

    private func releaseObservationTransactionPermit() {
        guard observationTransactionInFlight else { return }
        guard !observationTransactionWaiters.isEmpty else {
            observationTransactionInFlight = false
            return
        }
        let next = observationTransactionWaiters.removeFirst()
        next.continuation.resume(returning: .admitted)
    }

    private struct DailySessionEvidence {
        let sessionID: UUID
        let cumulativeGPSDistanceMeters: Double
        let continuity: RideSessionContinuity
    }

    /// The only live writer into the accepted daily ledger. It consumes the
    /// exact `RideEngineUpdate` produced for this observation and monotonic
    /// duration evidence owned here; display state and wall-clock subtraction
    /// never participate.
    private func acceptDailyCheckpoint(
        for update: RideEngineUpdate,
        observation: RideObservation
    ) async throws {
        updateGPSEvidenceOwnership(update: update, observation: observation)

        guard let evidence = dailySessionEvidence(for: update) else {
            if case .idle = update.phase {
                pendingCandidateHasGPSEvidence = false
            }
            return
        }
        try await attachDailyAccumulator(sessionID: evidence.sessionID)
        let durationSnapshot = try advanceDurationOwner(
            update: update,
            observation: observation,
            sessionID: evidence.sessionID
        )

        let calendar = dailyCalendarProvider()
        let localDay = try NembraCore.RideLocalDay(
            containing: observation.receivedAtDate,
            calendar: calendar
        )
        guard shouldPersistDailyCheckpoint(
            update: update,
            observation: observation,
            localDay: localDay
        ) else { return }

        let duration = try cumulativeDurationMetric(snapshot: durationSnapshot)
        let completed = update.events.contains { event in
            if case .rideEnded = event { return true }
            return false
        }
        try await persistDailyReceipt(
            evidence: evidence,
            duration: duration,
            wallDate: observation.receivedAtDate,
            uptimeNanoseconds: observation.receivedAtUptimeNanoseconds,
            calendar: calendar,
            currentRideSessionID: completed ? nil : evidence.sessionID
        )

        if completed {
            sessionsWithGPSEvidence.remove(evidence.sessionID)
            durationOwner = NembraCore.RideDurationObservationOwner()
            durationObservationHasGap = false
            durationBaseSeconds = nil
            durationBaseIsPartial = false
        }
    }

    private func dailySessionEvidence(for update: RideEngineUpdate) -> DailySessionEvidence? {
        for event in update.events {
            if case let .rideEnded(completed) = event {
                return DailySessionEvidence(
                    sessionID: completed.sessionID,
                    cumulativeGPSDistanceMeters: completed.qualityScreenedGPSDistanceMeters,
                    continuity: completed.continuity
                )
            }
        }
        return dailySessionEvidence(for: update.phase)
    }

    private func dailySessionEvidence(for phase: RideEnginePhase) -> DailySessionEvidence? {
        let session: ActiveRideSession
        switch phase {
        case .idle, .candidate:
            return nil
        case let .active(active):
            session = active
        case let .temporarilyDisconnected(disconnected):
            session = disconnected.session
        case let .endingCandidate(ending):
            session = ending.session
        }
        return DailySessionEvidence(
            sessionID: session.id,
            cumulativeGPSDistanceMeters: session.accumulatedGPSDistanceMeters,
            continuity: session.continuity
        )
    }

    private func updateGPSEvidenceOwnership(
        update: RideEngineUpdate,
        observation: RideObservation
    ) {
        if case .candidate = update.phase,
           observation.qualityScreenedGPSDistanceDeltaMeters != nil {
            pendingCandidateHasGPSEvidence = true
        }

        if let evidence = dailySessionEvidence(for: update),
           observation.qualityScreenedGPSDistanceDeltaMeters != nil
                || pendingCandidateHasGPSEvidence
                || evidence.cumulativeGPSDistanceMeters > 0 {
            sessionsWithGPSEvidence.insert(evidence.sessionID)
            pendingCandidateHasGPSEvidence = false
        }

        if update.events.contains(where: { event in
            if case .candidateCancelled = event { return true }
            return false
        }) {
            pendingCandidateHasGPSEvidence = false
        }
    }

    private func attachDailyAccumulator(sessionID: UUID) async throws {
        guard dailyAccumulator?.sessionID != sessionID else { return }
        guard let dailyRideStore else {
            throw DailyRidePersistenceError.accumulatorConflict(sessionID)
        }
        let restored = try await dailyRideStore.accumulator(sessionID: sessionID)
        dailyAccumulator = restored
            ?? NembraCore.DailyRideSegmentAccumulator(sessionID: sessionID)

        if restored?.lastAcknowledgedCheckpoint?.distanceSource == .gpsRoute {
            // An explicitly accepted zero-distance GPS anchor is still GPS
            // evidence. Reconstruct its ownership after relaunch instead of
            // relying on a positive numeric delta as a proxy for provenance.
            sessionsWithGPSEvidence.insert(sessionID)
        }

        if let duration = restored?.lastAcknowledgedCheckpoint?.cumulativeDurationSeconds {
            durationBaseSeconds = duration.value
            durationBaseIsPartial = duration.disposition != .complete
        } else {
            durationBaseSeconds = 0
            durationBaseIsPartial = false
        }
    }

    private func advanceDurationOwner(
        update: RideEngineUpdate,
        observation: RideObservation,
        sessionID: UUID
    ) throws -> NembraCore.RideSessionDurationEvidenceSnapshot? {
        var candidate = durationOwner
        var candidateObservationHasGap = durationObservationHasGap
        var handledLifecycleBoundary = false
        var finalizedSnapshot: NembraCore.RideSessionDurationEvidenceSnapshot?

        func continueObservation(
            sessionID: UUID,
            beginsAfterUnobservedInterval: Bool
        ) throws {
            if candidate.activeSessionID == nil {
                try candidate.begin(
                    sessionID: sessionID,
                    processGenerationID: processGenerationID,
                    atUptimeNanoseconds: observation.receivedAtUptimeNanoseconds,
                    beginsAfterUnobservedInterval: beginsAfterUnobservedInterval
                )
            } else if candidateObservationHasGap {
                try candidate.resumeObservation(
                    sessionID: sessionID,
                    processGenerationID: processGenerationID,
                    atUptimeNanoseconds: observation.receivedAtUptimeNanoseconds
                )
            } else {
                try candidate.observe(
                    sessionID: sessionID,
                    atUptimeNanoseconds: observation.receivedAtUptimeNanoseconds
                )
            }
            candidateObservationHasGap = false
        }

        for event in update.events {
            switch event {
            case let .rideStarted(session):
                let candidateIntervalWasUnobserved = session.beganAtUptimeNanoseconds
                    != observation.receivedAtUptimeNanoseconds
                try candidate.begin(
                    sessionID: session.id,
                    processGenerationID: processGenerationID,
                    atUptimeNanoseconds: observation.receivedAtUptimeNanoseconds,
                    beginsAfterUnobservedInterval: candidateIntervalWasUnobserved
                )
                candidateObservationHasGap = false
                handledLifecycleBoundary = true

            case let .rideTemporarilyDisconnected(disconnectedSessionID):
                try candidate.markObservationGap(
                    sessionID: disconnectedSessionID,
                    atUptimeNanoseconds: observation.receivedAtUptimeNanoseconds
                )
                candidateObservationHasGap = true
                handledLifecycleBoundary = true

            case let .rideResumed(resumedSessionID):
                try continueObservation(
                    sessionID: resumedSessionID,
                    beginsAfterUnobservedInterval: true
                )
                handledLifecycleBoundary = true

            case let .rideEnded(completed):
                finalizedSnapshot = try candidate.end(
                    sessionID: completed.sessionID,
                    atUptimeNanoseconds: observation.receivedAtUptimeNanoseconds
                )
                candidateObservationHasGap = false
                handledLifecycleBoundary = true

            case .candidateStarted, .candidateCancelled, .endingCandidateStarted:
                break
            }
        }

        if !handledLifecycleBoundary {
            switch update.phase {
            case .active, .endingCandidate:
                try continueObservation(
                    sessionID: sessionID,
                    // Missing process-local observation ownership is itself a
                    // gap; never infer completeness from an absent owner.
                    beginsAfterUnobservedInterval: true
                )
            case .temporarilyDisconnected, .idle, .candidate:
                break
            }
        }

        durationOwner = candidate
        durationObservationHasGap = candidateObservationHasGap
        return finalizedSnapshot ?? candidate.snapshot
    }

    private func shouldPersistDailyCheckpoint(
        update: RideEngineUpdate,
        observation: RideObservation,
        localDay: NembraCore.RideLocalDay
    ) -> Bool {
        guard let last = dailyAccumulator?.lastAcknowledgedCheckpoint else { return true }
        if last.localDay != localDay { return true }
        if observation.receivedAtDate <= last.wallDate { return true }
        if update.events.contains(where: { event in
            switch event {
            case .rideStarted, .rideTemporarilyDisconnected, .rideResumed,
                 .endingCandidateStarted, .rideEnded:
                return true
            case .candidateStarted, .candidateCancelled:
                return false
            }
        }) {
            return true
        }
        guard observation.receivedAtUptimeNanoseconds > last.uptimeNanoseconds,
              let configuration else {
            return true
        }
        return observation.receivedAtUptimeNanoseconds - last.uptimeNanoseconds
            >= configuration.checkpointCadence.minimumIntervalNanoseconds
    }

    private func cumulativeDurationMetric(
        snapshot: NembraCore.RideSessionDurationEvidenceSnapshot?
    ) throws -> NembraCore.DailyRideMetricEvidence {
        guard let durationBaseSeconds,
              let snapshot,
              let observedNanoseconds = snapshot.observedDurationNanoseconds else {
            return try NembraCore.DailyRideMetricEvidence(
                value: nil,
                disposition: .unavailable
            )
        }
        let observedSeconds = Double(observedNanoseconds) / 1_000_000_000
        let cumulative = durationBaseSeconds + observedSeconds
        guard cumulative.isFinite else {
            throw DailyRidePersistenceError.accumulatorConflict(snapshot.sessionID)
        }
        let disposition: NembraCore.DailyRideMetricDisposition
        switch snapshot.coverage {
        case .complete where !durationBaseIsPartial:
            disposition = .complete
        case .complete, .partial:
            disposition = .knownPartial
        case .unknown:
            return try NembraCore.DailyRideMetricEvidence(
                value: nil,
                disposition: .unavailable
            )
        }
        return try NembraCore.DailyRideMetricEvidence(
            value: cumulative,
            disposition: disposition
        )
    }

    private func persistDailyReceipt(
        evidence: DailySessionEvidence,
        duration: NembraCore.DailyRideMetricEvidence,
        wallDate: Date,
        uptimeNanoseconds: UInt64,
        calendar: Calendar,
        currentRideSessionID: UUID?
    ) async throws {
        guard let dailyRideStore,
              let accumulator = dailyAccumulator,
              accumulator.sessionID == evidence.sessionID else {
            throw DailyRidePersistenceError.accumulatorConflict(evidence.sessionID)
        }

        let distance: NembraCore.DailyRideMetricEvidence
        let distanceSource: NembraCore.RideDistanceSource?
        if sessionsWithGPSEvidence.contains(evidence.sessionID) {
            distance = try NembraCore.DailyRideMetricEvidence(
                value: evidence.cumulativeGPSDistanceMeters,
                disposition: .knownPartial
            )
            distanceSource = .gpsRoute
        } else {
            distance = try NembraCore.DailyRideMetricEvidence(
                value: nil,
                disposition: .unavailable
            )
            distanceSource = nil
        }

        let sequence: UInt64
        if let previous = accumulator.lastAcknowledgedCheckpoint {
            guard previous.sequence < UInt64.max else {
                throw DailyRidePersistenceError.accumulatorConflict(evidence.sessionID)
            }
            sequence = previous.sequence + 1
        } else {
            sequence = 0
        }
        guard let packageContinuity = NembraCore.RideSessionContinuity(
            rawValue: evidence.continuity.rawValue
        ) else {
            throw DailyRidePersistenceError.accumulatorConflict(evidence.sessionID)
        }
        let checkpoint = try NembraCore.AcceptedDailyRideCheckpoint(
            sessionID: evidence.sessionID,
            sequence: sequence,
            uptimeNanoseconds: uptimeNanoseconds,
            wallDate: wallDate,
            localDay: NembraCore.RideLocalDay(containing: wallDate, calendar: calendar),
            cumulativeDistanceMeters: distance,
            cumulativeDurationSeconds: duration,
            distanceSource: distanceSource,
            continuity: packageContinuity
        )
        let proposal = try accumulator.prepare(checkpoint)
        _ = try await dailyRideStore.commit(proposal)
        dailyAccumulator = proposal.accumulatorAfterPersistence
        await refreshDailyPresentation(
            // The receipt's source date owns ledger placement, while Today is
            // always the user's actual current local day at presentation time.
            now: .now,
            calendar: dailyCalendarProvider(),
            currentRideSessionID: currentRideSessionID
        )
    }

    private func restoreDailyWriterIfNeeded(for phase: RideEnginePhase) async throws {
        guard let evidence = dailySessionEvidence(for: phase) else { return }
        try await attachDailyAccumulator(sessionID: evidence.sessionID)
        if evidence.cumulativeGPSDistanceMeters > 0 {
            sessionsWithGPSEvidence.insert(evidence.sessionID)
        }

        // Recovery is not a scooter or location observation. Keep duration in
        // an explicit gap until fresh evidence arrives instead of extending a
        // process-local monotonic segment across time Nembra did not observe.
        durationOwner = NembraCore.RideDurationObservationOwner()
        durationObservationHasGap = true
    }

    private func persistRecoveredCompletionIfNeeded(
        _ completed: CompletedRideEvidence,
        recoveredAtUptimeNanoseconds: UInt64
    ) async throws {
        let evidence = DailySessionEvidence(
            sessionID: completed.sessionID,
            cumulativeGPSDistanceMeters: completed.qualityScreenedGPSDistanceMeters,
            continuity: completed.continuity
        )
        try await attachDailyAccumulator(sessionID: completed.sessionID)
        if completed.qualityScreenedGPSDistanceMeters > 0 {
            sessionsWithGPSEvidence.insert(completed.sessionID)
        }

        let expectedDistance: NembraCore.DailyRideMetricEvidence
        if sessionsWithGPSEvidence.contains(completed.sessionID) {
            expectedDistance = try NembraCore.DailyRideMetricEvidence(
                value: completed.qualityScreenedGPSDistanceMeters,
                disposition: .knownPartial
            )
        } else {
            expectedDistance = try NembraCore.DailyRideMetricEvidence(
                value: nil,
                disposition: .unavailable
            )
        }
        if let last = dailyAccumulator?.lastAcknowledgedCheckpoint,
           last.wallDate == completed.endedAtDate,
           last.cumulativeDistanceMeters == expectedDistance {
            return
        }

        let duration = try Self.recoveredCompletionDuration(
            after: dailyAccumulator?.lastAcknowledgedCheckpoint
        )
        try await persistDailyReceipt(
            evidence: evidence,
            duration: duration,
            wallDate: completed.endedAtDate,
            uptimeNanoseconds: recoveredAtUptimeNanoseconds,
            calendar: dailyCalendarProvider(),
            currentRideSessionID: nil
        )
    }

    /// A recovered pending completion cannot reconstruct time outside an
    /// observed monotonic segment. Preserve the exact accepted numeric floor and
    /// qualify it partial; never replace a durable numeric cumulative duration
    /// with `.unavailable`, which would discard known evidence.
    nonisolated static func recoveredCompletionDuration(
        after checkpoint: NembraCore.AcceptedDailyRideCheckpoint?
    ) throws -> NembraCore.DailyRideMetricEvidence {
        guard let prior = checkpoint?.cumulativeDurationSeconds else {
            return try NembraCore.DailyRideMetricEvidence(
                value: nil,
                disposition: .unavailable
            )
        }
        if let value = prior.value {
            return try NembraCore.DailyRideMetricEvidence(
                value: value,
                disposition: .knownPartial
            )
        }
        return try NembraCore.DailyRideMetricEvidence(
            value: nil,
            disposition: prior.disposition == .conflicting
                ? .conflicting
                : .unavailable
        )
    }

    private func refreshDailyPresentation(
        now: Date,
        calendar: Calendar,
        currentRideSessionID: UUID?
    ) async {
        await dailyRidePresentationStore?.refresh(
            now: now,
            calendar: calendar,
            currentRideSessionID: currentRideSessionID
        )
    }

    private func failDailyPersistence(_ error: Error) {
        dailyPersistenceFailClosed = true
        dailyRidePresentationStore?.markPersistenceFailure()
        fail(error, persistence: true)
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
        if activeSessionID != newSessionID {
            activeSessionID = newSessionID
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
        // `minimum` is the bridge/source receipt captured before any FIFO wait.
        // Mutate the chronology only after admission without charging durable-I/O
        // queue latency as if it were observed ride duration.
        var candidate = minimum
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
