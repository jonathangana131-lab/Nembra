import Dispatch
import Foundation
import XCTest
@testable import Nembra

final class RideLocationRecoveryHardeningTests: XCTestCase {
    func testTrailingSourceIssueMakesCompletedRoutePartialWithoutLaterPoint() async throws {
        let directory = temporaryDirectory("trailing-gap")
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try RidePersistenceFactory.makeRouteContainer(
            storeURL: directory.appendingPathComponent("RideRoutes.store")
        )
        let routeStore = SwiftDataRideRouteStore(modelContainer: container)
        let source = HardeningLocationSource()
        let sessionID = UUID()
        let coordinator = try RideLocationCaptureCoordinator(
            source: source,
            qualityPolicy: try testPolicy(),
            routeStore: routeStore,
            sessionScopedEvidenceAdmissionSink: { _, _, _ in true }
        )

        try await coordinator.begin(sessionID: sessionID, requestedCoverage: .complete)
        await source.emit(event(try sample(45.638700, -122.661500, 1_000_000_000, 0)))
        await source.emit(event(try sample(45.638790, -122.661500, 2_000_000_000, 1)))
        await source.emit(
            RideLocationSourceEvent(
                sample: nil,
                issue: .locationUnavailable,
                isStationary: false,
                receivedAtUptimeNanoseconds: 3_000_000_000
            )
        )

        let summary = try await coordinator.finish()
        let manifest = try XCTUnwrap(summary.routeManifest)
        XCTAssertEqual(manifest.coverage, .partial)
        XCTAssertEqual(manifest.pointCount, 2)
        XCTAssertEqual(manifest.segmentCount, 1)
        XCTAssertEqual(summary.acceptedPointCount, 2)
    }

    @MainActor
    func testEndingCandidateZeroDistanceLocationDoesNotSelfAwaitCompletionBarrier() async throws {
        let directory = temporaryDirectory("zero-distance-deadlock")
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = try RidePersistenceFactory.make(
            scope: .simulation(scenario: .connectedStopped, namespace: "zero-distance-deadlock"),
            baseDirectoryURL: directory
        )
        let initialState = SimulatedScooterService.state(for: .connectedStopped)
        let service = SimulatedScooterService(initialState: initialState, commandLatencyNanoseconds: 0)
        let rideStore = RideApplicationStore(
            service: service,
            initialState: initialState,
            configuration: try RideApplicationConfiguration.simulatorQA(),
            checkpointStore: persistence.checkpointStore,
            historyStore: persistence.historyStore
        )
        let source = HardeningLocationSource()
        let admissions = HardeningAdmissionCollector()
        let coordinator = try RideLocationCaptureCoordinator(
            source: source,
            qualityPolicy: try testPolicy(),
            routeStore: persistence.routeStore,
            sessionScopedEvidenceAdmissionSink: { [weak rideStore] sessionID, meters, uptime in
                await admissions.append(sessionID: sessionID, meters: meters, uptime: uptime)
                guard let rideStore else { return false }
                return await rideStore.admitQualityScreenedLocationEvidence(
                    distanceDeltaMeters: meters,
                    receivedAtUptimeNanoseconds: uptime,
                    for: sessionID
                )
            }
        )
        rideStore.setRideCompletionBarrier { sessionID in
            let summary = try await coordinator.finish()
            XCTAssertEqual(summary.sessionID, sessionID)
        }
        await rideStore.start()

        await service.simulateRide(speedKilometersPerHour: 12, elapsedSeconds: 0)
        try await waitUntil("Ride should become active.") { rideStore.status == .active }
        let sessionID = try XCTUnwrap(rideStore.activeSessionID)
        try await coordinator.begin(sessionID: sessionID, requestedCoverage: .partial)

        let firstUptime = DispatchTime.now().uptimeNanoseconds
        await source.emit(event(try sample(45.638700, -122.661500, firstUptime, 0)))
        try await Task.sleep(nanoseconds: 50_000_000)
        await service.simulateRide(speedKilometersPerHour: 0, elapsedSeconds: 0)
        try await waitUntil("Zero speed should enter ending candidate.") {
            rideStore.status == .endingCandidate
        }
        try await Task.sleep(nanoseconds: 550_000_000)

        await source.emit(event(try sample(
            45.638700,
            -122.661500,
            max(firstUptime + 1, DispatchTime.now().uptimeNanoseconds),
            1
        )))
        try await Task.sleep(nanoseconds: 75_000_000)
        XCTAssertEqual(rideStore.status, .endingCandidate)
        let capturedAdmissions = await admissions.values()
        XCTAssertGreaterThanOrEqual(capturedAdmissions.count, 2)
        XCTAssertNil(
            capturedAdmissions.last?.meters,
            "An exact-zero location displacement is identity-only and must not drive ride ending."
        )

        await service.simulateRide(speedKilometersPerHour: 0, elapsedSeconds: 0)
        try await waitUntil("Independent scooter evidence should complete without a capture self-await.") {
            rideStore.status == .idle && rideStore.lastCompletedSessionID == sessionID
        }
        rideStore.stop()
    }

    @MainActor
    func testCheckpointCoordinatorAccessGateSerializesOverlappingPersistenceAwaits() async throws {
        let directory = temporaryDirectory("ingest-single-flight")
        defer { try? FileManager.default.removeItem(at: directory) }
        let historyContainer = try RidePersistenceFactory.makeHistoryContainer(
            storeURL: directory.appendingPathComponent("RideHistory.store")
        )
        let historyStore = SwiftDataRideHistoryStore(modelContainer: historyContainer)
        let checkpointStore = BlockingRideCheckpointStore()
        let initialState = SimulatedScooterService.state(for: .connectedStopped)
        let service = SimulatedScooterService(initialState: initialState, commandLatencyNanoseconds: 0)
        let rideStore = RideApplicationStore(
            service: service,
            initialState: initialState,
            configuration: try RideApplicationConfiguration.simulatorQA(),
            checkpointStore: checkpointStore,
            historyStore: historyStore
        )
        await rideStore.start()

        await service.simulateRide(speedKilometersPerHour: 2, elapsedSeconds: 0)
        try await waitForMutationStart(checkpointStore)
        await service.simulateRide(speedKilometersPerHour: 12, elapsedSeconds: 0)
        try await Task.sleep(nanoseconds: 100_000_000)

        let peakBeforeRelease = await checkpointStore.maximumConcurrentMutations()
        XCTAssertEqual(peakBeforeRelease, 1)
        await checkpointStore.releaseBlockedMutation()
        try await waitUntil("Serialized candidate then confirmation should produce one active ride.") {
            rideStore.status == .active
        }
        let peakAfterRelease = await checkpointStore.maximumConcurrentMutations()
        XCTAssertEqual(peakAfterRelease, 1)
        XCTAssertNotNil(rideStore.activeSessionID)
        rideStore.stop()
    }

    @MainActor
    func testStartupPendingCompletionRetriesInSameProcessAfterTransientBarrierFailure() async throws {
        let directory = temporaryDirectory("startup-retry")
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = try RidePersistenceFactory.make(
            scope: .simulation(scenario: .connectedStopped, namespace: "startup-retry"),
            baseDirectoryURL: directory
        )
        let initialState = SimulatedScooterService.state(for: .connectedStopped)

        let firstService = SimulatedScooterService(initialState: initialState, commandLatencyNanoseconds: 0)
        let firstStore = RideApplicationStore(
            service: firstService,
            initialState: initialState,
            configuration: try RideApplicationConfiguration.simulatorQA(),
            checkpointStore: persistence.checkpointStore,
            historyStore: persistence.historyStore
        )
        firstStore.setRideCompletionBarrier { _ in throw HardeningTestError.transientFailure }
        await firstStore.start()
        await firstService.simulateRide(speedKilometersPerHour: 12, elapsedSeconds: 0)
        try await waitUntil("First process should start a ride.") { firstStore.status == .active }
        let sessionID = try XCTUnwrap(firstStore.activeSessionID)
        await firstService.simulateRide(speedKilometersPerHour: 0, elapsedSeconds: 0)
        try await Task.sleep(nanoseconds: 550_000_000)
        await firstService.simulateRide(speedKilometersPerHour: 0, elapsedSeconds: 0)
        try await waitUntil("Failed barrier should leave completed ride pending.") {
            firstStore.status == .persistenceUnavailable
        }
        firstStore.stop()

        let retryBarrier = FailOnceBarrier()
        let secondService = SimulatedScooterService(initialState: initialState, commandLatencyNanoseconds: 0)
        let secondStore = RideApplicationStore(
            service: secondService,
            initialState: initialState,
            configuration: try RideApplicationConfiguration.simulatorQA(),
            checkpointStore: persistence.checkpointStore,
            historyStore: persistence.historyStore
        )
        secondStore.setRideCompletionBarrier { _ in try await retryBarrier.run() }
        await secondStore.start()
        XCTAssertEqual(secondStore.status, .persistenceUnavailable)
        let pendingAfterStartupFailure = try await persistence.checkpointStore.load()
        XCTAssertNotNil(pendingAfterStartupFailure)

        // start() already subscribed to live evidence before the transient
        // startup failure. This sample retries the exact durable pending handoff.
        await secondService.simulateRide(speedKilometersPerHour: 0, elapsedSeconds: 0)
        try await waitUntil("A later live sample should retry without relaunch.") {
            secondStore.status == .idle && secondStore.lastCompletedSessionID == sessionID
        }
        let committed = try await persistence.historyStore.record(sessionID: sessionID)
        let cleared = try await persistence.checkpointStore.load()
        XCTAssertNotNil(committed)
        XCTAssertNil(cleared)
        let attempts = await retryBarrier.attemptCount()
        XCTAssertGreaterThanOrEqual(attempts, 2)
        secondStore.stop()
    }

    func testCorruptNegativeAcceptedPointCountFailsClosedAtDecodeBoundary() async throws {
        let directory = temporaryDirectory("corrupt-outcome")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let sessionID = UUID()
        let raw = "{\"acceptedPointCount\":-1,\"sessionID\":\"\(sessionID.uuidString)\",\"state\":\"recorded\"}"
        try Data(raw.utf8).write(
            to: directory.appendingPathComponent("\(sessionID.uuidString).json"),
            options: .atomic
        )
        let store = AtomicRideRouteOutcomeStore(directoryURL: directory)

        do {
            _ = try await store.record(sessionID: sessionID)
            XCTFail("Persisted invariant violations must not decode as trusted route truth.")
        } catch RideRouteOutcomeStoreError.corruptRecord(let corruptID) {
            XCTAssertEqual(corruptID, sessionID)
        }
    }

    func testRecoveredRouteDoesNotInferApplicationAdmissionCountFromManifestPoints() async throws {
        let directory = temporaryDirectory("unknown-count")
        defer { try? FileManager.default.removeItem(at: directory) }
        let routeContainer = try RidePersistenceFactory.makeRouteContainer(
            storeURL: directory.appendingPathComponent("RideRoutes.store")
        )
        let routeStore = SwiftDataRideRouteStore(modelContainer: routeContainer)
        let outcomeStore = AtomicRideRouteOutcomeStore(
            directoryURL: directory.appendingPathComponent("RouteOutcomes", isDirectory: true)
        )
        let sessionID = UUID()
        let point = try RideRoutePoint(
            sequence: 0,
            latitude: 37.334900,
            longitude: -122.009020,
            capturedAtDate: Date(timeIntervalSince1970: 1_700_000_000),
            horizontalAccuracyMeters: 4
        )
        _ = try await routeStore.commit(
            try RideRouteChunk(
                id: RideRouteChunkID(sessionID: sessionID, segmentIndex: 0, chunkIndex: 0),
                points: [point]
            )
        )
        let reconciler = RideRouteOutcomeReconciler(
            outcomeStore: outcomeStore,
            draftFinalizer: RideRouteDraftFinalizer(routeStore: routeStore)
        )

        try await reconciler.reconcile(sessionID: sessionID)
        let outcome = try await outcomeStore.record(sessionID: sessionID)
        XCTAssertEqual(outcome?.state, .recorded)
        XCTAssertNil(outcome?.acceptedPointCount)
    }

    @MainActor
    func testRuntimeStartupRepairsPostHistoryStorageFailureWithoutPendingCheckpoint() async throws {
        let directory = temporaryDirectory("post-history-repair")
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = try RidePersistenceFactory.make(
            scope: .simulation(scenario: .connectedStopped, namespace: "post-history-repair"),
            baseDirectoryURL: directory
        )
        let routeStore = try XCTUnwrap(persistence.routeStore)
        let sessionID = UUID()
        let point = try RideRoutePoint(
            sequence: 0,
            latitude: 37.334900,
            longitude: -122.009020,
            capturedAtDate: Date(timeIntervalSince1970: 1_700_000_000),
            horizontalAccuracyMeters: 4
        )
        _ = try await routeStore.commit(
            try RideRouteChunk(
                id: RideRouteChunkID(sessionID: sessionID, segmentIndex: 0, chunkIndex: 0),
                points: [point]
            )
        )
        _ = try await persistence.routeOutcomeStore.commit(
            try RideRouteOutcomeRecord(
                sessionID: sessionID,
                state: .storageFailed,
                acceptedPointCount: 1
            )
        )
        let checkpointBeforeRuntime = try await persistence.checkpointStore.load()
        XCTAssertNil(checkpointBeforeRuntime, "Repair must not depend on a pending ride checkpoint.")

        let initialState = SimulatedScooterService.state(for: .connectedStopped)
        let service = SimulatedScooterService(initialState: initialState, commandLatencyNanoseconds: 0)
        let runtime = AppRuntime(
            vehicleStore: VehicleStore(
                service: service,
                initialState: initialState,
                shouldAutoConnectOnStart: false,
                speedInstrumentInterpolationPolicy: .disabled
            ),
            rideStore: RideApplicationStore(
                service: service,
                initialState: initialState,
                configuration: nil,
                checkpointStore: nil,
                historyStore: nil
            ),
            rideHistoryStore: RideHistoryPresentationStore(historyStore: persistence.historyStore),
            rideRouteStore: RideRoutePresentationStore(
                routeStore: routeStore,
                outcomeStore: persistence.routeOutcomeStore
            ),
            simulatorService: service,
            simulationScenario: nil,
            simulatorAutoCompletesRide: false,
            rideLocationCaptureCoordinator: nil,
            rideRouteOutcomeReconciler: RideRouteOutcomeReconciler(
                outcomeStore: persistence.routeOutcomeStore,
                draftFinalizer: RideRouteDraftFinalizer(routeStore: routeStore)
            )
        )

        await runtime.start()
        let repaired = try await persistence.routeOutcomeStore.record(sessionID: sessionID)
        let manifest = try await routeStore.manifest(sessionID: sessionID)
        XCTAssertEqual(repaired?.state, .recorded)
        XCTAssertEqual(repaired?.acceptedPointCount, 1)
        XCTAssertEqual(manifest?.coverage, .partial)
    }

    @MainActor
    func testMissingRouteDatabaseStillSurfacesRecordedAndUnknownOutcomeTruth() async throws {
        let directory = temporaryDirectory("missing-route-db")
        defer { try? FileManager.default.removeItem(at: directory) }
        let outcomeStore = AtomicRideRouteOutcomeStore(directoryURL: directory)
        let presentation = RideRoutePresentationStore(
            routeStore: nil,
            outcomeStore: outcomeStore,
            startupPersistenceError: "Route database unavailable."
        )

        let recordedSession = UUID()
        _ = try await outcomeStore.commit(
            try RideRouteOutcomeRecord(
                sessionID: recordedSession,
                state: .recorded,
                acceptedPointCount: nil
            )
        )
        await presentation.refresh(sessionID: recordedSession)
        XCTAssertEqual(presentation.status(sessionID: recordedSession), .failed)

        let unknownSession = UUID()
        _ = try await outcomeStore.commit(
            try RideRouteOutcomeRecord(
                sessionID: unknownSession,
                state: .unknown,
                acceptedPointCount: nil
            )
        )
        await presentation.refresh(sessionID: unknownSession)
        XCTAssertEqual(presentation.status(sessionID: unknownSession), .unavailable)
        XCTAssertEqual(
            presentation.errorMessage(sessionID: unknownSession),
            "Route recording outcome is unknown for this recovered ride."
        )
    }

    private func testPolicy() throws -> RideLocationQualityPolicy {
        try RideLocationQualityPolicy(
            maximumHorizontalAccuracyMeters: 20,
            maximumMeasurementAgeSeconds: 5,
            maximumFutureMeasurementSkewSeconds: 1,
            maximumContinuityGapNanoseconds: 5_000_000_000,
            maximumImpliedSpeedMetersPerSecond: 25,
            allowsSoftwareSimulatedLocations: true
        )
    }

    private func event(_ sample: RideLocationSample) -> RideLocationSourceEvent {
        RideLocationSourceEvent(sample: sample, issue: nil, isStationary: false)
    }

    private func sample(
        _ latitude: Double,
        _ longitude: Double,
        _ uptime: UInt64,
        _ dateOffset: TimeInterval
    ) throws -> RideLocationSample {
        let date = Date(timeIntervalSince1970: 1_700_000_000 + dateOffset)
        return try RideLocationSample(
            latitude: latitude,
            longitude: longitude,
            sourceMeasurementDate: date,
            receivedAtDate: date,
            receivedAtUptimeNanoseconds: uptime,
            horizontalAccuracyMeters: 4,
            isAccuracyLimited: false,
            isSimulatedBySoftware: true
        )
    }

    private func temporaryDirectory(_ name: String) -> URL {
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

    private func waitForMutationStart(
        _ store: BlockingRideCheckpointStore,
        timeoutNanoseconds: UInt64 = 2_000_000_000
    ) async throws {
        let start = DispatchTime.now().uptimeNanoseconds
        while DispatchTime.now().uptimeNanoseconds - start < timeoutNanoseconds {
            if await store.hasStartedMutation() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for the checkpoint mutation gate.")
    }
}

private enum HardeningTestError: Error {
    case transientFailure
}

private actor FailOnceBarrier {
    private var attempts = 0
    func run() throws {
        attempts += 1
        if attempts == 1 { throw HardeningTestError.transientFailure }
    }
    func attemptCount() -> Int { attempts }
}

private actor BlockingRideCheckpointStore: RideCheckpointStore {
    private var checkpoint: RideDurableCheckpoint?
    private var shouldBlockNextMutation = true
    private var blockedContinuation: CheckedContinuation<Void, Never>?
    private var startedMutation = false
    private var activeMutations = 0
    private var peakConcurrentMutations = 0

    func load() async throws -> RideDurableCheckpoint? { checkpoint }

    func save(_ checkpoint: RideDurableCheckpoint) async throws {
        await beginMutationIfNeeded()
        self.checkpoint = checkpoint
        endMutation()
    }

    func clear() async throws {
        await beginMutationIfNeeded()
        checkpoint = nil
        endMutation()
    }

    func hasStartedMutation() -> Bool { startedMutation }
    func maximumConcurrentMutations() -> Int { peakConcurrentMutations }

    func releaseBlockedMutation() {
        blockedContinuation?.resume()
        blockedContinuation = nil
    }

    private func beginMutationIfNeeded() async {
        activeMutations += 1
        peakConcurrentMutations = max(peakConcurrentMutations, activeMutations)
        startedMutation = true
        guard shouldBlockNextMutation else { return }
        shouldBlockNextMutation = false
        await withCheckedContinuation { continuation in
            blockedContinuation = continuation
        }
    }

    private func endMutation() { activeMutations -= 1 }
}

private actor HardeningLocationSource: RideLocationSource {
    private var continuation: AsyncStream<RideLocationSourceEvent>.Continuation?
    private var started = false

    func events() -> AsyncStream<RideLocationSourceEvent> {
        continuation?.finish()
        let pair = AsyncStream<RideLocationSourceEvent>.makeStream()
        continuation = pair.continuation
        return pair.stream
    }

    func start() { started = true }

    func stop() {
        started = false
        continuation?.finish()
        continuation = nil
    }

    func emit(_ event: RideLocationSourceEvent) {
        guard started else { return }
        continuation?.yield(event)
    }
}

private actor HardeningAdmissionCollector {
    struct Value: Sendable {
        let sessionID: UUID
        let meters: Double?
        let uptime: UInt64
    }
    private var recorded: [Value] = []
    func append(sessionID: UUID, meters: Double?, uptime: UInt64) {
        recorded.append(Value(sessionID: sessionID, meters: meters, uptime: uptime))
    }
    func values() -> [Value] { recorded }
}
