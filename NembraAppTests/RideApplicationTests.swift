import Dispatch
import SwiftData
import XCTest
@testable import Nembra

final class RideApplicationTests: XCTestCase {
    func testSwiftDataHistoryStorePersistsExactIdempotentRecord() async throws {
        let directory = temporaryDirectory(name: "history")
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("RideHistory.store")

        let sessionID = UUID()
        let record = RideHistoryRecord(
            evidence: try completedEvidence(
                sessionID: sessionID,
                endingOdometerKilometers: 101.25
            )
        )

        do {
            let container = try RidePersistenceFactory.makeHistoryContainer(storeURL: storeURL)
            let store = SwiftDataRideHistoryStore(modelContainer: container)
            let inserted = try await store.commit(record)
            let duplicate = try await store.commit(record)
            let storedRecord = try await store.record(sessionID: sessionID)
            XCTAssertEqual(inserted, .inserted)
            XCTAssertEqual(duplicate, .alreadyPresent)
            XCTAssertEqual(storedRecord, record)
        }

        do {
            let reopenedContainer = try RidePersistenceFactory.makeHistoryContainer(storeURL: storeURL)
            let reopenedStore = SwiftDataRideHistoryStore(modelContainer: reopenedContainer)
            let reopenedRecord = try await reopenedStore.record(sessionID: sessionID)
            XCTAssertEqual(reopenedRecord, record)

            let conflicting = RideHistoryRecord(
                evidence: try completedEvidence(
                    sessionID: sessionID,
                    endingOdometerKilometers: 101.5
                )
            )
            do {
                _ = try await reopenedStore.commit(conflicting)
                XCTFail("The same ride UUID with different evidence must never overwrite history.")
            } catch let error as RideHistoryStoreError {
                XCTAssertEqual(error, .sessionConflict(sessionID))
            }
        }
    }

    func testSwiftDataHistoryRejectsPayloadWhoseSessionIdentityDoesNotMatchRow() async throws {
        let directory = temporaryDirectory(name: "history-corruption")
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("RideHistory.store")
        let requestedSessionID = UUID()
        let payloadSessionID = UUID()

        let container = try RidePersistenceFactory.makeHistoryContainer(storeURL: storeURL)
        let corruptPayload = try JSONEncoder().encode(
            RideHistoryRecord(
                evidence: try completedEvidence(
                    sessionID: payloadSessionID,
                    endingOdometerKilometers: 101.25
                )
            )
        )
        let context = ModelContext(container)
        context.insert(
            StoredRideHistoryRecord(
                sessionID: requestedSessionID,
                payload: corruptPayload
            )
        )
        try context.save()

        let store = SwiftDataRideHistoryStore(modelContainer: container)
        do {
            _ = try await store.record(sessionID: requestedSessionID)
            XCTFail("A SwiftData row must never return durable ride evidence for a different session UUID.")
        } catch let error as RideHistoryPersistenceError {
            XCTAssertEqual(error, .corruptRecord(requestedSessionID))
        }
    }

    @MainActor
    func testStateOnlyAcknowledgementsDoNotReplayRawSpeedEvidence() async throws {
        let directory = temporaryDirectory(name: "single-use-speed")
        defer { try? FileManager.default.removeItem(at: directory) }

        let persistence = try RidePersistenceFactory.make(
            scope: .simulation(scenario: .connectedStopped, namespace: "single-use-speed"),
            baseDirectoryURL: directory
        )
        let configuration = RideApplicationConfiguration(
            detectionPolicy: try RideDetectionPolicy(
                candidateSpeedKilometersPerHour: 1,
                confirmationSpeedKilometersPerHour: 3,
                confirmationDurationNanoseconds: 250_000_000,
                confirmationOdometerDeltaKilometers: 10,
                confirmationGPSDistanceMeters: 10_000,
                endingDurationNanoseconds: 450_000_000,
                maximumSpeedSampleAgeNanoseconds: 1_000_000_000
            ),
            checkpointCadence: try RideCheckpointCadence(
                minimumIntervalNanoseconds: 100_000_000
            )
        )

        let initialState = SimulatedScooterService.state(for: .connectedStopped)
        let service = SimulatedScooterService(
            initialState: initialState,
            commandLatencyNanoseconds: 0
        )
        let store = RideApplicationStore(
            service: service,
            initialState: initialState,
            configuration: configuration,
            checkpointStore: persistence.checkpointStore,
            historyStore: persistence.historyStore
        )
        await store.start()

        await service.simulateRide(speedKilometersPerHour: 12, elapsedSeconds: 0)
        try await waitUntil("One raw packet should start only a ride candidate.") {
            store.status == .candidate
        }

        try await Task.sleep(nanoseconds: 300_000_000)
        try await service.setHeadlight(true)
        try await Task.sleep(nanoseconds: 75_000_000)

        XCTAssertEqual(
            store.status,
            .candidate,
            "A headlight acknowledgement must not replay the previous speed packet and confirm a ride."
        )
        XCTAssertNil(store.activeSessionID)

        await service.simulateRide(speedKilometersPerHour: 12, elapsedSeconds: 0)
        try await waitUntil("A second fresh raw packet may confirm the candidate after the duration gate.") {
            store.status == .active
        }
        XCTAssertNotNil(store.activeSessionID)
        store.stop()
    }

    @MainActor
    func testRawSpeedArrivingBeforeConnectedStateIsConsumedOnceWhenStateCatchesUp() async throws {
        let directory = temporaryDirectory(name: "cross-stream-reconnect")
        defer { try? FileManager.default.removeItem(at: directory) }

        let persistence = try RidePersistenceFactory.make(
            scope: .simulation(scenario: .reconnecting, namespace: "cross-stream-reconnect"),
            baseDirectoryURL: directory
        )
        let configuration = try RideApplicationConfiguration.simulatorQA()
        let reconnectingState = SimulatedScooterService.state(for: .reconnecting)
        let service = ControlledScooterService(initialState: reconnectingState)
        let store = RideApplicationStore(
            service: service,
            initialState: reconnectingState,
            configuration: configuration,
            checkpointStore: persistence.checkpointStore,
            historyStore: persistence.historyStore
        )
        await store.start()
        XCTAssertEqual(store.status, .idle)

        // Deliberately invert the two independent service streams: the raw
        // packet reaches RideApplicationStore before its connected state does.
        try await service.emitSpeed(kilometersPerHour: 12)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(
            store.status,
            .idle,
            "A packet observed while the state stream still says reconnecting must not be assigned to that unconfirmed connection."
        )

        var connectedState = reconnectingState
        connectedState.connection = .connected
        connectedState.connectionIssue = nil
        connectedState.lastUpdated = .now
        await service.emitState(connectedState)

        try await waitUntil("The buffered fresh packet should be consumed exactly once when the connected state catches up.") {
            store.status == .active
        }
        XCTAssertNotNil(store.activeSessionID)
        store.stop()
    }

    @MainActor
    func testRideApplicationRestoresSameSessionAndCommitsHistory() async throws {
        let directory = temporaryDirectory(name: "recovery")
        defer { try? FileManager.default.removeItem(at: directory) }

        let persistence = try RidePersistenceFactory.make(
            scope: .simulation(scenario: .riding, namespace: "recovery-test"),
            baseDirectoryURL: directory
        )
        let configuration = try RideApplicationConfiguration.simulatorQA()

        let firstState = SimulatedScooterService.state(for: .connectedStopped)
        let firstService = SimulatedScooterService(initialState: firstState)
        var firstStore: RideApplicationStore? = RideApplicationStore(
            service: firstService,
            initialState: firstState,
            configuration: configuration,
            checkpointStore: persistence.checkpointStore,
            historyStore: persistence.historyStore
        )
        await firstStore?.start()

        await firstService.simulateRide(speedKilometersPerHour: 12, elapsedSeconds: 1)
        try await waitUntil("The explicit QA ride should become active.") {
            firstStore?.status == .active
        }
        let sessionID = try XCTUnwrap(firstStore?.activeSessionID)

        firstStore?.stop()
        firstStore = nil

        let durableCheckpoint = try await persistence.checkpointStore.load()
        guard case let .inProgress(checkpoint)? = durableCheckpoint else {
            return XCTFail("An active automatic ride must have durable recovery evidence.")
        }
        XCTAssertEqual(checkpoint.sessionID, sessionID)

        let recoveredState = SimulatedScooterService.state(for: .reconnecting)
        let recoveredService = SimulatedScooterService(initialState: recoveredState)
        let recoveredStore = RideApplicationStore(
            service: recoveredService,
            initialState: recoveredState,
            configuration: configuration,
            checkpointStore: persistence.checkpointStore,
            historyStore: persistence.historyStore
        )
        await recoveredStore.start()

        XCTAssertEqual(recoveredStore.activeSessionID, sessionID)
        XCTAssertEqual(recoveredStore.continuity, .recoveredCheckpoint)
        XCTAssertEqual(recoveredStore.status, .temporarilyDisconnected)

        await recoveredService.simulateReconnected()
        await recoveredService.simulateRide(speedKilometersPerHour: 12, elapsedSeconds: 0)
        try await waitUntil("Fresh authoritative speed should resume the recovered ride.") {
            recoveredStore.status == .active
        }
        XCTAssertEqual(recoveredStore.activeSessionID, sessionID)
        XCTAssertEqual(recoveredStore.continuity, .recoveredCheckpoint)
        XCTAssertEqual(recoveredStore.statusText, "Ride resumed")

        await recoveredService.simulateRide(speedKilometersPerHour: 0, elapsedSeconds: 0)
        try await Task.sleep(nanoseconds: 550_000_000)
        await recoveredService.simulateRide(speedKilometersPerHour: 0, elapsedSeconds: 0)

        try await waitUntil("Completed ride evidence should be committed and acknowledged.") {
            recoveredStore.lastCompletedSessionID == sessionID && recoveredStore.status == .idle
        }

        let clearedCheckpoint = try await persistence.checkpointStore.load()
        let committedRecord = try await persistence.historyStore.record(sessionID: sessionID)
        XCTAssertNil(clearedCheckpoint)
        XCTAssertEqual(committedRecord?.sessionID, sessionID)
        recoveredStore.stop()
    }

    @MainActor
    func testOrdinaryRuntimeKeepsAutomaticRideDetectionDisabled() {
        let runtime = AppBootstrap.makeRuntime(
            arguments: ["Nembra"],
            environment: [:]
        )
        XCTAssertEqual(runtime.rideStore.status, .disabled)
    }

    private func completedEvidence(
        sessionID: UUID,
        endingOdometerKilometers: Double
    ) throws -> CompletedRideEvidence {
        try CompletedRideEvidence(
            sessionID: sessionID,
            beganAtDate: Date(timeIntervalSince1970: 1_000),
            confirmedAtDate: Date(timeIntervalSince1970: 1_002),
            endedAtDate: Date(timeIntervalSince1970: 1_060),
            startingOdometerKilometers: 100,
            endingOdometerKilometers: endingOdometerKilometers,
            qualityScreenedGPSDistanceMeters: 1_900,
            continuity: .uninterruptedProcess
        )
    }

    private func temporaryDirectory(name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("Nembra-\(name)-\(UUID().uuidString)", isDirectory: true)
    }

    @MainActor
    private func waitUntil(
        _ failureMessage: String,
        timeoutNanoseconds: UInt64 = 3_000_000_000,
        condition: @MainActor () -> Bool
    ) async throws {
        let start = DispatchTime.now().uptimeNanoseconds
        while DispatchTime.now().uptimeNanoseconds - start < timeoutNanoseconds {
            if condition() { return }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTFail(failureMessage)
    }
}

private actor ControlledScooterService: ScooterService {
    nonisolated let profile = VehicleProfile.maxshotV1SPro

    private var state: VehicleState
    private var stateContinuation: AsyncStream<VehicleState>.Continuation?
    private var speedContinuation: AsyncStream<SpeedTelemetrySample>.Continuation?

    init(initialState: VehicleState) {
        state = initialState
    }

    func stateUpdates() async -> AsyncStream<VehicleState> {
        let pair = AsyncStream<VehicleState>.makeStream()
        stateContinuation = pair.continuation
        return pair.stream
    }

    func speedTelemetryUpdates() async -> AsyncStream<SpeedTelemetrySample> {
        let pair = AsyncStream<SpeedTelemetrySample>.makeStream()
        speedContinuation = pair.continuation
        return pair.stream
    }

    func snapshot() async -> VehicleState {
        state
    }

    func emitState(_ newState: VehicleState) {
        state = newState
        stateContinuation?.yield(newState)
    }

    func emitSpeed(kilometersPerHour: Double) throws {
        let sample = try SpeedTelemetrySample(
            source: .scooterBluetooth,
            provenance: .absoluteMeasurement,
            metersPerSecond: kilometersPerHour / 3.6,
            receivedAtUptimeNanoseconds: DispatchTime.now().uptimeNanoseconds,
            receivedAtDate: .now,
            measurementDate: nil,
            speedAccuracyMetersPerSecond: nil
        )
        speedContinuation?.yield(sample)
    }

    func connect() async {
        var connected = state
        connected.connection = .connected
        connected.connectionIssue = nil
        connected.lastUpdated = .now
        emitState(connected)
    }

    func disconnect() async {
        var disconnected = state
        disconnected.connection = .disconnected
        disconnected.lastUpdated = .now
        emitState(disconnected)
    }

    func setHeadlight(_ enabled: Bool) async throws {}
    func setLocked(_ locked: Bool) async throws {}
    func setCruise(_ enabled: Bool) async throws {}
    func setRideMode(_ mode: RideMode) async throws {}
    func setStartMode(_ mode: StartMode) async throws {}
    func setSpeedLimit(kilometersPerHour: Int, slot: SpeedLimitSlot) async throws {}
}
