import Foundation
import Testing
@testable import NembraCore

@Suite("Ride route evidence")
struct RideRouteEvidenceTests {
    private let sessionID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    private func point(
        _ sequence: UInt64,
        latitude: Double = 45.6387,
        longitude: Double = -122.6615
    ) throws -> RideRoutePoint {
        try RideRoutePoint(
            sequence: sequence,
            latitude: latitude,
            longitude: longitude,
            capturedAtDate: Date(timeIntervalSince1970: 1_700_000_000 + Double(sequence)),
            sourceMeasurementDate: Date(timeIntervalSince1970: 1_700_000_000 + Double(sequence)),
            horizontalAccuracyMeters: 4.5
        )
    }

    @Test("coordinates and horizontal accuracy fail closed")
    func invalidPointsRejected() {
        #expect(throws: RideRouteEvidenceError.invalidCoordinate) {
            _ = try RideRoutePoint(
                sequence: 0,
                latitude: 91,
                longitude: -122,
                capturedAtDate: .now
            )
        }
        #expect(throws: RideRouteEvidenceError.invalidCoordinate) {
            _ = try RideRoutePoint(
                sequence: 0,
                latitude: 45,
                longitude: .infinity,
                capturedAtDate: .now
            )
        }
        #expect(throws: RideRouteEvidenceError.invalidHorizontalAccuracy) {
            _ = try RideRoutePoint(
                sequence: 0,
                latitude: 45,
                longitude: -122,
                capturedAtDate: .now,
                horizontalAccuracyMeters: -1
            )
        }
    }

    @Test("chunks require nonempty strictly increasing point sequence")
    func chunkSequenceIsValidated() throws {
        let id = RideRouteChunkID(sessionID: sessionID, segmentIndex: 0, chunkIndex: 0)
        #expect(throws: RideRouteEvidenceError.emptyChunk) {
            _ = try RideRouteChunk(id: id, points: [])
        }
        #expect(throws: RideRouteEvidenceError.nonMonotonicPointSequence) {
            _ = try RideRouteChunk(id: id, points: [try point(1), try point(1)])
        }
        #expect(throws: RideRouteEvidenceError.nonMonotonicPointSequence) {
            _ = try RideRouteChunk(id: id, points: [try point(2), try point(1)])
        }
    }

    @Test("empty route can only finalize as unknown with zero counts")
    func emptyManifestRemainsUnknown() throws {
        let manifest = try RideRouteManifest(
            sessionID: sessionID,
            coverage: .unknown,
            segmentCount: 0,
            pointCount: 0,
            knownGapCount: 0
        )
        let geometry = try RideRouteGeometry(manifest: manifest, chunks: [])
        #expect(geometry.segments.isEmpty)
        #expect(!geometry.hasRecordedGeometry)
        #expect(!geometry.hasDrawablePath)

        #expect(throws: RideRouteEvidenceError.invalidManifest) {
            _ = try RideRouteManifest(
                sessionID: sessionID,
                coverage: .complete,
                segmentCount: 0,
                pointCount: 0,
                knownGapCount: 0
            )
        }
    }

    @Test("continuous chunks assemble into one drawable segment")
    func continuousChunksAssemble() throws {
        let chunks = [
            try RideRouteChunk(
                id: RideRouteChunkID(sessionID: sessionID, segmentIndex: 0, chunkIndex: 0),
                points: [try point(0), try point(1)]
            ),
            try RideRouteChunk(
                id: RideRouteChunkID(sessionID: sessionID, segmentIndex: 0, chunkIndex: 1),
                points: [try point(2), try point(3)]
            )
        ]
        let manifest = try RideRouteManifest(
            sessionID: sessionID,
            coverage: .complete,
            segmentCount: 1,
            pointCount: 4,
            knownGapCount: 0
        )

        let geometry = try RideRouteGeometry(manifest: manifest, chunks: Array(chunks.reversed()))
        #expect(geometry.coverage == .complete)
        #expect(geometry.pointCount == 4)
        #expect(geometry.segments.count == 1)
        #expect(geometry.segments[0].points.map(\.sequence) == [0, 1, 2, 3])
        #expect(geometry.hasDrawablePath)
    }

    @Test("explicit segments preserve a known geometry gap instead of connecting through it")
    func segmentsPreserveGap() throws {
        let chunks = [
            try RideRouteChunk(
                id: RideRouteChunkID(sessionID: sessionID, segmentIndex: 0, chunkIndex: 0),
                points: [try point(0), try point(1)]
            ),
            try RideRouteChunk(
                id: RideRouteChunkID(sessionID: sessionID, segmentIndex: 1, chunkIndex: 0),
                points: [try point(2), try point(3)]
            )
        ]
        let manifest = try RideRouteManifest(
            sessionID: sessionID,
            coverage: .partial,
            segmentCount: 2,
            pointCount: 4,
            knownGapCount: 1
        )

        let geometry = try RideRouteGeometry(manifest: manifest, chunks: chunks)
        #expect(geometry.knownGapCount == 1)
        #expect(geometry.segments.count == 2)
        #expect(geometry.segments[0].points.map(\.sequence) == [0, 1])
        #expect(geometry.segments[1].points.map(\.sequence) == [2, 3])
    }

    @Test("complete geometry cannot contain an explicit segment gap")
    func completeManifestCannotContainGap() {
        #expect(throws: RideRouteEvidenceError.invalidManifest) {
            _ = try RideRouteManifest(
                sessionID: sessionID,
                coverage: .complete,
                segmentCount: 2,
                pointCount: 4,
                knownGapCount: 1
            )
        }
    }

    @Test("geometry rejects session mismatch, missing chunks, and count mismatch")
    func geometryFailsClosedOnCorruption() throws {
        let firstChunk = try RideRouteChunk(
            id: RideRouteChunkID(sessionID: sessionID, segmentIndex: 0, chunkIndex: 0),
            points: [try point(0), try point(1)]
        )
        let skippedChunk = try RideRouteChunk(
            id: RideRouteChunkID(sessionID: sessionID, segmentIndex: 0, chunkIndex: 2),
            points: [try point(2), try point(3)]
        )
        let manifest = try RideRouteManifest(
            sessionID: sessionID,
            coverage: .partial,
            segmentCount: 1,
            pointCount: 4,
            knownGapCount: 0
        )

        #expect(throws: RideRouteEvidenceError.nonContiguousChunks) {
            _ = try RideRouteGeometry(manifest: manifest, chunks: [firstChunk, skippedChunk])
        }

        let otherSession = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let foreignChunk = try RideRouteChunk(
            id: RideRouteChunkID(sessionID: otherSession, segmentIndex: 0, chunkIndex: 0),
            points: [try point(0), try point(1)]
        )
        #expect(throws: RideRouteEvidenceError.mismatchedSession) {
            _ = try RideRouteGeometry(manifest: manifest, chunks: [foreignChunk])
        }

        let wrongCountManifest = try RideRouteManifest(
            sessionID: sessionID,
            coverage: .partial,
            segmentCount: 1,
            pointCount: 3,
            knownGapCount: 0
        )
        #expect(throws: RideRouteEvidenceError.manifestCountMismatch) {
            _ = try RideRouteGeometry(manifest: wrongCountManifest, chunks: [firstChunk])
        }
    }

    @Test("point ordering must stay monotonic across chunk and segment boundaries")
    func globalPointSequenceIsValidated() throws {
        let chunks = [
            try RideRouteChunk(
                id: RideRouteChunkID(sessionID: sessionID, segmentIndex: 0, chunkIndex: 0),
                points: [try point(5), try point(6)]
            ),
            try RideRouteChunk(
                id: RideRouteChunkID(sessionID: sessionID, segmentIndex: 1, chunkIndex: 0),
                points: [try point(4), try point(7)]
            )
        ]
        let manifest = try RideRouteManifest(
            sessionID: sessionID,
            coverage: .partial,
            segmentCount: 2,
            pointCount: 4,
            knownGapCount: 1
        )

        #expect(throws: RideRouteEvidenceError.nonMonotonicPointSequence) {
            _ = try RideRouteGeometry(manifest: manifest, chunks: chunks)
        }
    }
}
