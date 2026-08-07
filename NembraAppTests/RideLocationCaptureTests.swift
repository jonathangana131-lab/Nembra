import Dispatch
import Foundation
import XCTest
@testable import Nembra

final class RideLocationCaptureTests: XCTestCase {
    func testLocationCoordinatorPersistsExplicitGapAndFeedsOnlyContinuousDistance() async throws {
        let directory = temporaryDirectory(name: "location-coordinator")
        defer { try? FileManager.default.removeItem(at: directory) }
        let routeURL = directory.appendingPathComponent("RideRoutes.store")
        let container = try RidePersistenceFactory.makeRouteContainer(storeURL: routeURL)
        let routeStore = SwiftDataRideRouteStore(modelContainer: container)
        let source = TestRideLocationSource()
        let distances = DistanceCollector()
        let sessionID = UUID()

        let coordinator = try RideLocationCaptureCoordinator(
            source: source,
            qualityPolicy: try testPolicy(),
            routeStore: routeStore,
            routeChunkSize: 2
        ) { meters, uptime in
            await distances.append(meters: meters, uptime: uptime)
        }
        try await coordinator.begin(sessionID: sessionID, requestedCoverage: .complete)

        await source.emit(event(sample: try sample(
            latitude: 45.638700,
            longitude: -122.661500,
            uptime: 1_000_000_000,
            dateOffset: 0
        )))
        await source.emit(event(sample: try sample(
            latitude: 45.638790,
            longitude: -122.661500,
            uptime: 2_000_000_000,
            dateOffset: 1
        )))
        await source.emit(
            RideLocationSourceEvent(
                sample: nil,
                issue: .locationUnavailable,
                isStationary: false
            )
        )
        await source.emit(event(sample: try sample(
            latitude: 45.650000,
            longitude: -122.650000,
            uptime: 3_000_000_000,
            dateOffset: 2
        )))
        await source.emit(event(sample: try sample(
            latitude: 45.650090,
            longitude: -122.650000,
            uptime: 4_000_000_000,
            dateOffset: 3
        )))

        let summary = try await coordinator.finish()
        let manifest = try XCTUnwrap(summary.routeManifest)
        XCTAssertEqual(summary.sessionID, sessionID)
        XCTAssertEqual(summary.acceptedPointCount, 4)
        XCTAssertFalse(summary.routePersistenceFailed)
        XCTAssertEqual(manifest.coverage, .partial)
        XCTAssertEqual(manifest.segmentCount, 2)
        XCTAssertEqual(manifest.pointCount, 4)
        XCTAssertEqual(manifest.knownGapCount, 1)
        XCTAssertGreaterThan(summary.qualityScreenedDistanceMeters, 18)
        XCTAssertLessThan(summary.qualityScreenedDistanceMeters, 22)

        let loadedGeometry = try await routeStore.geometry(sessionID: sessionID)
        let geometry = try XCTUnwrap(loadedGeometry)
        XCTAssertEqual(geometry.segments.count, 2)
        XCTAssertEqual(geometry.segments[0].points.count, 2)
        XCTAssertEqual(geometry.segments[1].points.count, 2)
        XCTAssertEqual(geometry.segments[0].points.map(\.sequence), [0, 1])
        XCTAssertEqual(geometry.segments[1].points.map(\.sequence), [2, 3])

        let recordedDistances = await distances.values()
        XCTAssertEqual(recordedDistances.count, 2)
        XCTAssertEqual(recordedDistances.map(\.uptime), [2_000_000_000, 4_000_000_000])
        XCTAssertGreaterThan(recordedDistances.reduce(0) { $0 + $1.meters }, 18)
        XCTAssertLessThan(recordedDistances.reduce(0) { $0 + $1.meters }, 22)
    }

    func testSessionScopedDistanceSinkCarriesCaptureIdentity() async throws {
        let source = TestRideLocationSource()
        let distances = SessionDistanceCollector()
        let sessionID = UUID()
        let coordinator = try RideLocationCaptureCoordinator(
            source: source,
            qualityPolicy: try testPolicy(),
            routeStore: nil,
            sessionScopedDistanceSink: { emittedSessionID, meters, uptime in
                await distances.append(
                    sessionID: emittedSessionID,
                    meters: meters,
                    uptime: uptime
                )
            }
        )
        try await coordinator.begin(sessionID: sessionID, requestedCoverage: .complete)

        await source.emit(event(sample: try sample(
            latitude: 45.638700,
            longitude: -122.661500,
            uptime: 1_000_000_000,
            dateOffset: 0
        )))
        await source.emit(event(sample: try sample(
            latitude: 45.638790,
            longitude: -122.661500,
            uptime: 2_000_000_000,
            dateOffset: 1
        )))

        _ = try await coordinator.finish()
        let recorded = await distances.values()
        XCTAssertEqual(recorded.count, 1)
        XCTAssertEqual(recorded.first?.sessionID, sessionID)
        XCTAssertEqual(recorded.first?.uptime, 2_000_000_000)
    }

    func testMissingRouteStoreDoesNotDiscardScreenedGPSDistance() async throws {
        let source = TestRideLocationSource()
        let distances = DistanceCollector()
        let sessionID = UUID()
        let coordinator = try RideLocationCaptureCoordinator(
            source: source,
            qualityPolicy: try testPolicy(),
            routeStore: nil
        ) { meters, uptime in
            await distances.append(meters: meters, uptime: uptime)
        }
        try await coordinator.begin(sessionID: sessionID, requestedCoverage: .complete)

        await source.emit(event(sample: try sample(
            latitude: 45.638700,
            longitude: -122.661500,
            uptime: 1_000_000_000,
            dateOffset: 0
        )))
        await source.emit(event(sample: try sample(
            latitude: 45.638790,
            longitude: -122.661500,
            uptime: 2_000_000_000,
            dateOffset: 1
        )))

        let summary = try await coordinator.finish()
        XCTAssertNil(summary.routeManifest)
        XCTAssertTrue(summary.routePersistenceFailed)
        XCTAssertEqual(summary.acceptedPointCount, 2)
        XCTAssertGreaterThan(summary.qualityScreenedDistanceMeters, 9)
        XCTAssertLessThan(summary.qualityScreenedDistanceMeters, 11)
        let recordedDistances = await distances.values()
        XCTAssertEqual(recordedDistances.count, 1)
    }

    func testRejectedRideAdmissionExcludesCoordinateFromRouteAndDistance() async throws {
        let directory = temporaryDirectory(name: "location-admission-cutoff")
        defer { try? FileManager.default.removeItem(at: directory) }
        let routeURL = directory.appendingPathComponent("RideRoutes.store")
        let container = try RidePersistenceFactory.makeRouteContainer(storeURL: routeURL)
        let routeStore = SwiftDataRideRouteStore(modelContainer: container)
        let source = TestRideLocationSource()
        let admission = LocationAdmissionSequence(decisions: [true, true, false])
        let sessionID = UUID()

        let coordinator = try RideLocationCaptureCoordinator(
            source: source,
            qualityPolicy: try testPolicy(),
            routeStore: routeStore,
            routeChunkSize: 2,
            sessionScopedEvidenceAdmissionSink: { emittedSessionID, meters, uptime in
                await admission.admit(
                    sessionID: emittedSessionID,
                    meters: meters,
                    uptime: uptime
                )
            }
        )
        try await coordinator.begin(sessionID: sessionID, requestedCoverage: .complete)

        await source.emit(event(sample: try sample(
            latitude: 45.638700,
            longitude: -122.661500,
            uptime: 1_000_000_000,
            dateOffset: 0
        )))
        await source.emit(event(sample: try sample(
            latitude: 45.638790,
            longitude: -122.661500,
            uptime: 2_000_000_000,
            dateOffset: 1
        )))
        await source.emit(event(sample: try sample(
            latitude: 45.638880,
            longitude: -122.661500,
            uptime: 3_000_000_000,
            dateOffset: 2
        )))

        let summary = try await coordinator.finish()
        let manifest = try XCTUnwrap(summary.routeManifest)
        XCTAssertEqual(summary.acceptedPointCount, 2)
        XCTAssertGreaterThan(summary.qualityScreenedDistanceMeters, 9)
        XCTAssertLessThan(summary.qualityScreenedDistanceMeters, 11)
        XCTAssertEqual(manifest.pointCount, 2)

        let geometry = try XCTUnwrap(try await routeStore.geometry(sessionID: sessionID))
        XCTAssertEqual(geometry.segments.count, 1)
        XCTAssertEqual(geometry.segments[0].points.count, 2)
        XCTAssertEqual(geometry.segments[0].points.map(\.sequence), [0, 1])

        let calls = await admission.values()
        XCTAssertEqual(calls.count, 3)
        XCTAssertEqual(calls.map(\.sessionID), [sessionID, sessionID, sessionID])
        XCTAssertNil(calls[0].meters)
        XCTAssertNotNil(calls[1].meters)
        XCTAssertNotNil(calls[2].meters)
    }

    func testCoordinatorCanBeReusedWithoutLeakingPreviousSessionState() async throws {
        let directory = temporaryDirectory(name: "location-reuse")
        defer { try? FileManager.default.removeItem(at: directory) }
        let routeURL = directory.appendingPathComponent("RideRoutes.store")
        let container = try RidePersistenceFactory.makeRouteContainer(storeURL: routeURL)
        let routeStore = SwiftDataRideRouteStore(modelContainer: container)
        let source = TestRideLocationSource()
        let distances = DistanceCollector()
        let coordinator = try RideLocationCaptureCoordinator(
            source: source,
            qualityPolicy: try testPolicy(),
            routeStore: routeStore
        ) { meters, uptime in
            await distances.append(meters: meters, uptime: uptime)
        }

        let firstSession = UUID()
        try await coordinator.begin(sessionID: firstSession, requestedCoverage: .complete)
        await source.emit(event(sample: try sample(
            latitude: 45.638700,
            longitude: -122.661500,
            uptime: 1_000_000_000,
            dateOffset: 0
        )))
        await source.emit(event(sample: try sample(
            latitude: 45.638790,
            longitude: -122.661500,
            uptime: 2_000_000_000,
            dateOffset: 1
        )))
        let firstSummary = try await coordinator.finish()
        XCTAssertEqual(firstSummary.routeManifest?.coverage, .complete)
        XCTAssertFalse(firstSummary.routePersistenceFailed)

        let secondSession = UUID()
        try await coordinator.begin(sessionID: secondSession, requestedCoverage: .partial)
        await source.emit(event(sample: try sample(
            latitude: 45.700000,
            longitude: -122.600000,
            uptime: 100,
            dateOffset: 10
        )))
        await source.emit(event(sample: try sample(
            latitude: 45.700090,
            longitude: -122.600000,
            uptime: 1_000_000_100,
            dateOffset: 11
        )))
        let secondSummary = try await coordinator.finish()
        XCTAssertEqual(secondSummary.routeManifest?.coverage, .partial)
        XCTAssertEqual(secondSummary.acceptedPointCount, 2)
        XCTAssertFalse(secondSummary.routePersistenceFailed)

        let firstGeometry = try await routeStore.geometry(sessionID: firstSession)
        let secondGeometry = try await routeStore.geometry(sessionID: secondSession)
        XCTAssertNotNil(firstGeometry)
        XCTAssertNotNil(secondGeometry)
    }

    @MainActor
    func testScreenedGPSDeltaEntersExistingRideEngineInsteadOfParallelTripState() async throws {
        let directory = temporaryDirectory(name: "location-ride-engine")
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = try RidePersistenceFactory.make(
            scope: .simulation(scenario: .connectedStopped, namespace: "location-ride-engine"),
            baseDirectoryURL: directory
        )
        let configuration = RideApplicationConfiguration(
            detectionPolicy: try RideDetectionPolicy(
                candidateSpeedKilometersPerHour: 1,
                confirmationSpeedKilometersPerHour: 100,
                confirmationDurationNanoseconds: 0,
                confirmationOdometerDeltaKilometers: 100,
                confirmationGPSDistanceMeters: 5,
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
        let rideStore = RideApplicationStore(
            service: service,
            initialState: initialState,
            configuration: configuration,
            checkpointStore: persistence.checkpointStore,
            historyStore: persistence.historyStore
        )
        await rideStore.start()

        await service.simulateRide(speedKilometersPerHour: 2, elapsedSeconds: 0)
        try await waitUntil("Weak speed evidence should create a ride candidate.") {
            rideStore.status == .candidate
        }

        await rideStore.ingestQualityScreenedGPSDistanceDelta(
            6,
            receivedAtUptimeNanoseconds: DispatchTime.now().uptimeNanoseconds
        )
        try await waitUntil("The existing RideEngine should confirm from screened GPS evidence.") {
            rideStore.status == .active
        }
        XCTAssertNotNil(rideStore.activeSessionID)
        rideStore.stop()
    }

    @MainActor
    func testCompletedRideRejectsLateSessionScopedGPSDelta() async throws {
        let directory = temporaryDirectory(name: "location-session-scope")
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = try RidePersistenceFactory.make(
            scope: .simulation(scenario: .connectedStopped, namespace: "location-session-scope"),
            baseDirectoryURL: directory
        )
        let initialState = SimulatedScooterService.state(for: .connectedStopped)
        let service = SimulatedScooterService(
            initialState: initialState,
            commandLatencyNanoseconds: 0
        )
        let rideStore = RideApplicationStore(
            service: service,
            initialState: initialState,
            configuration: try RideApplicationConfiguration.simulatorQA(),
            checkpointStore: persistence.checkpointStore,
            historyStore: persistence.historyStore
        )
        await rideStore.start()

        await service.simulateRide(speedKilometersPerHour: 12, elapsedSeconds: 0)
        try await waitUntil("Simulator movement should start a confirmed ride.") {
            rideStore.status == .active
        }
        let completedSessionID = try XCTUnwrap(rideStore.activeSessionID)

        await service.simulateRide(speedKilometersPerHour: 0, elapsedSeconds: 0)
        try await Task.sleep(nanoseconds: 550_000_000)
        await service.simulateRide(speedKilometersPerHour: 0, elapsedSeconds: 0)
        try await waitUntil("The ride should complete before delayed GPS is delivered.") {
            rideStore.status == .idle
                && rideStore.lastCompletedSessionID == completedSessionID
        }
        XCTAssertNil(rideStore.activeSessionID)

        let admitted = await rideStore.ingestQualityScreenedGPSDistanceDelta(
            25,
            receivedAtUptimeNanoseconds: DispatchTime.now().uptimeNanoseconds,
            for: completedSessionID
        )
        try await Task.sleep(nanoseconds: 75_000_000)

        XCTAssertFalse(admitted, "A completed ride must reject the paired route coordinate as well as GPS distance.")
        XCTAssertEqual(
            rideStore.status,
            .idle,
            "A delayed coordinate from a completed ride must not become fresh movement for a later ride."
        )
        XCTAssertNil(rideStore.activeSessionID)
        XCTAssertEqual(rideStore.lastCompletedSessionID, completedSessionID)
        rideStore.stop()
    }

    @MainActor
    func testRideSessionLifecycleKeepsOneIdentityThroughEndingRecoveryThenEndsOnce() async throws {
        let directory = temporaryDirectory(name: "location-lifecycle")
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = try RidePersistenceFactory.make(
            scope: .simulation(scenario: .connectedStopped, namespace: "location-lifecycle"),
            baseDirectoryURL: directory
        )
        let initialState = SimulatedScooterService.state(for: .connectedStopped)
        let service = SimulatedScooterService(
            initialState: initialState,
            commandLatencyNanoseconds: 0
        )
        let rideStore = RideApplicationStore(
            service: service,
            initialState: initialState,
            configuration: try RideApplicationConfiguration.simulatorQA(),
            checkpointStore: persistence.checkpointStore,
            historyStore: persistence.historyStore
        )
        await rideStore.start()

        let events = SessionEventCollector()
        let stream = rideStore.rideSessionEvents()
        let consumer = Task {
            for await event in stream {
                await events.append(event)
            }
        }

        await service.simulateRide(speedKilometersPerHour: 12, elapsedSeconds: 0)
        try await waitUntil("Simulator movement should begin one authoritative session.") {
            rideStore.status == .active
        }
        let sessionID = try XCTUnwrap(rideStore.activeSessionID)
        try await waitForSessionEventCount(events, count: 1)
        let initialEvents = await events.values()
        XCTAssertEqual(initialEvents, [.becameActive(sessionID)])

        await service.simulateRide(speedKilometersPerHour: 0, elapsedSeconds: 0)
        try await waitUntil("Zero speed should enter the ending candidate without ending the session.") {
            rideStore.status == .endingCandidate
        }
        XCTAssertEqual(rideStore.activeSessionID, sessionID)

        await service.simulateRide(speedKilometersPerHour: 12, elapsedSeconds: 0)
        try await waitUntil("Fresh movement should recover the same ride session.") {
            rideStore.status == .active
        }
        XCTAssertEqual(rideStore.activeSessionID, sessionID)
        try await Task.sleep(nanoseconds: 75_000_000)
        let recoveredEvents = await events.values()
        XCTAssertEqual(
            recoveredEvents,
            [.becameActive(sessionID)],
            "Ending-candidate recovery must not restart root-owned location capture."
        )

        await service.simulateRide(speedKilometersPerHour: 0, elapsedSeconds: 0)
        try await Task.sleep(nanoseconds: 550_000_000)
        await service.simulateRide(speedKilometersPerHour: 0, elapsedSeconds: 0)
        try await waitUntil("The completed ride should return the authoritative session to idle.") {
            rideStore.status == .idle
        }
        try await waitForSessionEventCount(events, count: 2)
        let completedEvents = await events.values()
        XCTAssertEqual(
            completedEvents,
            [.becameActive(sessionID), .ended(sessionID)]
        )

        rideStore.stop()
        consumer.cancel()
    }

    @MainActor
    func testThrowingCompletionBarrierKeepsHistoryPendingUntilRetry() async throws {
        let directory = temporaryDirectory(name: "completion-barrier-retry")
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = try RidePersistenceFactory.make(
            scope: .simulation(scenario: .connectedStopped, namespace: "completion-barrier-retry"),
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
        rideStore.setRideCompletionBarrier { _ in
            throw TestRideCompletionBarrierError.unavailable
        }
        await rideStore.start()

        await service.simulateRide(speedKilometersPerHour: 12, elapsedSeconds: 0)
        try await waitUntil("Simulator movement should start a confirmed ride.") {
            rideStore.status == .active
        }
        let sessionID = try XCTUnwrap(rideStore.activeSessionID)

        await service.simulateRide(speedKilometersPerHour: 0, elapsedSeconds: 0)
        try await Task.sleep(nanoseconds: 550_000_000)
        await service.simulateRide(speedKilometersPerHour: 0, elapsedSeconds: 0)
        try await waitUntil("A failed completion barrier should surface as persistence unavailable.") {
            rideStore.status == .persistenceUnavailable
        }

        let pending = try await persistence.checkpointStore.load()
        guard case let .completedPendingCommit(evidence) = pending else {
            XCTFail("The completed ride checkpoint must remain pending when route outcome persistence fails.")
            return
        }
        XCTAssertEqual(evidence.sessionID, sessionID)
        XCTAssertNil(try await persistence.historyStore.record(sessionID: sessionID))

        rideStore.setRideCompletionBarrier { _ in }
        await service.simulateRide(speedKilometersPerHour: 0, elapsedSeconds: 0)
        try await waitUntil("A later observation should retry and commit the same pending ride.") {
            rideStore.status == .idle && rideStore.lastCompletedSessionID == sessionID
        }
        XCTAssertNotNil(try await persistence.historyStore.record(sessionID: sessionID))
        XCTAssertNil(try await persistence.checkpointStore.load())
        rideStore.stop()
    }

    func testRouteOutcomeLedgerPersistsFailureAndAllowsVerifiedRepair() async throws {
        let directory = temporaryDirectory(name: "route-outcome-ledger")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AtomicRideRouteOutcomeStore(directoryURL: directory)
        let sessionID = UUID()
        let failed = try RideRouteOutcomeRecord(
            sessionID: sessionID,
            state: .storageFailed,
            acceptedPointCount: 3
        )
        _ = try await store.commit(failed)
        XCTAssertEqual(try await store.record(sessionID: sessionID), failed)

        let repaired = try RideRouteOutcomeRecord(
            sessionID: sessionID,
            state: .recorded,
            acceptedPointCount: 3
        )
        _ = try await store.commit(repaired)
        XCTAssertEqual(try await store.record(sessionID: sessionID), repaired)

        let contradictory = try RideRouteOutcomeRecord(
            sessionID: sessionID,
            state: .noRecordedGeometry,
            acceptedPointCount: 0
        )
        do {
            _ = try await store.commit(contradictory)
            XCTFail("A verified recorded route must not be rewritten as no geometry.")
        } catch RideRouteOutcomeStoreError.conflictingOutcome(let conflictID) {
            XCTAssertEqual(conflictID, sessionID)
        }
    }

    @MainActor
    func testRoutePresentationDistinguishesStorageFailureFromNoRecordedGeometry() async throws {
        let directory = temporaryDirectory(name: "route-outcome-presentation")
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try RidePersistenceFactory.makeRouteContainer(
            storeURL: directory.appendingPathComponent("RideRoutes.store")
        )
        let routeStore = SwiftDataRideRouteStore(modelContainer: container)
        let outcomeStore = AtomicRideRouteOutcomeStore(
            directoryURL: directory.appendingPathComponent("RouteOutcomes", isDirectory: true)
        )
        let presentation = RideRoutePresentationStore(
            routeStore: routeStore,
            outcomeStore: outcomeStore
        )

        let failedSession = UUID()
        _ = try await outcomeStore.commit(
            try RideRouteOutcomeRecord(
                sessionID: failedSession,
                state: .storageFailed,
                acceptedPointCount: 2
            )
        )
        await presentation.refresh(sessionID: failedSession)
        XCTAssertEqual(presentation.status(sessionID: failedSession), .failed)
        XCTAssertNotNil(presentation.errorMessage(sessionID: failedSession))

        let emptySession = UUID()
        _ = try await outcomeStore.commit(
            try RideRouteOutcomeRecord(
                sessionID: emptySession,
                state: .noRecordedGeometry,
                acceptedPointCount: 0
            )
        )
        await presentation.refresh(sessionID: emptySession)
        XCTAssertEqual(presentation.status(sessionID: emptySession), .unavailable)
        XCTAssertNil(presentation.errorMessage(sessionID: emptySession))
    }

    func testPersistedRouteChunksWithoutManifestRecoverAsPartial() async throws {
        let directory = temporaryDirectory(name: "route-draft-recovery")
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try RidePersistenceFactory.makeRouteContainer(
            storeURL: directory.appendingPathComponent("RideRoutes.store")
        )
        let routeStore = SwiftDataRideRouteStore(modelContainer: container)
        let sessionID = UUID()
        let capturedAtDate = Date(timeIntervalSince1970: 1_700_000_000)
        let points = [
            try RideRoutePoint(
                sequence: 0,
                latitude: 37.334900,
                longitude: -122.009020,
                capturedAtDate: capturedAtDate,
                horizontalAccuracyMeters: 4
            ),
            try RideRoutePoint(
                sequence: 1,
                latitude: 37.335305,
                longitude: -122.009020,
                capturedAtDate: capturedAtDate.addingTimeInterval(2),
                horizontalAccuracyMeters: 4
            )
        ]
        let chunk = try RideRouteChunk(
            id: RideRouteChunkID(sessionID: sessionID, segmentIndex: 0, chunkIndex: 0),
            points: points
        )
        _ = try await routeStore.commit(chunk)

        let before = try await routeStore.manifest(sessionID: sessionID)
        XCTAssertNil(before)

        let finalizer = RideRouteDraftFinalizer(routeStore: routeStore)
        let manifest = try await finalizer.finalizePartialDraftIfNeeded(sessionID: sessionID)
        XCTAssertEqual(manifest?.coverage, .partial)
        XCTAssertEqual(manifest?.pointCount, 2)

        let loadedGeometry = try await routeStore.geometry(sessionID: sessionID)
        let geometry = try XCTUnwrap(loadedGeometry)
        XCTAssertEqual(geometry.coverage, .partial)
        XCTAssertTrue(geometry.hasDrawablePath)

        let secondPass = try await finalizer.finalizePartialDraftIfNeeded(sessionID: sessionID)
        XCTAssertEqual(secondPass, manifest, "Recovered route finalization must be idempotent.")
    }

    func testRouteDraftRecoveryDoesNotInventEmptyManifest() async throws {
        let directory = temporaryDirectory(name: "route-draft-empty")
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try RidePersistenceFactory.makeRouteContainer(
            storeURL: directory.appendingPathComponent("RideRoutes.store")
        )
        let routeStore = SwiftDataRideRouteStore(modelContainer: container)
        let sessionID = UUID()
        let finalizer = RideRouteDraftFinalizer(routeStore: routeStore)

        let recovered = try await finalizer.finalizePartialDraftIfNeeded(sessionID: sessionID)
        let manifest = try await routeStore.manifest(sessionID: sessionID)
        XCTAssertNil(recovered)
        XCTAssertNil(manifest)
    }

    func testMalformedRecoveredRouteDraftFailsClosed() async throws {
        let directory = temporaryDirectory(name: "route-draft-malformed")
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try RidePersistenceFactory.makeRouteContainer(
            storeURL: directory.appendingPathComponent("RideRoutes.store")
        )
        let routeStore = SwiftDataRideRouteStore(modelContainer: container)
        let sessionID = UUID()
        let point = try RideRoutePoint(
            sequence: 0,
            latitude: 37.334900,
            longitude: -122.009020,
            capturedAtDate: Date(timeIntervalSince1970: 1_700_000_000),
            horizontalAccuracyMeters: 4
        )
        let malformedChunk = try RideRouteChunk(
            id: RideRouteChunkID(sessionID: sessionID, segmentIndex: 1, chunkIndex: 0),
            points: [point]
        )
        _ = try await routeStore.commit(malformedChunk)

        let finalizer = RideRouteDraftFinalizer(routeStore: routeStore)
        do {
            _ = try await finalizer.finalizePartialDraftIfNeeded(sessionID: sessionID)
            XCTFail("Non-contiguous recovered route evidence must fail closed.")
        } catch {
            let manifest = try await routeStore.manifest(sessionID: sessionID)
            XCTAssertNil(manifest)
        }
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

    private func event(sample: RideLocationSample) -> RideLocationSourceEvent {
        RideLocationSourceEvent(sample: sample, issue: nil, isStationary: false)
    }

    private func sample(
        latitude: Double,
        longitude: Double,
        uptime: UInt64,
        dateOffset: TimeInterval
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

    @MainActor
    private func waitForSessionEventCount(
        _ collector: SessionEventCollector,
        count: Int,
        timeoutNanoseconds: UInt64 = 2_000_000_000
    ) async throws {
        let start = DispatchTime.now().uptimeNanoseconds
        while DispatchTime.now().uptimeNanoseconds - start < timeoutNanoseconds {
            let values = await collector.values()
            if values.count >= count { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Timed out waiting for \(count) ride session lifecycle events.")
    }
}

private enum TestRideCompletionBarrierError: Error {
    case unavailable
}

private actor TestRideLocationSource: RideLocationSource {
    private var continuation: AsyncStream<RideLocationSourceEvent>.Continuation?
    private var started = false

    func events() -> AsyncStream<RideLocationSourceEvent> {
        let pair = AsyncStream<RideLocationSourceEvent>.makeStream()
        continuation?.finish()
        continuation = pair.continuation
        return pair.stream
    }

    func start() {
        started = true
    }

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

private actor DistanceCollector {
    struct Value: Equatable, Sendable {
        let meters: Double
        let uptime: UInt64
    }

    private var recorded: [Value] = []

    func append(meters: Double, uptime: UInt64) {
        recorded.append(Value(meters: meters, uptime: uptime))
    }

    func values() -> [Value] {
        recorded
    }
}

private actor SessionDistanceCollector {
    struct Value: Equatable, Sendable {
        let sessionID: UUID
        let meters: Double
        let uptime: UInt64
    }

    private var recorded: [Value] = []

    func append(sessionID: UUID, meters: Double, uptime: UInt64) {
        recorded.append(Value(sessionID: sessionID, meters: meters, uptime: uptime))
    }

    func values() -> [Value] {
        recorded
    }
}

private actor LocationAdmissionSequence {
    struct Call: Equatable, Sendable {
        let sessionID: UUID
        let meters: Double?
        let uptime: UInt64
    }

    private var decisions: [Bool]
    private var calls: [Call] = []

    init(decisions: [Bool]) {
        self.decisions = decisions
    }

    func admit(sessionID: UUID, meters: Double?, uptime: UInt64) -> Bool {
        calls.append(Call(sessionID: sessionID, meters: meters, uptime: uptime))
        guard !decisions.isEmpty else { return false }
        return decisions.removeFirst()
    }

    func values() -> [Call] {
        calls
    }
}

private actor SessionEventCollector {
    private var recorded: [RideApplicationSessionEvent] = []

    func append(_ event: RideApplicationSessionEvent) {
        recorded.append(event)
    }

    func values() -> [RideApplicationSessionEvent] {
        recorded
    }
}
