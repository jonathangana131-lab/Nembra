import Foundation
import Testing
@testable import NembraCore

@Suite("Ride route recorder")
struct RideRouteRecorderTests {
    private let sessionID = UUID(uuidString: "99999999-2222-3333-4444-555555555555")!

    @Test("recorder chunks accepted points and finalizes exact continuous geometry")
    func chunksAndFinalizesContinuousGeometry() async throws {
        let store = MemoryRideRouteStore()
        let recorder = try RideRouteRecorder(
            sessionID: sessionID,
            store: store,
            maximumPointsPerChunk: 2
        )

        #expect(try await recorder.start() == .new)
        let first = try await recorder.append(
            latitude: 45.6387,
            longitude: -122.6615,
            capturedAtDate: Date(timeIntervalSince1970: 1_000),
            horizontalAccuracyMeters: 4
        )
        let second = try await recorder.append(
            latitude: 45.6391,
            longitude: -122.6607,
            capturedAtDate: Date(timeIntervalSince1970: 1_001),
            horizontalAccuracyMeters: 4
        )
        let third = try await recorder.append(
            latitude: 45.6397,
            longitude: -122.6599,
            capturedAtDate: Date(timeIntervalSince1970: 1_002),
            horizontalAccuracyMeters: 5
        )

        #expect(first.sequence == 0)
        #expect(second.sequence == 1)
        #expect(third.sequence == 2)

        let manifest = try await recorder.finish(coverage: .complete)
        #expect(manifest.coverage == .complete)
        #expect(manifest.segmentCount == 1)
        #expect(manifest.pointCount == 3)
        #expect(manifest.knownGapCount == 0)

        let chunks = try await store.chunks(sessionID: sessionID)
        #expect(chunks.count == 2)
        #expect(chunks.map(\.id.chunkIndex) == [0, 1])
        #expect(chunks.flatMap(\.points).map(\.sequence) == [0, 1, 2])

        let geometry = try RideRouteGeometry(manifest: manifest, chunks: chunks)
        #expect(geometry.hasDrawablePath)
        #expect(geometry.pointCount == 3)
    }

    @Test("known gap becomes a separate segment and complete coverage is rejected")
    func explicitGapIsNeverDrawnAcross() async throws {
        let store = MemoryRideRouteStore()
        let recorder = try RideRouteRecorder(
            sessionID: sessionID,
            store: store,
            maximumPointsPerChunk: 8
        )
        _ = try await recorder.start()

        _ = try await recorder.append(
            latitude: 45.6387,
            longitude: -122.6615,
            capturedAtDate: Date(timeIntervalSince1970: 1_000)
        )
        _ = try await recorder.append(
            latitude: 45.6391,
            longitude: -122.6607,
            capturedAtDate: Date(timeIntervalSince1970: 1_001)
        )
        try await recorder.markGap()
        _ = try await recorder.append(
            latitude: 45.6400,
            longitude: -122.6590,
            capturedAtDate: Date(timeIntervalSince1970: 1_010)
        )
        _ = try await recorder.append(
            latitude: 45.6405,
            longitude: -122.6582,
            capturedAtDate: Date(timeIntervalSince1970: 1_011)
        )

        do {
            _ = try await recorder.finish(coverage: .complete)
            Issue.record("A recorder that observed a gap must not finalize as complete.")
        } catch let error as RideRouteRecorderError {
            #expect(error == .coverageContradictsKnownGap)
        }

        let manifest = try await recorder.finish(coverage: .partial)
        let chunks = try await store.chunks(sessionID: sessionID)
        let geometry = try RideRouteGeometry(manifest: manifest, chunks: chunks)

        #expect(manifest.segmentCount == 2)
        #expect(manifest.knownGapCount == 1)
        #expect(geometry.segments.count == 2)
        #expect(geometry.segments[0].points.map(\.sequence) == [0, 1])
        #expect(geometry.segments[1].points.map(\.sequence) == [2, 3])
    }

    @Test("unfinished persisted draft resumes in a new segment after process recovery")
    func recoveryCreatesExplicitDiscontinuity() async throws {
        let store = MemoryRideRouteStore()
        let original = try RideRouteRecorder(
            sessionID: sessionID,
            store: store,
            maximumPointsPerChunk: 2
        )
        _ = try await original.start()
        _ = try await original.append(
            latitude: 45.6387,
            longitude: -122.6615,
            capturedAtDate: Date(timeIntervalSince1970: 1_000)
        )
        _ = try await original.append(
            latitude: 45.6391,
            longitude: -122.6607,
            capturedAtDate: Date(timeIntervalSince1970: 1_001)
        )

        let resumed = try RideRouteRecorder(
            sessionID: sessionID,
            store: store,
            maximumPointsPerChunk: 2
        )
        #expect(
            try await resumed.start() == .resumed(
                persistedPointCount: 2,
                nextSegmentIndex: 1
            )
        )
        let resumedPoint = try await resumed.append(
            latitude: 45.6400,
            longitude: -122.6590,
            capturedAtDate: Date(timeIntervalSince1970: 1_020)
        )
        #expect(resumedPoint.sequence == 2)

        do {
            _ = try await resumed.finish(coverage: .complete)
            Issue.record("A process recovery must prevent a complete route claim.")
        } catch let error as RideRouteRecorderError {
            #expect(error == .coverageContradictsKnownGap)
        }

        let manifest = try await resumed.finish(coverage: .partial)
        let chunks = try await store.chunks(sessionID: sessionID)
        let geometry = try RideRouteGeometry(manifest: manifest, chunks: chunks)
        #expect(geometry.segments.map(\.index) == [0, 1])
        #expect(geometry.knownGapCount == 1)
        #expect(geometry.pointCount == 3)
    }

    @Test("finalized route validates on reopen and cannot accept more evidence")
    func finalizedRouteIsImmutable() async throws {
        let store = MemoryRideRouteStore()
        let first = try RideRouteRecorder(sessionID: sessionID, store: store)
        _ = try await first.start()
        _ = try await first.append(
            latitude: 45.6387,
            longitude: -122.6615,
            capturedAtDate: Date(timeIntervalSince1970: 1_000)
        )
        let manifest = try await first.finish(coverage: .partial)

        let reopened = try RideRouteRecorder(sessionID: sessionID, store: store)
        #expect(try await reopened.start() == .alreadyFinalized(manifest))

        do {
            _ = try await reopened.append(
                latitude: 45.6391,
                longitude: -122.6607,
                capturedAtDate: Date(timeIntervalSince1970: 1_001)
            )
            Issue.record("Finalized route evidence must be immutable.")
        } catch let error as RideRouteRecorderError {
            #expect(error == .alreadyFinalized(sessionID))
        }
    }

    @Test("empty recorder finalizes only as unknown geometry")
    func emptyRecordingCannotClaimCoverage() async throws {
        let store = MemoryRideRouteStore()
        let recorder = try RideRouteRecorder(sessionID: sessionID, store: store)
        _ = try await recorder.start()

        let manifest = try await recorder.finish(coverage: .complete)
        #expect(manifest.coverage == .unknown)
        #expect(manifest.pointCount == 0)
        #expect(manifest.segmentCount == 0)
        #expect(manifest.knownGapCount == 0)
    }
}

private actor MemoryRideRouteStore: RideRouteStore {
    private var chunksByID: [RideRouteChunkID: RideRouteChunk] = [:]
    private var manifestsBySession: [UUID: RideRouteManifest] = [:]

    func commit(_ chunk: RideRouteChunk) async throws -> RideRouteStoreCommitResult {
        if let existing = chunksByID[chunk.id] {
            guard existing == chunk else {
                throw RideRouteStoreError.chunkConflict(chunk.id)
            }
            return .alreadyPresent
        }
        chunksByID[chunk.id] = chunk
        return .inserted
    }

    func chunk(id: RideRouteChunkID) async throws -> RideRouteChunk? {
        chunksByID[id]
    }

    func chunks(sessionID: UUID) async throws -> [RideRouteChunk] {
        chunksByID.values
            .filter { $0.id.sessionID == sessionID }
            .sorted { lhs, rhs in
                if lhs.id.segmentIndex != rhs.id.segmentIndex {
                    return lhs.id.segmentIndex < rhs.id.segmentIndex
                }
                return lhs.id.chunkIndex < rhs.id.chunkIndex
            }
    }

    func commit(_ manifest: RideRouteManifest) async throws -> RideRouteStoreCommitResult {
        if let existing = manifestsBySession[manifest.sessionID] {
            guard existing == manifest else {
                throw RideRouteStoreError.manifestConflict(manifest.sessionID)
            }
            return .alreadyPresent
        }
        manifestsBySession[manifest.sessionID] = manifest
        return .inserted
    }

    func manifest(sessionID: UUID) async throws -> RideRouteManifest? {
        manifestsBySession[sessionID]
    }
}
