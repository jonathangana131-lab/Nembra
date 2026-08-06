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

        let geometry = try XCTUnwrap(try await routeStore.geometry(sessionID: sessionID))
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
        XCTAssertEqual(await distances.values().count, 1)
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

        XCTAssertNotNil(try await routeStore.geometry(sessionID: firstSession))
        XCTAssertNotNil(try await routeStore.geometry(sessionID: secondSession))
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
