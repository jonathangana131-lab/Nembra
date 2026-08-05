import Foundation
import Testing
@testable import NembraCore

private enum RecordingRideCheckpointStoreError: Error, Equatable {
    case injectedFailure
}

private actor RecordingRideCheckpointStore: RideCheckpointStore {
    private(set) var value: RideDurableCheckpoint?
    private(set) var savedValues: [RideDurableCheckpoint] = []
    private(set) var clearCount = 0
    private var shouldFailNextSave = false
    private var shouldFailNextClear = false

    init(value: RideDurableCheckpoint? = nil) {
        self.value = value
    }

    func save(_ checkpoint: RideDurableCheckpoint) async throws {
        if shouldFailNextSave {
            shouldFailNextSave = false
            throw RecordingRideCheckpointStoreError.injectedFailure
        }
        value = checkpoint
        savedValues.append(checkpoint)
    }

    func load() async throws -> RideDurableCheckpoint? {
        value
    }

    func clear() async throws {
        if shouldFailNextClear {
            shouldFailNextClear = false
            throw RecordingRideCheckpointStoreError.injectedFailure
        }
        value = nil
        clearCount += 1
    }

    func failNextSave() {
        shouldFailNextSave = true
    }

    func failNextClear() {
        shouldFailNextClear = true
    }
}

@Suite("Ride checkpoint coordinator")
struct RideCheckpointCoordinatorTests {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)
    private let fixedSessionID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!

    private func policy(endingDuration: UInt64 = 5_000) throws -> RideDetectionPolicy {
        try RideDetectionPolicy(
            candidateSpeedKilometersPerHour: 1,
            confirmationSpeedKilometersPerHour: 4,
            confirmationDurationNanoseconds: 0,
            confirmationOdometerDeltaKilometers: 0.05,
            confirmationGPSDistanceMeters: 8,
            endingDurationNanoseconds: endingDuration,
            maximumSpeedSampleAgeNanoseconds: 1_000
        )
    }

    private func cadence(_ interval: UInt64 = 10_000) throws -> RideCheckpointCadence {
        try RideCheckpointCadence(minimumIntervalNanoseconds: interval)
    }

    private func observation(
        _ uptime: UInt64,
        connection: VehicleConnectionState = .connected,
        speedKPH: Double? = nil,
        odometer: Double? = nil,
        gpsDelta: Double? = nil
    ) throws -> RideObservation {
        let date = epoch.addingTimeInterval(Double(uptime) / 1_000_000_000)
        let sample = try speedKPH.map {
            try SpeedTelemetrySample(
                source: .scooterBluetooth,
                provenance: .absoluteMeasurement,
                metersPerSecond: $0 / 3.6,
                receivedAtUptimeNanoseconds: uptime,
                receivedAtDate: date
            )
        }
        return try RideObservation(
            receivedAtUptimeNanoseconds: uptime,
            receivedAtDate: date,
            connection: connection,
            speedSample: sample,
            odometerKilometers: odometer,
            qualityScreenedGPSDistanceDeltaMeters: gpsDelta
        )
    }

    private func coordinator(
        store: RecordingRideCheckpointStore,
        cadenceInterval: UInt64 = 10_000
    ) throws -> RideCheckpointCoordinator {
        RideCheckpointCoordinator(
            engine: RideEngine(policy: try policy(), makeSessionID: { fixedSessionID }),
            store: store,
            cadence: try cadence(cadenceInterval)
        )
    }

    private func inProgressCheckpoint() throws -> RideRecoveryCheckpoint {
        try RideRecoveryCheckpoint(
            sessionID: fixedSessionID,
            beganAtDate: epoch,
            confirmedAtDate: epoch.addingTimeInterval(1),
            persistedPhase: .active,
            phaseBeganAtDate: nil,
            lastObservedAtDate: epoch.addingTimeInterval(2),
            checkpointedAtDate: epoch.addingTimeInterval(2),
            startingOdometerKilometers: 100,
            latestOdometerKilometers: 100.5,
            accumulatedGPSDistanceMeters: 500
        )
    }

    private func completedEvidence() throws -> CompletedRideEvidence {
        var engine = RideEngine(policy: try policy(), makeSessionID: { fixedSessionID })
        _ = try engine.ingest(observation(1_000, speedKPH: 8, odometer: 100, gpsDelta: 2))
        _ = try engine.ingest(observation(1_500, speedKPH: 8, odometer: 100.1, gpsDelta: 1))
        _ = try engine.ingest(observation(2_000, speedKPH: 0, odometer: 100.1))
        let ended = try engine.ingest(observation(7_000, speedKPH: 0, odometer: 100.1))
        for event in ended.events {
            if case let .rideEnded(evidence) = event {
                return evidence
            }
        }
        throw RecordingRideCheckpointStoreError.injectedFailure
    }

    @Test("checkpoint cadence rejects zero instead of creating write-every-frame semantics")
    func invalidCadenceRejected() {
        #expect(throws: RideCheckpointCoordinatorError.invalidCadence) {
            _ = try RideCheckpointCadence(minimumIntervalNanoseconds: 0)
        }
    }

    @Test("ride start is persisted immediately even when periodic cadence is not due")
    func rideStartPersistsImmediately() async throws {
        let store = RecordingRideCheckpointStore()
        let coordinator = try coordinator(store: store)

        let update = try await coordinator.ingest(
            observation(1_000, speedKPH: 8, odometer: 100, gpsDelta: 1)
        )
        guard case .active = update.phase else {
            Issue.record("ride should be active")
            return
        }

        let saved = await store.savedValues
        #expect(saved.count == 1)
        guard case let .inProgress(checkpoint) = saved.first else {
            Issue.record("ride start must save in-progress recovery evidence")
            return
        }
        #expect(checkpoint.sessionID == fixedSessionID)
    }

    @Test("stable active telemetry is checkpointed by cadence, not every observation")
    func activeUpdatesRespectCadence() async throws {
        let store = RecordingRideCheckpointStore()
        let coordinator = try coordinator(store: store, cadenceInterval: 10_000)

        _ = try await coordinator.ingest(observation(1_000, speedKPH: 8, odometer: 100))
        _ = try await coordinator.ingest(observation(2_000, speedKPH: 8, odometer: 100.01))
        #expect((await store.savedValues).count == 1)

        _ = try await coordinator.ingest(observation(11_000, speedKPH: 8, odometer: 100.02))
        #expect((await store.savedValues).count == 2)
    }

    @Test("disconnect and stop transitions checkpoint immediately")
    func significantTransitionsPersistImmediately() async throws {
        let store = RecordingRideCheckpointStore()
        let coordinator = try coordinator(store: store, cadenceInterval: 1_000_000)

        _ = try await coordinator.ingest(observation(1_000, speedKPH: 8, odometer: 100))
        _ = try await coordinator.ingest(
            observation(2_000, connection: .disconnected, odometer: 100.01)
        )
        #expect((await store.savedValues).count == 2)

        _ = try await coordinator.ingest(observation(3_000, speedKPH: 0, odometer: 100.01))
        #expect((await store.savedValues).count == 3)
        guard case let .inProgress(checkpoint) = await store.value else {
            Issue.record("ending candidate should remain recoverable")
            return
        }
        #expect(checkpoint.persistedPhase == .endingCandidate)
    }

    @Test("ride end becomes completed-pending before the active recovery journal can be cleared")
    func completionHandoffClosesCrashGap() async throws {
        let store = RecordingRideCheckpointStore()
        let coordinator = try coordinator(store: store, cadenceInterval: 1_000_000)

        _ = try await coordinator.ingest(observation(1_000, speedKPH: 8, odometer: 100))
        _ = try await coordinator.ingest(observation(1_500, speedKPH: 8, odometer: 100.1))
        _ = try await coordinator.ingest(observation(2_000, speedKPH: 0, odometer: 100.1))
        let ended = try await coordinator.ingest(observation(7_000, speedKPH: 0, odometer: 100.1))

        guard case let .rideEnded(evidence) = ended.events.first else {
            Issue.record("expected completed ride")
            return
        }
        #expect(await coordinator.pendingCompletedRideEvidence() == evidence)
        #expect(await store.value == .completedPendingCommit(evidence))

        await #expect(throws: RideCheckpointCoordinatorError.completedRideAwaitingCommit(fixedSessionID)) {
            _ = try await coordinator.ingest(observation(8_000, speedKPH: 0))
        }
        await #expect(throws: RideCheckpointCoordinatorError.noMatchingPendingCompletion) {
            try await coordinator.acknowledgeCompletedRideCommitted(sessionID: UUID())
        }

        try await coordinator.acknowledgeCompletedRideCommitted(sessionID: fixedSessionID)
        #expect(await coordinator.pendingCompletedRideEvidence() == nil)
        #expect(await store.value == nil)
        #expect(await store.clearCount == 1)
    }

    @Test("failed durable ride-start write leaves engine unchanged and the same observation retryable")
    func rideStartSaveFailureIsTransactional() async throws {
        let store = RecordingRideCheckpointStore()
        await store.failNextSave()
        let coordinator = try coordinator(store: store)
        let start = try observation(1_000, speedKPH: 8, odometer: 100)

        await #expect(throws: RecordingRideCheckpointStoreError.injectedFailure) {
            _ = try await coordinator.ingest(start)
        }
        #expect(await coordinator.currentPhase() == .idle)

        let retry = try await coordinator.ingest(start)
        guard case .active = retry.phase else {
            Issue.record("same observation must remain retryable after failed save")
            return
        }
    }

    @Test("failed completion handoff leaves ending state retryable instead of losing the ride")
    func completionSaveFailureIsTransactional() async throws {
        let store = RecordingRideCheckpointStore()
        let coordinator = try coordinator(store: store, cadenceInterval: 1_000_000)
        _ = try await coordinator.ingest(observation(1_000, speedKPH: 8, odometer: 100))
        _ = try await coordinator.ingest(observation(1_500, speedKPH: 8, odometer: 100.1))
        _ = try await coordinator.ingest(observation(2_000, speedKPH: 0, odometer: 100.1))
        let endingPhase = await coordinator.currentPhase()
        await store.failNextSave()
        let finalStop = try observation(7_000, speedKPH: 0, odometer: 100.1)

        await #expect(throws: RecordingRideCheckpointStoreError.injectedFailure) {
            _ = try await coordinator.ingest(finalStop)
        }
        #expect(await coordinator.currentPhase() == endingPhase)
        #expect(await coordinator.pendingCompletedRideEvidence() == nil)

        let retry = try await coordinator.ingest(finalStop)
        guard case let .rideEnded(evidence) = retry.events.first else {
            Issue.record("completion should succeed when the exact observation is retried")
            return
        }
        #expect(await store.value == .completedPendingCommit(evidence))
    }

    @Test("failed completion acknowledgement keeps the pending handoff blocked until journal clear succeeds")
    func completionClearFailurePreservesPendingHandoff() async throws {
        let evidence = try completedEvidence()
        let store = RecordingRideCheckpointStore(value: .completedPendingCommit(evidence))
        let coordinator = try await RideCheckpointCoordinator.restoring(
            policy: try policy(),
            store: store,
            cadence: try cadence(),
            recoveredAtUptimeNanoseconds: 50_000,
            recoveredAtDate: epoch.addingTimeInterval(50)
        )
        await store.failNextClear()

        await #expect(throws: RecordingRideCheckpointStoreError.injectedFailure) {
            try await coordinator.acknowledgeCompletedRideCommitted(sessionID: evidence.sessionID)
        }
        #expect(await coordinator.pendingCompletedRideEvidence() == evidence)
        #expect(await store.value == .completedPendingCommit(evidence))

        try await coordinator.acknowledgeCompletedRideCommitted(sessionID: evidence.sessionID)
        #expect(await coordinator.pendingCompletedRideEvidence() == nil)
        #expect(await store.value == nil)
    }

    @Test("in-progress journal restores the same ride as temporarily disconnected")
    func inProgressRestore() async throws {
        let checkpoint = try inProgressCheckpoint()
        let store = RecordingRideCheckpointStore(value: .inProgress(checkpoint))
        let coordinator = try await RideCheckpointCoordinator.restoring(
            policy: try policy(),
            store: store,
            cadence: try cadence(),
            recoveredAtUptimeNanoseconds: 50_000,
            recoveredAtDate: epoch.addingTimeInterval(50)
        )

        guard case let .temporarilyDisconnected(disconnected) = await coordinator.currentPhase() else {
            Issue.record("recovered ride must wait for fresh movement evidence")
            return
        }
        #expect(disconnected.session.id == checkpoint.sessionID)
        #expect(disconnected.session.continuity == .recoveredCheckpoint)
        #expect(disconnected.session.beganAtUptimeNanoseconds == nil)
    }

    @Test("completed-pending journal survives relaunch and blocks a new ride until history acknowledges it")
    func pendingCompletionRestore() async throws {
        let evidence = try completedEvidence()
        let store = RecordingRideCheckpointStore(value: .completedPendingCommit(evidence))
        let coordinator = try await RideCheckpointCoordinator.restoring(
            policy: try policy(),
            store: store,
            cadence: try cadence(),
            recoveredAtUptimeNanoseconds: 50_000,
            recoveredAtDate: epoch.addingTimeInterval(50)
        )

        #expect(await coordinator.pendingCompletedRideEvidence() == evidence)
        await #expect(throws: RideCheckpointCoordinatorError.completedRideAwaitingCommit(evidence.sessionID)) {
            _ = try await coordinator.ingest(observation(51_000, speedKPH: 8))
        }

        try await coordinator.acknowledgeCompletedRideCommitted(sessionID: evidence.sessionID)
        #expect(await coordinator.pendingCompletedRideEvidence() == nil)
        #expect(await coordinator.currentPhase() == .idle)
    }

    @Test("atomic journal round-trips completed-pending handoff records")
    func atomicStoreRoundTripsCompletedPending() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("nembra-completion-handoff-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AtomicRideCheckpointStore(directoryURL: directory)
        let evidence = try completedEvidence()

        try await store.save(.completedPendingCommit(evidence))
        #expect(try await store.load() == .completedPendingCommit(evidence))
    }
}
