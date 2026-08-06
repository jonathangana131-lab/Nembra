import Foundation
import XCTest
@testable import Nembra

final class RideRouteDraftFinalizerTests: XCTestCase {
    func testPersistedChunksWithoutManifestRecoverAsPartialRoute() async throws {
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
            id: RideRouteChunkID(
                sessionID: sessionID,
                segmentIndex: 0,
                chunkIndex: 0
            ),
            points: points
        )
        _ = try await routeStore.commit(chunk)

        let manifestBeforeRecovery = try await routeStore.manifest(sessionID: sessionID)
        XCTAssertNil(manifestBeforeRecovery)

        let finalizer = RideRouteDraftFinalizer(routeStore: routeStore)
        let manifest = try await finalizer.finalizePartialDraftIfNeeded(sessionID: sessionID)

        XCTAssertEqual(manifest?.sessionID, sessionID)
        XCTAssertEqual(manifest?.coverage, .partial)
        XCTAssertEqual(manifest?.segmentCount, 1)
        XCTAssertEqual(manifest?.pointCount, 2)
        XCTAssertEqual(manifest?.knownGapCount, 0)

        let loadedGeometry = try await routeStore.geometry(sessionID: sessionID)
        let geometry = try XCTUnwrap(loadedGeometry)
        XCTAssertEqual(geometry.coverage, .partial)
        XCTAssertEqual(geometry.pointCount, 2)
        XCTAssertTrue(geometry.hasDrawablePath)

        let secondPass = try await finalizer.finalizePartialDraftIfNeeded(sessionID: sessionID)
        XCTAssertEqual(secondPass, manifest, "Crash recovery must remain idempotent across repeated launches.")
    }

    func testNoPersistedChunksDoesNotInventEmptyRouteManifest() async throws {
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
        let geometry = try await routeStore.geometry(sessionID: sessionID)
        XCTAssertNil(recovered)
        XCTAssertNil(manifest)
        XCTAssertNil(geometry)
    }

    func testMalformedNonContiguousDraftFailsClosedWithoutManifest() async throws {
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
            id: RideRouteChunkID(
                sessionID: sessionID,
                segmentIndex: 1,
                chunkIndex: 0
            ),
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

    private func temporaryDirectory(name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("Nembra-\(name)-\(UUID().uuidString)", isDirectory: true)
    }
}
