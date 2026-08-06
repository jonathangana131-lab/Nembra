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

public enum RideRouteRecorderError: Error, Equatable, Sendable {
    case invalidChunkCapacity
    case notStarted
    case alreadyStarted
    case alreadyFinalized(UUID)
    case corruptDraft(UUID)
    case sequenceOverflow
    case segmentOverflow
    case chunkOverflow
    case coverageContradictsKnownGap
    case durableChunkVerificationFailed(RideRouteChunkID)
    case durableManifestVerificationFailed(UUID)
}

public enum RideRouteRecorderStartResult: Equatable, Sendable {
    case new
    case resumed(persistedPointCount: Int, nextSegmentIndex: UInt32)
    case alreadyFinalized(RideRouteManifest)
}

/// Incremental recorder above `RideRouteStore` for already quality-screened
/// coordinates. The recorder assigns durable ordering, chunks points without
/// rewriting prior evidence, and creates explicit segment boundaries across a
/// known gap or process recovery.
///
/// This type deliberately does not decide whether a GPS update is accurate
/// enough to accept. Production Core Location policy must screen updates before
/// calling `append`, and must supply final coverage rather than asking the
/// recorder to infer completeness from a visually continuous line.
public actor RideRouteRecorder {
    public let sessionID: UUID
    public let maximumPointsPerChunk: Int

    private let store: any RideRouteStore
    private var started = false
    private var finalizedManifest: RideRouteManifest?
    private var buffer: [RideRoutePoint] = []
    private var currentSegmentIndex: UInt32 = 0
    private var currentChunkIndex: UInt32 = 0
    private var nextSequence: UInt64 = 0
    private var totalPointCount = 0
    private var segmentIndicesWithPoints: Set<UInt32> = []
    private var pendingGap = false
    private var resumedAcrossProcessBoundary = false

    public init(
        sessionID: UUID,
        store: any RideRouteStore,
        maximumPointsPerChunk: Int = 64
    ) throws {
        guard maximumPointsPerChunk > 0 else {
            throw RideRouteRecorderError.invalidChunkCapacity
        }
        self.sessionID = sessionID
        self.store = store
        self.maximumPointsPerChunk = maximumPointsPerChunk
    }

    /// Validates persisted state before accepting new points. A finalized route
    /// is read and assembled before it is reported as finalized. An unfinished
    /// draft resumes at a new segment because a process boundary is an explicit
    /// continuity gap, never something Nembra may draw across optimistically.
    @discardableResult
    public func start() async throws -> RideRouteRecorderStartResult {
        guard !started else {
            throw RideRouteRecorderError.alreadyStarted
        }

        let chunks = try await store.chunks(sessionID: sessionID)
        if let manifest = try await store.manifest(sessionID: sessionID) {
            _ = try RideRouteGeometry(manifest: manifest, chunks: chunks)
            finalizedManifest = manifest
            started = true
            return .alreadyFinalized(manifest)
        }

        guard !chunks.isEmpty else {
            started = true
            return .new
        }

        let draft = try Self.validateDraft(sessionID: sessionID, chunks: chunks)
        guard draft.lastSequence < UInt64.max else {
            throw RideRouteRecorderError.sequenceOverflow
        }
        guard draft.lastSegmentIndex < UInt32.max else {
            throw RideRouteRecorderError.segmentOverflow
        }

        totalPointCount = draft.pointCount
        segmentIndicesWithPoints = Set(draft.segmentIndices)
        nextSequence = draft.lastSequence + 1
        currentSegmentIndex = draft.lastSegmentIndex + 1
        currentChunkIndex = 0
        resumedAcrossProcessBoundary = true
        started = true
        return .resumed(
            persistedPointCount: draft.pointCount,
            nextSegmentIndex: currentSegmentIndex
        )
    }

    /// Accept one coordinate that has already passed the caller's location
    /// quality policy. The returned point contains the sequence Nembra assigned.
    @discardableResult
    public func append(
        latitude: Double,
        longitude: Double,
        capturedAtDate: Date,
        sourceMeasurementDate: Date? = nil,
        horizontalAccuracyMeters: Double? = nil
    ) async throws -> RideRoutePoint {
        try requireWritable()

        if pendingGap, totalPointCount > 0 {
            try beginNextSegment()
            pendingGap = false
        }

        let point = try RideRoutePoint(
            sequence: nextSequence,
            latitude: latitude,
            longitude: longitude,
            capturedAtDate: capturedAtDate,
            sourceMeasurementDate: sourceMeasurementDate,
            horizontalAccuracyMeters: horizontalAccuracyMeters
        )

        buffer.append(point)
        totalPointCount += 1
        segmentIndicesWithPoints.insert(currentSegmentIndex)

        if nextSequence < UInt64.max {
            nextSequence += 1
        } else if buffer.count < maximumPointsPerChunk {
            // The final representable sequence can exist, but no subsequent
            // point may be accepted. Flushing it remains safe.
            nextSequence = UInt64.max
        }

        if buffer.count >= maximumPointsPerChunk {
            try await flushBuffer()
        }
        return point
    }

    /// Marks a known recording discontinuity. Buffered evidence is committed
    /// first. The next accepted point begins a new segment; repeated gap calls
    /// before another point collapse into one boundary instead of creating empty
    /// segments that would imply evidence Nembra never recorded.
    public func markGap() async throws {
        try requireWritable()
        try await flushBuffer()
        if totalPointCount > 0 {
            pendingGap = true
        }
    }

    /// Commits any partial chunk and then one immutable manifest. Coverage is a
    /// caller-supplied truth claim. `complete` is rejected after a known segment
    /// gap or process recovery because the recorder itself has evidence that
    /// continuity was not observed end-to-end.
    @discardableResult
    public func finish(coverage: RideDistanceCoverage) async throws -> RideRouteManifest {
        try requireWritable()
        try await flushBuffer()

        let segmentCount = segmentIndicesWithPoints.count
        let knownGapCount = max(0, segmentCount - 1)

        if coverage == .complete,
           (knownGapCount > 0 || resumedAcrossProcessBoundary || pendingGap) {
            throw RideRouteRecorderError.coverageContradictsKnownGap
        }

        let manifest: RideRouteManifest
        if totalPointCount == 0 {
            manifest = try RideRouteManifest(
                sessionID: sessionID,
                coverage: .unknown,
                segmentCount: 0,
                pointCount: 0,
                knownGapCount: 0
            )
        } else {
            manifest = try RideRouteManifest(
                sessionID: sessionID,
                coverage: coverage,
                segmentCount: segmentCount,
                pointCount: totalPointCount,
                knownGapCount: knownGapCount
            )
        }

        _ = try await store.commit(manifest)
        guard try await store.manifest(sessionID: sessionID) == manifest else {
            throw RideRouteRecorderError.durableManifestVerificationFailed(sessionID)
        }

        finalizedManifest = manifest
        pendingGap = false
        return manifest
    }

    public func manifestIfFinalized() -> RideRouteManifest? {
        finalizedManifest
    }

    private func requireWritable() throws {
        guard started else {
            throw RideRouteRecorderError.notStarted
        }
        guard finalizedManifest == nil else {
            throw RideRouteRecorderError.alreadyFinalized(sessionID)
        }
        guard nextSequence < UInt64.max || totalPointCount == 0 else {
            throw RideRouteRecorderError.sequenceOverflow
        }
    }

    private func beginNextSegment() throws {
        guard currentSegmentIndex < UInt32.max else {
            throw RideRouteRecorderError.segmentOverflow
        }
        currentSegmentIndex += 1
        currentChunkIndex = 0
    }

    private func flushBuffer() async throws {
        guard !buffer.isEmpty else { return }

        let id = RideRouteChunkID(
            sessionID: sessionID,
            segmentIndex: currentSegmentIndex,
            chunkIndex: currentChunkIndex
        )
        let chunk = try RideRouteChunk(id: id, points: buffer)
        _ = try await store.commit(chunk)
        guard try await store.chunk(id: id) == chunk else {
            throw RideRouteRecorderError.durableChunkVerificationFailed(id)
        }

        buffer.removeAll(keepingCapacity: true)
        guard currentChunkIndex < UInt32.max else {
            throw RideRouteRecorderError.chunkOverflow
        }
        currentChunkIndex += 1
    }

    private struct DraftValidation {
        let pointCount: Int
        let lastSequence: UInt64
        let lastSegmentIndex: UInt32
        let segmentIndices: [UInt32]
    }

    private static func validateDraft(
        sessionID: UUID,
        chunks: [RideRouteChunk]
    ) throws -> DraftValidation {
        guard !chunks.isEmpty,
              chunks.allSatisfy({ $0.id.sessionID == sessionID }) else {
            throw RideRouteRecorderError.corruptDraft(sessionID)
        }

        let ordered = chunks.sorted { lhs, rhs in
            if lhs.id.segmentIndex != rhs.id.segmentIndex {
                return lhs.id.segmentIndex < rhs.id.segmentIndex
            }
            return lhs.id.chunkIndex < rhs.id.chunkIndex
        }
        let grouped = Dictionary(grouping: ordered, by: { $0.id.segmentIndex })
        let segmentIndices = grouped.keys.sorted()
        guard let lastSegmentIndex = segmentIndices.last,
              segmentIndices == Array(UInt32(0)...lastSegmentIndex) else {
            throw RideRouteRecorderError.corruptDraft(sessionID)
        }

        var pointCount = 0
        var previousSequence: UInt64?
        for segmentIndex in segmentIndices {
            guard let segmentChunks = grouped[segmentIndex] else {
                throw RideRouteRecorderError.corruptDraft(sessionID)
            }
            let sortedChunks = segmentChunks.sorted { $0.id.chunkIndex < $1.id.chunkIndex }
            guard sortedChunks.map(\.id.chunkIndex) == Array(UInt32(0)..<UInt32(sortedChunks.count)) else {
                throw RideRouteRecorderError.corruptDraft(sessionID)
            }

            for point in sortedChunks.flatMap(\.points) {
                if let previousSequence, point.sequence <= previousSequence {
                    throw RideRouteRecorderError.corruptDraft(sessionID)
                }
                previousSequence = point.sequence
                pointCount += 1
            }
        }

        guard let lastSequence = previousSequence else {
            throw RideRouteRecorderError.corruptDraft(sessionID)
        }
        return DraftValidation(
            pointCount: pointCount,
            lastSequence: lastSequence,
            lastSegmentIndex: lastSegmentIndex,
            segmentIndices: segmentIndices
        )
    }
}
