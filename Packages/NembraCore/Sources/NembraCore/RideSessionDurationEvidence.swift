import Foundation

public enum RideSessionDurationEvidenceError: Error, Equatable, Sendable {
    case invalidObservationSegment
    case sessionMismatch
    case conflictingSegmentIdentity
    case closedSegmentCannotExtend
    case segmentIdentityReused
    case retiredProcessGenerationReused
    case restoredProcessGenerationReused
    case unexpectedSequence
    case invalidGapClassification
    case sequenceExhausted
    case durationOverflow
}

/// Coverage of the elapsed-time evidence Nembra actually observed for a ride session.
///
/// `partial` means at least one interval before or between observation segments was not
/// observed. The missing interval is never reconstructed from wall-clock timestamps.
public enum RideSessionDurationCoverage: String, Codable, Equatable, Sendable {
    case unknown
    case complete
    case partial
}

/// Durable projection of one contiguous process-local monotonic observation interval.
///
/// Raw uptime values are deliberately not persisted because they are meaningful only inside
/// their originating process/boot epoch. Only their checked difference is durable. A session
/// may have more than one segment in the same process when app suspension or another explicit
/// evidence interruption creates an unobserved interval.
///
/// `segmentID` is an idempotency identity for repeated checkpoints of this exact interval.
/// `processGenerationID` identifies the process generation that produced it; callers should
/// generate a new process-generation identity after relaunch instead of restoring an old one
/// as active.
public struct RideSessionDurationObservedSegment: Codable, Equatable, Sendable {
    public let sessionID: UUID
    public let segmentID: UUID
    public let processGenerationID: UUID
    public let sequenceNumber: UInt64
    public let observedDurationNanoseconds: UInt64
    public let followsUnobservedInterval: Bool

    public init(
        sessionID: UUID,
        segmentID: UUID,
        processGenerationID: UUID,
        sequenceNumber: UInt64,
        observedFromUptimeNanoseconds: UInt64,
        observedThroughUptimeNanoseconds: UInt64,
        followsUnobservedInterval: Bool
    ) throws {
        guard observedThroughUptimeNanoseconds >= observedFromUptimeNanoseconds else {
            throw RideSessionDurationEvidenceError.invalidObservationSegment
        }

        self.sessionID = sessionID
        self.segmentID = segmentID
        self.processGenerationID = processGenerationID
        self.sequenceNumber = sequenceNumber
        self.observedDurationNanoseconds =
            observedThroughUptimeNanoseconds - observedFromUptimeNanoseconds
        self.followsUnobservedInterval = followsUnobservedInterval
    }

    private enum CodingKeys: String, CodingKey {
        case sessionID
        case segmentID
        case processGenerationID
        case sequenceNumber
        case observedDurationNanoseconds
        case followsUnobservedInterval
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.sessionID = try container.decode(UUID.self, forKey: .sessionID)
        self.segmentID = try container.decode(UUID.self, forKey: .segmentID)
        self.processGenerationID = try container.decode(UUID.self, forKey: .processGenerationID)
        self.sequenceNumber = try container.decode(UInt64.self, forKey: .sequenceNumber)
        self.observedDurationNanoseconds = try container.decode(
            UInt64.self,
            forKey: .observedDurationNanoseconds
        )
        self.followsUnobservedInterval = try container.decode(
            Bool.self,
            forKey: .followsUnobservedInterval
        )
    }
}

public struct RideSessionDurationEvidenceSnapshot: Equatable, Sendable {
    public let sessionID: UUID
    /// Nil means Nembra has no monotonic elapsed-time evidence yet. A real observed
    /// zero-duration segment remains `.some(0)` and is distinct from unavailable.
    public let observedDurationNanoseconds: UInt64?
    public let coverage: RideSessionDurationCoverage
    public let observationSegmentCount: Int

#if SWIFT_PACKAGE
    /// Package tests and package-owned producers may construct snapshots directly.
    /// App-target code must not gain the same authority when this source is compiled
    /// directly into Nembra's manually selected Core source set.
    package init(
        sessionID: UUID,
        observedDurationNanoseconds: UInt64?,
        coverage: RideSessionDurationCoverage,
        observationSegmentCount: Int
    ) {
        self.sessionID = sessionID
        self.observedDurationNanoseconds = observedDurationNanoseconds
        self.coverage = coverage
        self.observationSegmentCount = observationSegmentCount
    }
#else
    /// Direct-source app builds keep snapshot minting in this file so the duration
    /// accumulator remains the only production projection authority.
    fileprivate init(
        sessionID: UUID,
        observedDurationNanoseconds: UInt64?,
        coverage: RideSessionDurationCoverage,
        observationSegmentCount: Int
    ) {
        self.sessionID = sessionID
        self.observedDurationNanoseconds = observedDurationNanoseconds
        self.coverage = coverage
        self.observationSegmentCount = observationSegmentCount
    }
#endif

    public var hasUnobservedInterval: Bool {
        coverage == .partial
    }
}

public enum RideSessionDurationUpsertResult: Equatable, Sendable {
    case inserted
    case extended(additionalNanoseconds: UInt64)
    case idempotentReplay
    case staleReplayIgnored
}

/// Crash-safe ride-session elapsed-time evidence assembled from contiguous process-local
/// monotonic observation segments. It never uses `Date` subtraction to fill evidence gaps.
///
/// A caller may checkpoint one observation segment repeatedly. Replaying that segment with
/// a longer observed duration extends it by only the new delta; an older checkpoint is
/// ignored. Once a later segment begins, earlier segments are sealed and cannot grow. A new
/// segment must use the next sequence number and explicitly acknowledge the unobserved interval
/// separating it from the previous segment. Its process generation may be the same (for an
/// in-process suspension/interruption) or different (for relaunch), but a retired generation
/// cannot reappear after a different process generation has begun.
///
/// The default initializer means observation begins at the ride/session boundary, so sequence
/// zero must not claim an earlier gap. Set `beginsAfterUnobservedInterval` only when attaching
/// to a ride after elapsed time was already unobserved (for example conservative recovery);
/// sequence zero must then acknowledge that initial gap and coverage becomes `.partial`.
///
/// Decoding is a durable-restoration boundary. If decoded evidence already contains a segment,
/// that segment is sealed: it may be replayed idempotently/stale, but it cannot be extended and
/// the next inserted segment must use a different process-generation identity. If decoded
/// evidence is still empty, the first later segment must acknowledge an initial unobserved
/// interval. Both rules prevent a caller from stretching process-local monotonic truth across
/// relaunch merely because a checkpoint happened before useful elapsed-time evidence existed.
///
/// Fresh construction, mutation, and snapshot projection are package-scoped. Codable remains
/// public as the durable import/export representation, but an external feature cannot operate a
/// decoded/copied value as a fresh ride observer or project it into completed-duration evidence.
/// A future app-facing creator must be owned by the ride lifecycle and keep the accumulator
/// encapsulated so one observation authority exists per active session.
public struct RideSessionDurationEvidenceAccumulator: Codable, Equatable, Sendable {
    public let sessionID: UUID
    public let beginsAfterUnobservedInterval: Bool
    private var observationSegments: [RideSessionDurationObservedSegment]
    private var totalObservedDurationNanoseconds: UInt64
    private var requiresFreshProcessGeneration: Bool
    private var requiresInitialRecoveryGap: Bool

    package init(
        sessionID: UUID,
        beginsAfterUnobservedInterval: Bool = false
    ) {
        self.sessionID = sessionID
        self.beginsAfterUnobservedInterval = beginsAfterUnobservedInterval
        self.observationSegments = []
        self.totalObservedDurationNanoseconds = 0
        self.requiresFreshProcessGeneration = false
        self.requiresInitialRecoveryGap = false
    }

    package var snapshot: RideSessionDurationEvidenceSnapshot {
        let duration: UInt64? = observationSegments.isEmpty
            ? nil
            : totalObservedDurationNanoseconds
        let coverage: RideSessionDurationCoverage
        if observationSegments.isEmpty {
            coverage = .unknown
        } else if observationSegments.contains(where: { $0.followsUnobservedInterval }) {
            coverage = .partial
        } else {
            coverage = .complete
        }

        return RideSessionDurationEvidenceSnapshot(
            sessionID: sessionID,
            observedDurationNanoseconds: duration,
            coverage: coverage,
            observationSegmentCount: observationSegments.count
        )
    }

    @discardableResult
    package mutating func upsert(
        _ segment: RideSessionDurationObservedSegment
    ) throws -> RideSessionDurationUpsertResult {
        guard segment.sessionID == sessionID else {
            throw RideSessionDurationEvidenceError.sessionMismatch
        }

        if let existingIndex = observationSegments.firstIndex(
            where: { $0.sequenceNumber == segment.sequenceNumber }
        ) {
            let existing = observationSegments[existingIndex]
            guard existing.segmentID == segment.segmentID,
                  existing.processGenerationID == segment.processGenerationID,
                  existing.followsUnobservedInterval == segment.followsUnobservedInterval else {
                throw RideSessionDurationEvidenceError.conflictingSegmentIdentity
            }

            if segment.observedDurationNanoseconds == existing.observedDurationNanoseconds {
                return .idempotentReplay
            }
            if segment.observedDurationNanoseconds < existing.observedDurationNanoseconds {
                return .staleReplayIgnored
            }
            guard existingIndex == observationSegments.index(before: observationSegments.endIndex),
                  !requiresFreshProcessGeneration else {
                throw RideSessionDurationEvidenceError.closedSegmentCannotExtend
            }

            let additional = segment.observedDurationNanoseconds - existing.observedDurationNanoseconds
            let (newTotal, overflow) = totalObservedDurationNanoseconds
                .addingReportingOverflow(additional)
            guard !overflow else {
                throw RideSessionDurationEvidenceError.durationOverflow
            }

            observationSegments[existingIndex] = segment
            totalObservedDurationNanoseconds = newTotal
            return .extended(additionalNanoseconds: additional)
        }

        guard !observationSegments.contains(where: { $0.segmentID == segment.segmentID }) else {
            throw RideSessionDurationEvidenceError.segmentIdentityReused
        }

        let expectedSequence: UInt64
        if let lastSequence = observationSegments.last?.sequenceNumber {
            let (next, overflow) = lastSequence.addingReportingOverflow(1)
            guard !overflow else {
                throw RideSessionDurationEvidenceError.sequenceExhausted
            }
            expectedSequence = next
        } else {
            expectedSequence = 0
        }

        guard segment.sequenceNumber == expectedSequence else {
            throw RideSessionDurationEvidenceError.unexpectedSequence
        }

        if expectedSequence == 0 {
            let requiresGap = beginsAfterUnobservedInterval || requiresInitialRecoveryGap
            guard segment.followsUnobservedInterval == requiresGap else {
                throw RideSessionDurationEvidenceError.invalidGapClassification
            }
        } else {
            guard segment.followsUnobservedInterval else {
                throw RideSessionDurationEvidenceError.invalidGapClassification
            }
        }

        if requiresFreshProcessGeneration,
           let previousSegment = observationSegments.last,
           previousSegment.processGenerationID == segment.processGenerationID {
            throw RideSessionDurationEvidenceError.restoredProcessGenerationReused
        }

        if let previousSegment = observationSegments.last,
           previousSegment.processGenerationID != segment.processGenerationID,
           observationSegments.contains(where: {
               $0.processGenerationID == segment.processGenerationID
           }) {
            throw RideSessionDurationEvidenceError.retiredProcessGenerationReused
        }

        let (newTotal, overflow) = totalObservedDurationNanoseconds
            .addingReportingOverflow(segment.observedDurationNanoseconds)
        guard !overflow else {
            throw RideSessionDurationEvidenceError.durationOverflow
        }

        observationSegments.append(segment)
        totalObservedDurationNanoseconds = newTotal
        requiresFreshProcessGeneration = false
        requiresInitialRecoveryGap = false
        return .inserted
    }

    /// Equality compares durable ride evidence only. Process-local continuation authority is
    /// intentionally excluded because serialization seals it and it is not persisted evidence.
    public static func == (
        lhs: RideSessionDurationEvidenceAccumulator,
        rhs: RideSessionDurationEvidenceAccumulator
    ) -> Bool {
        lhs.sessionID == rhs.sessionID &&
            lhs.beginsAfterUnobservedInterval == rhs.beginsAfterUnobservedInterval &&
            lhs.observationSegments == rhs.observationSegments &&
            lhs.totalObservedDurationNanoseconds == rhs.totalObservedDurationNanoseconds
    }

    private enum CodingKeys: String, CodingKey {
        case sessionID
        case beginsAfterUnobservedInterval
        case observationSegments
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedSessionID = try container.decode(UUID.self, forKey: .sessionID)
        let decodedBeginsAfterUnobservedInterval = try container.decodeIfPresent(
            Bool.self,
            forKey: .beginsAfterUnobservedInterval
        ) ?? false
        let decodedSegments = try container.decode(
            [RideSessionDurationObservedSegment].self,
            forKey: .observationSegments
        )

        self.init(
            sessionID: decodedSessionID,
            beginsAfterUnobservedInterval: decodedBeginsAfterUnobservedInterval
        )
        do {
            for segment in decodedSegments {
                try upsert(segment)
            }
            requiresFreshProcessGeneration = !decodedSegments.isEmpty
            requiresInitialRecoveryGap = decodedSegments.isEmpty
        } catch {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Ride session duration evidence is structurally invalid."
                )
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sessionID, forKey: .sessionID)
        try container.encode(
            beginsAfterUnobservedInterval,
            forKey: .beginsAfterUnobservedInterval
        )
        try container.encode(observationSegments, forKey: .observationSegments)
    }
}
