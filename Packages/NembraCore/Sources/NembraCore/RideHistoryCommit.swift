import Foundation

public enum RideHistoryCommitResult: Equatable, Sendable {
    case inserted
    case alreadyPresent
}

public enum RideHistoryStoreError: Error, Equatable, Sendable {
    case sessionConflict(UUID)
}

/// The durable completed-ride payload owned by local ride history.
///
/// This first record intentionally preserves the raw validated completion
/// evidence rather than baking in a final reconciled distance. ODO/GPS/live
/// evidence and reconciliation can evolve without changing ride identity.
public struct RideHistoryRecord: Codable, Equatable, Sendable {
    public let evidence: CompletedRideEvidence

    public init(evidence: CompletedRideEvidence) {
        self.evidence = evidence
    }

    public var sessionID: UUID { evidence.sessionID }
}

/// Local completed-ride storage contract. Implementations must make commit
/// idempotent by session UUID: committing an equivalent record again returns
/// `alreadyPresent`; the same UUID with different durable evidence must fail
/// with `RideHistoryStoreError.sessionConflict` rather than overwrite history.
public protocol RideHistoryStore: Sendable {
    func commit(_ record: RideHistoryRecord) async throws -> RideHistoryCommitResult
    func record(sessionID: UUID) async throws -> RideHistoryRecord?
}

public enum RideHistoryCommitCoordinatorError: Error, Equatable, Sendable {
    case noPendingCompletedRide
    case durableVerificationFailed(UUID)
}

/// Bridges the crash-recovery journal into permanent completed-ride history.
///
/// The history store is committed first, then immediately read back and checked
/// for exact durable equivalence. Only after that verification may the recovery
/// coordinator clear `completedPendingCommit`. If clearing fails, retrying this
/// operation relies on history-store idempotency and cannot create a duplicate.
public actor RideHistoryCommitCoordinator {
    private let recoveryCoordinator: RideCheckpointCoordinator
    private let historyStore: any RideHistoryStore

    public init(
        recoveryCoordinator: RideCheckpointCoordinator,
        historyStore: any RideHistoryStore
    ) {
        self.recoveryCoordinator = recoveryCoordinator
        self.historyStore = historyStore
    }

    @discardableResult
    public func commitPendingRide() async throws -> RideHistoryCommitResult {
        guard let evidence = await recoveryCoordinator.pendingCompletedRideEvidence() else {
            throw RideHistoryCommitCoordinatorError.noPendingCompletedRide
        }

        let record = RideHistoryRecord(evidence: evidence)
        let result = try await historyStore.commit(record)

        guard try await historyStore.record(sessionID: record.sessionID) == record else {
            throw RideHistoryCommitCoordinatorError.durableVerificationFailed(record.sessionID)
        }

        try await recoveryCoordinator.acknowledgeCompletedRideCommitted(
            sessionID: record.sessionID
        )
        return result
    }
}

// MARK: - Durable route geometry evidence

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

    private enum CodingKeys: String, CodingKey {
        case sequence
        case latitude
        case longitude
        case capturedAtDate
        case sourceMeasurementDate
        case horizontalAccuracyMeters
    }

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

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            sequence: container.decode(UInt64.self, forKey: .sequence),
            latitude: container.decode(Double.self, forKey: .latitude),
            longitude: container.decode(Double.self, forKey: .longitude),
            capturedAtDate: container.decode(Date.self, forKey: .capturedAtDate),
            sourceMeasurementDate: container.decodeIfPresent(Date.self, forKey: .sourceMeasurementDate),
            horizontalAccuracyMeters: container.decodeIfPresent(Double.self, forKey: .horizontalAccuracyMeters)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sequence, forKey: .sequence)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
        try container.encode(capturedAtDate, forKey: .capturedAtDate)
        try container.encodeIfPresent(sourceMeasurementDate, forKey: .sourceMeasurementDate)
        try container.encodeIfPresent(horizontalAccuracyMeters, forKey: .horizontalAccuracyMeters)
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

    private enum CodingKeys: String, CodingKey {
        case id
        case points
    }

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

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(RideRouteChunkID.self, forKey: .id),
            points: container.decode([RideRoutePoint].self, forKey: .points)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(points, forKey: .points)
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

    private enum CodingKeys: String, CodingKey {
        case sessionID
        case coverage
        case segmentCount
        case pointCount
        case knownGapCount
    }

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

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            sessionID: container.decode(UUID.self, forKey: .sessionID),
            coverage: container.decode(RideDistanceCoverage.self, forKey: .coverage),
            segmentCount: container.decode(Int.self, forKey: .segmentCount),
            pointCount: container.decode(Int.self, forKey: .pointCount),
            knownGapCount: container.decode(Int.self, forKey: .knownGapCount)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sessionID, forKey: .sessionID)
        try container.encode(coverage, forKey: .coverage)
        try container.encode(segmentCount, forKey: .segmentCount)
        try container.encode(pointCount, forKey: .pointCount)
        try container.encode(knownGapCount, forKey: .knownGapCount)
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
        guard segmentIndices.count == manifest.segmentCount,
              segmentIndices.enumerated().allSatisfy({ pair in
                  pair.element == UInt32(pair.offset)
              }) else {
            throw RideRouteEvidenceError.nonContiguousSegments
        }

        var segments: [RideRouteSegment] = []
        var totalPointCount = 0
        var previousSequence: UInt64?

        for segmentIndex in segmentIndices {
            guard let segmentChunks = grouped[segmentIndex] else { continue }
            let sortedChunks = segmentChunks.sorted { $0.id.chunkIndex < $1.id.chunkIndex }
            guard sortedChunks.enumerated().allSatisfy({ pair in
                pair.element.id.chunkIndex == UInt32(pair.offset)
            }) else {
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

        guard totalPointCount == manifest.pointCount else {
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
