import Foundation

public enum RideRouteEvidenceError: Error, Equatable, Sendable {
    case invalidCoordinate
    case invalidHorizontalAccuracy
    case emptyChunk
    case nonMonotonicPointSequence
    case invalidManifest
    case mismatchedSession
    case nonContiguousSegments
    case nonContiguousChunks
    case manifestCountMismatch
}

/// One quality-screened coordinate accepted into ride-route evidence.
///
/// `sequence` is the durable ordering authority inside one ride. Wall-clock
/// dates are retained for history/timeline presentation only and are never used
/// to repair or reorder geometry after a system-clock change.
public struct RideRoutePoint: Codable, Equatable, Sendable {
    public let sequence: UInt64
    public let latitude: Double
    public let longitude: Double
    public let capturedAtDate: Date
    public let sourceMeasurementDate: Date?
    public let horizontalAccuracyMeters: Double?

    public init(
        sequence: UInt64,
        latitude: Double,
        longitude: Double,
        capturedAtDate: Date,
        sourceMeasurementDate: Date? = nil,
        horizontalAccuracyMeters: Double? = nil
    ) throws {
        guard latitude.isFinite,
              longitude.isFinite,
              (-90...90).contains(latitude),
              (-180...180).contains(longitude) else {
            throw RideRouteEvidenceError.invalidCoordinate
        }

        if let horizontalAccuracyMeters {
            guard horizontalAccuracyMeters.isFinite,
                  horizontalAccuracyMeters >= 0 else {
                throw RideRouteEvidenceError.invalidHorizontalAccuracy
            }
        }

        self.sequence = sequence
        self.latitude = latitude
        self.longitude = longitude
        self.capturedAtDate = capturedAtDate
        self.sourceMeasurementDate = sourceMeasurementDate
        self.horizontalAccuracyMeters = horizontalAccuracyMeters
    }
}

public struct RideRouteChunkID: Codable, Equatable, Hashable, Sendable {
    public let sessionID: UUID
    public let segmentIndex: UInt32
    public let chunkIndex: UInt32

    public init(sessionID: UUID, segmentIndex: UInt32, chunkIndex: UInt32) {
        self.sessionID = sessionID
        self.segmentIndex = segmentIndex
        self.chunkIndex = chunkIndex
    }
}

/// Immutable persisted geometry batch.
///
/// Chunks with the same `segmentIndex` form one continuous polyline and must
/// have contiguous `chunkIndex` values starting at zero. A higher segment index
/// is an explicit geometry discontinuity: presentation must never draw a line
/// across that boundary merely to make a route look complete.
public struct RideRouteChunk: Codable, Equatable, Sendable {
    public let id: RideRouteChunkID
    public let points: [RideRoutePoint]

    public init(id: RideRouteChunkID, points: [RideRoutePoint]) throws {
        guard !points.isEmpty else {
            throw RideRouteEvidenceError.emptyChunk
        }
        guard Self.hasStrictlyIncreasingSequence(points) else {
            throw RideRouteEvidenceError.nonMonotonicPointSequence
        }
        self.id = id
        self.points = points
    }

    private static func hasStrictlyIncreasingSequence(_ points: [RideRoutePoint]) -> Bool {
        guard points.count > 1 else { return true }
        return zip(points, points.dropFirst()).allSatisfy { previous, next in
            next.sequence > previous.sequence
        }
    }
}

/// Final route-geometry metadata for one completed ride.
///
/// This describes only what Nembra actually recorded. `coverage` is supplied by
/// the recording layer; geometry types do not infer completeness from the mere
/// absence of a stored gap marker.
public struct RideRouteManifest: Codable, Equatable, Sendable {
    public let sessionID: UUID
    public let coverage: RideDistanceCoverage
    public let segmentCount: Int
    public let pointCount: Int
    public let knownGapCount: Int

    public init(
        sessionID: UUID,
        coverage: RideDistanceCoverage,
        segmentCount: Int,
        pointCount: Int,
        knownGapCount: Int
    ) throws {
        guard segmentCount >= 0,
              segmentCount <= Int(UInt32.max),
              pointCount >= 0,
              knownGapCount >= 0 else {
            throw RideRouteEvidenceError.invalidManifest
        }

        if pointCount == 0 {
            guard segmentCount == 0,
                  knownGapCount == 0,
                  coverage == .unknown else {
                throw RideRouteEvidenceError.invalidManifest
            }
        } else {
            guard segmentCount > 0,
                  segmentCount <= pointCount else {
                throw RideRouteEvidenceError.invalidManifest
            }
            if segmentCount > 1 {
                guard knownGapCount == segmentCount - 1 else {
                    throw RideRouteEvidenceError.invalidManifest
                }
            } else {
                guard knownGapCount == 0 else {
                    throw RideRouteEvidenceError.invalidManifest
                }
            }
            if coverage == .complete {
                guard segmentCount == 1 else {
                    throw RideRouteEvidenceError.invalidManifest
                }
            }
        }

        self.sessionID = sessionID
        self.coverage = coverage
        self.segmentCount = segmentCount
        self.pointCount = pointCount
        self.knownGapCount = knownGapCount
    }
}

public struct RideRouteSegment: Equatable, Sendable {
    public let index: UInt32
    public let points: [RideRoutePoint]

    public init(index: UInt32, points: [RideRoutePoint]) {
        self.index = index
        self.points = points
    }
}

/// Validated completed geometry assembled from immutable chunks plus the final
/// manifest. It fails closed on missing/reordered chunks or mismatched sessions
/// instead of drawing a plausible-looking path through corrupt evidence.
public struct RideRouteGeometry: Equatable, Sendable {
    public let sessionID: UUID
    public let coverage: RideDistanceCoverage
    public let knownGapCount: Int
    public let segments: [RideRouteSegment]

    public init(manifest: RideRouteManifest, chunks: [RideRouteChunk]) throws {
        guard chunks.allSatisfy({ $0.id.sessionID == manifest.sessionID }) else {
            throw RideRouteEvidenceError.mismatchedSession
        }

        if manifest.pointCount == 0 {
            guard chunks.isEmpty else {
                throw RideRouteEvidenceError.manifestCountMismatch
            }
            self.sessionID = manifest.sessionID
            self.coverage = manifest.coverage
            self.knownGapCount = manifest.knownGapCount
            self.segments = []
            return
        }

        let ordered = chunks.sorted { lhs, rhs in
            if lhs.id.segmentIndex != rhs.id.segmentIndex {
                return lhs.id.segmentIndex < rhs.id.segmentIndex
            }
            return lhs.id.chunkIndex < rhs.id.chunkIndex
        }

        let grouped = Dictionary(grouping: ordered, by: { $0.id.segmentIndex })
        let segmentIndices = grouped.keys.sorted()
        let expectedSegmentIndices = Array(UInt32(0)..<UInt32(manifest.segmentCount))
        guard segmentIndices == expectedSegmentIndices else {
            throw RideRouteEvidenceError.nonContiguousSegments
        }

        var segments: [RideRouteSegment] = []
        var totalPointCount = 0
        var previousSequence: UInt64?

        for segmentIndex in segmentIndices {
            guard let segmentChunks = grouped[segmentIndex] else { continue }
            let sortedChunks = segmentChunks.sorted { $0.id.chunkIndex < $1.id.chunkIndex }
            let expectedChunkIndices = Array(UInt32(0)..<UInt32(sortedChunks.count))
            guard sortedChunks.map(\.id.chunkIndex) == expectedChunkIndices else {
                throw RideRouteEvidenceError.nonContiguousChunks
            }

            let points = sortedChunks.flatMap(\.points)
            for point in points {
                if let previousSequence, point.sequence <= previousSequence {
                    throw RideRouteEvidenceError.nonMonotonicPointSequence
                }
                previousSequence = point.sequence
            }

            totalPointCount += points.count
            segments.append(RideRouteSegment(index: segmentIndex, points: points))
        }

        guard segments.count == manifest.segmentCount,
              totalPointCount == manifest.pointCount else {
            throw RideRouteEvidenceError.manifestCountMismatch
        }

        self.sessionID = manifest.sessionID
        self.coverage = manifest.coverage
        self.knownGapCount = manifest.knownGapCount
        self.segments = segments
    }

    public var pointCount: Int {
        segments.reduce(0) { $0 + $1.points.count }
    }

    public var hasRecordedGeometry: Bool {
        pointCount > 0
    }

    public var hasDrawablePath: Bool {
        segments.contains { $0.points.count >= 2 }
    }
}

public enum RideRouteStoreCommitResult: Equatable, Sendable {
    case inserted
    case alreadyPresent
}

public enum RideRouteStoreError: Error, Equatable, Sendable {
    case chunkConflict(RideRouteChunkID)
    case manifestConflict(UUID)
}

/// Persistence boundary for immutable route chunks and one final manifest.
/// Equivalent retries are idempotent; same identities with different evidence
/// are conflicts and must never overwrite a recorded ride path.
public protocol RideRouteStore: Sendable {
    func commit(_ chunk: RideRouteChunk) async throws -> RideRouteStoreCommitResult
    func chunk(id: RideRouteChunkID) async throws -> RideRouteChunk?
    func chunks(sessionID: UUID) async throws -> [RideRouteChunk]
    func commit(_ manifest: RideRouteManifest) async throws -> RideRouteStoreCommitResult
    func manifest(sessionID: UUID) async throws -> RideRouteManifest?
}
