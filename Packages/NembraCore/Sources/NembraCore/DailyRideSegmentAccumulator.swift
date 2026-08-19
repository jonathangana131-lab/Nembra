import Foundation

public enum DailyRideSegmentAccumulatorError: Error, Equatable, Sendable {
    case invalidCheckpoint
    case sessionMismatch(expected: UUID, actual: UUID)
    case conflictingReplay(sequence: UInt64)
    case nonmonotonicSequence(previous: UInt64, incoming: UInt64)
    case nonmonotonicUptime(previous: UInt64, incoming: UInt64)
    case cumulativeDistanceRegressed(sequence: UInt64)
    case cumulativeDurationRegressed(sequence: UInt64)
    case segmentSequenceExhausted
    case invalidRestoredState
}

/// A durable receipt for one checkpoint that the ride-evidence authority has
/// already accepted.
///
/// Values are cumulative for the ride session, never UI counters. The frozen
/// `localDay` records the calendar and time-zone identity in force when the
/// receipt was accepted. A receipt with unavailable or conflicting distance
/// carries no source because it has no value that may enter a daily aggregate.
public struct AcceptedDailyRideCheckpoint: Codable, Equatable, Sendable {
    public let sessionID: UUID
    public let sequence: UInt64
    public let uptimeNanoseconds: UInt64
    public let wallDate: Date
    public let localDay: RideLocalDay
    public let cumulativeDistanceMeters: DailyRideMetricEvidence
    public let cumulativeDurationSeconds: DailyRideMetricEvidence
    public let distanceSource: RideDistanceSource?
    public let continuity: RideSessionContinuity

    private enum CodingKeys: String, CodingKey {
        case sessionID
        case sequence
        case uptimeNanoseconds
        case wallDate
        case localDay
        case cumulativeDistanceMeters
        case cumulativeDurationSeconds
        case distanceSource
        case continuity
    }

    public init(
        sessionID: UUID,
        sequence: UInt64,
        uptimeNanoseconds: UInt64,
        wallDate: Date,
        localDay: RideLocalDay,
        cumulativeDistanceMeters: DailyRideMetricEvidence,
        cumulativeDurationSeconds: DailyRideMetricEvidence,
        distanceSource: RideDistanceSource?,
        continuity: RideSessionContinuity
    ) throws {
        guard wallDate.timeIntervalSinceReferenceDate.isFinite,
              localDay.contains(segmentStart: wallDate, segmentEnd: wallDate) else {
            throw DailyRideSegmentAccumulatorError.invalidCheckpoint
        }
        if cumulativeDistanceMeters.value != nil {
            guard distanceSource != nil else {
                throw DailyRideSegmentAccumulatorError.invalidCheckpoint
            }
        } else if distanceSource != nil {
            throw DailyRideSegmentAccumulatorError.invalidCheckpoint
        }

        self.sessionID = sessionID
        self.sequence = sequence
        self.uptimeNanoseconds = uptimeNanoseconds
        self.wallDate = wallDate
        self.localDay = localDay
        self.cumulativeDistanceMeters = cumulativeDistanceMeters
        self.cumulativeDurationSeconds = cumulativeDurationSeconds
        self.distanceSource = distanceSource
        self.continuity = continuity
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                sessionID: container.decode(UUID.self, forKey: .sessionID),
                sequence: container.decode(UInt64.self, forKey: .sequence),
                uptimeNanoseconds: container.decode(UInt64.self, forKey: .uptimeNanoseconds),
                wallDate: container.decode(Date.self, forKey: .wallDate),
                localDay: container.decode(RideLocalDay.self, forKey: .localDay),
                cumulativeDistanceMeters: container.decode(
                    DailyRideMetricEvidence.self,
                    forKey: .cumulativeDistanceMeters
                ),
                cumulativeDurationSeconds: container.decode(
                    DailyRideMetricEvidence.self,
                    forKey: .cumulativeDurationSeconds
                ),
                distanceSource: container.decodeIfPresent(
                    RideDistanceSource.self,
                    forKey: .distanceSource
                ),
                continuity: container.decode(RideSessionContinuity.self, forKey: .continuity)
            )
        } catch DailyRideSegmentAccumulatorError.invalidCheckpoint {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Invalid accepted daily-ride checkpoint."
                )
            )
        }
    }
}

public enum DailyRideCheckpointAccumulationDisposition: String, Equatable, Sendable {
    /// The first durable anchor for the session; no interval exists yet.
    case initialAnchor
    /// One interval remained under the same frozen local-day identity.
    case sameLocalDay
    /// A checkpoint landed exactly on a shared day boundary, so the preceding
    /// delta could be assigned without interpolation.
    case exactLocalDayBoundary
    /// Calendar or time-zone ownership changed between checkpoints without an
    /// accepted checkpoint at the boundary. No metric delta is apportioned.
    case unobservedIdentityBoundary
    /// Wall time moved backward (or stopped) while monotonic uptime advanced.
    /// Daily placement is unavailable even though the session remains ordered.
    case wallClockRegression
    /// This exact already-acknowledged receipt was replayed.
    case idempotentReplay
}

/// A two-phase persistence proposal.
///
/// The caller must atomically persist `segmentsToPersist` and
/// `accumulatorAfterPersistence`, then replace its in-memory accumulator. If
/// persistence fails, it keeps the prior accumulator. Preparing the same receipt
/// again then yields the same stable segment IDs and bytes; nothing has been
/// acknowledged merely because a proposal was computed.
public struct DailyRideSegmentCommitProposal: Equatable, Sendable {
    public let checkpoint: AcceptedDailyRideCheckpoint
    public let disposition: DailyRideCheckpointAccumulationDisposition
    public let segmentsToPersist: [AcceptedRideSegment]
    public let accumulatorAfterPersistence: DailyRideSegmentAccumulator

    fileprivate init(
        checkpoint: AcceptedDailyRideCheckpoint,
        disposition: DailyRideCheckpointAccumulationDisposition,
        segmentsToPersist: [AcceptedRideSegment],
        accumulatorAfterPersistence: DailyRideSegmentAccumulator
    ) {
        self.checkpoint = checkpoint
        self.disposition = disposition
        self.segmentsToPersist = segmentsToPersist
        self.accumulatorAfterPersistence = accumulatorAfterPersistence
    }
}

/// Turns accepted cumulative ride checkpoints into immutable, day-aligned
/// ledger segments.
///
/// The accumulator never derives elapsed time from `Date`, never proportionally
/// splits a cumulative delta across an unobserved local-day/time-zone boundary,
/// and never mutates while preparing a persistence proposal. Its full receipt
/// history is retained so any acknowledged sequence can be replayed
/// idempotently and a reused sequence with different evidence fails closed.
public struct DailyRideSegmentAccumulator: Codable, Equatable, Sendable {
    public let sessionID: UUID
    public private(set) var nextSegmentSequence: UInt64
    private var acknowledgedCheckpoints: [AcceptedDailyRideCheckpoint]

    public var lastAcknowledgedCheckpoint: AcceptedDailyRideCheckpoint? {
        acknowledgedCheckpoints.last
    }

    public var acknowledgedCheckpointCount: Int {
        acknowledgedCheckpoints.count
    }

    private enum CodingKeys: String, CodingKey {
        case sessionID
        case nextSegmentSequence
        case acknowledgedCheckpoints
    }

    private static let evidenceRevision = "accepted-daily-checkpoint-accumulator-v1"

    public init(sessionID: UUID) {
        self.sessionID = sessionID
        self.nextSegmentSequence = 0
        self.acknowledgedCheckpoints = []
    }

    private init(
        sessionID: UUID,
        nextSegmentSequence: UInt64,
        acknowledgedCheckpoints: [AcceptedDailyRideCheckpoint]
    ) {
        self.sessionID = sessionID
        self.nextSegmentSequence = nextSegmentSequence
        self.acknowledgedCheckpoints = acknowledgedCheckpoints
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedSessionID = try container.decode(UUID.self, forKey: .sessionID)
        let decodedNextSequence = try container.decode(UInt64.self, forKey: .nextSegmentSequence)
        let decodedCheckpoints = try container.decode(
            [AcceptedDailyRideCheckpoint].self,
            forKey: .acknowledgedCheckpoints
        )

        do {
            var rebuilt = Self(sessionID: decodedSessionID)
            for checkpoint in decodedCheckpoints {
                let proposal = try rebuilt.prepare(checkpoint)
                guard proposal.disposition != .idempotentReplay else {
                    throw DailyRideSegmentAccumulatorError.invalidRestoredState
                }
                rebuilt = proposal.accumulatorAfterPersistence
            }
            guard rebuilt.nextSegmentSequence == decodedNextSequence else {
                throw DailyRideSegmentAccumulatorError.invalidRestoredState
            }
        } catch {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Invalid restored daily-ride segment accumulator.",
                    underlyingError: error
                )
            )
        }

        self.init(
            sessionID: decodedSessionID,
            nextSegmentSequence: decodedNextSequence,
            acknowledgedCheckpoints: decodedCheckpoints
        )
    }

    /// Builds the exact persistence work for a newly accepted receipt without
    /// acknowledging it. See `DailyRideSegmentCommitProposal` for the required
    /// transactional handoff.
    public func prepare(
        _ checkpoint: AcceptedDailyRideCheckpoint
    ) throws -> DailyRideSegmentCommitProposal {
        guard checkpoint.sessionID == sessionID else {
            throw DailyRideSegmentAccumulatorError.sessionMismatch(
                expected: sessionID,
                actual: checkpoint.sessionID
            )
        }

        if let acknowledged = acknowledgedCheckpoints.first(
            where: { $0.sequence == checkpoint.sequence }
        ) {
            guard acknowledged == checkpoint else {
                throw DailyRideSegmentAccumulatorError.conflictingReplay(
                    sequence: checkpoint.sequence
                )
            }
            return DailyRideSegmentCommitProposal(
                checkpoint: checkpoint,
                disposition: .idempotentReplay,
                segmentsToPersist: [],
                accumulatorAfterPersistence: self
            )
        }

        guard let previous = acknowledgedCheckpoints.last else {
            var receipts = acknowledgedCheckpoints
            receipts.append(checkpoint)
            let next = Self(
                sessionID: sessionID,
                nextSegmentSequence: nextSegmentSequence,
                acknowledgedCheckpoints: receipts
            )
            return DailyRideSegmentCommitProposal(
                checkpoint: checkpoint,
                disposition: .initialAnchor,
                segmentsToPersist: [],
                accumulatorAfterPersistence: next
            )
        }

        guard checkpoint.sequence > previous.sequence else {
            throw DailyRideSegmentAccumulatorError.nonmonotonicSequence(
                previous: previous.sequence,
                incoming: checkpoint.sequence
            )
        }
        guard checkpoint.uptimeNanoseconds > previous.uptimeNanoseconds else {
            throw DailyRideSegmentAccumulatorError.nonmonotonicUptime(
                previous: previous.uptimeNanoseconds,
                incoming: checkpoint.uptimeNanoseconds
            )
        }
        try Self.validateCumulativeEvidence(
            history: acknowledgedCheckpoints,
            current: checkpoint
        )

        let transition = try Self.makeTransition(
            previous: previous,
            current: checkpoint,
            startingSegmentSequence: nextSegmentSequence
        )
        var receipts = acknowledgedCheckpoints
        receipts.append(checkpoint)
        let next = Self(
            sessionID: sessionID,
            nextSegmentSequence: transition.nextSegmentSequence,
            acknowledgedCheckpoints: receipts
        )
        return DailyRideSegmentCommitProposal(
            checkpoint: checkpoint,
            disposition: transition.disposition,
            segmentsToPersist: transition.segments,
            accumulatorAfterPersistence: next
        )
    }

    private struct Transition {
        let disposition: DailyRideCheckpointAccumulationDisposition
        let segments: [AcceptedRideSegment]
        let nextSegmentSequence: UInt64
    }

    private static func validateCumulativeEvidence(
        history: [AcceptedDailyRideCheckpoint],
        current: AcceptedDailyRideCheckpoint
    ) throws {
        if let currentSource = current.distanceSource,
           let currentDistance = current.cumulativeDistanceMeters.value,
           let previousDistance = history.reversed().first(where: {
               $0.distanceSource == currentSource && $0.cumulativeDistanceMeters.value != nil
           })?.cumulativeDistanceMeters.value,
           currentDistance < previousDistance {
            throw DailyRideSegmentAccumulatorError.cumulativeDistanceRegressed(
                sequence: current.sequence
            )
        }
        if let currentDuration = current.cumulativeDurationSeconds.value,
           let previousDuration = history.reversed().first(where: {
               $0.cumulativeDurationSeconds.value != nil
           })?.cumulativeDurationSeconds.value,
           currentDuration < previousDuration {
            throw DailyRideSegmentAccumulatorError.cumulativeDurationRegressed(
                sequence: current.sequence
            )
        }
    }

    private static func makeTransition(
        previous: AcceptedDailyRideCheckpoint,
        current: AcceptedDailyRideCheckpoint,
        startingSegmentSequence: UInt64
    ) throws -> Transition {
        var sequence = startingSegmentSequence
        var segments: [AcceptedRideSegment] = []

        func append(
            localDay: RideLocalDay,
            beganAtDate: Date,
            endedAtDate: Date,
            distance: DailyRideMetricEvidence,
            duration: DailyRideMetricEvidence,
            distanceSource: RideDistanceSource?
        ) throws {
            let segment = try AcceptedRideSegment(
                id: AcceptedRideSegmentID(sessionID: current.sessionID, sequence: sequence),
                localDay: localDay,
                beganAtDate: beganAtDate,
                endedAtDate: endedAtDate,
                distanceMeters: distance,
                durationSeconds: duration,
                distanceSource: distanceSource,
                continuity: current.continuity,
                evidenceRevision: evidenceRevision
            )
            let (next, overflow) = sequence.addingReportingOverflow(1)
            guard !overflow else {
                throw DailyRideSegmentAccumulatorError.segmentSequenceExhausted
            }
            segments.append(segment)
            sequence = next
        }

        if previous.localDay == current.localDay {
            guard current.wallDate > previous.wallDate else {
                try append(
                    localDay: current.localDay,
                    beganAtDate: current.wallDate,
                    endedAtDate: current.wallDate,
                    distance: try unknownBoundaryMetric(
                        previous.cumulativeDistanceMeters,
                        current.cumulativeDistanceMeters
                    ),
                    duration: try unknownBoundaryMetric(
                        previous.cumulativeDurationSeconds,
                        current.cumulativeDurationSeconds
                    ),
                    distanceSource: nil
                )
                return Transition(
                    disposition: .wallClockRegression,
                    segments: segments,
                    nextSegmentSequence: sequence
                )
            }

            let distanceDelta = try distanceDelta(previous: previous, current: current)
            try append(
                localDay: current.localDay,
                beganAtDate: previous.wallDate,
                endedAtDate: current.wallDate,
                distance: distanceDelta.metric,
                duration: try cumulativeDelta(
                    previous.cumulativeDurationSeconds,
                    current.cumulativeDurationSeconds
                ),
                distanceSource: distanceDelta.source
            )
            return Transition(
                disposition: .sameLocalDay,
                segments: segments,
                nextSegmentSequence: sequence
            )
        }

        let isExactAdjacentBoundary = current.wallDate == previous.localDay.endDate
            && current.localDay.startDate == current.wallDate
            && previous.wallDate < current.wallDate
        if isExactAdjacentBoundary {
            let distanceDelta = try distanceDelta(previous: previous, current: current)
            try append(
                localDay: previous.localDay,
                beganAtDate: previous.wallDate,
                endedAtDate: current.wallDate,
                distance: distanceDelta.metric,
                duration: try cumulativeDelta(
                    previous.cumulativeDurationSeconds,
                    current.cumulativeDurationSeconds
                ),
                distanceSource: distanceDelta.source
            )
            return Transition(
                disposition: .exactLocalDayBoundary,
                segments: segments,
                nextSegmentSequence: sequence
            )
        }

        let distanceUnknown = try unknownBoundaryMetric(
            previous.cumulativeDistanceMeters,
            current.cumulativeDistanceMeters
        )
        let durationUnknown = try unknownBoundaryMetric(
            previous.cumulativeDurationSeconds,
            current.cumulativeDurationSeconds
        )
        let oldEnd: Date
        if current.wallDate >= previous.wallDate {
            oldEnd = min(previous.localDay.endDate, current.wallDate)
        } else {
            oldEnd = previous.wallDate
        }
        try append(
            localDay: previous.localDay,
            beganAtDate: previous.wallDate,
            endedAtDate: oldEnd,
            distance: distanceUnknown,
            duration: durationUnknown,
            distanceSource: nil
        )

        let currentStart: Date
        if previous.localDay.endDate <= current.localDay.startDate,
           current.wallDate >= current.localDay.startDate {
            currentStart = current.localDay.startDate
        } else {
            // Overlapping day intervals indicate a time-zone/calendar identity
            // change whose exact change instant is not evidenced. Reopen at the
            // accepted receipt instead of pretending the ride owned the whole
            // current local day.
            currentStart = current.wallDate
        }
        try append(
            localDay: current.localDay,
            beganAtDate: currentStart,
            endedAtDate: current.wallDate,
            distance: distanceUnknown,
            duration: durationUnknown,
            distanceSource: nil
        )
        return Transition(
            disposition: .unobservedIdentityBoundary,
            segments: segments,
            nextSegmentSequence: sequence
        )
    }

    private static func distanceDelta(
        previous: AcceptedDailyRideCheckpoint,
        current: AcceptedDailyRideCheckpoint
    ) throws -> (metric: DailyRideMetricEvidence, source: RideDistanceSource?) {
        if previous.cumulativeDistanceMeters.disposition == .conflicting
            || current.cumulativeDistanceMeters.disposition == .conflicting {
            return (
                try DailyRideMetricEvidence(value: nil, disposition: .conflicting),
                nil
            )
        }
        if previous.cumulativeDistanceMeters.disposition == .unavailable
            || current.cumulativeDistanceMeters.disposition == .unavailable {
            return (
                try DailyRideMetricEvidence(value: nil, disposition: .unavailable),
                nil
            )
        }
        guard previous.distanceSource == current.distanceSource else {
            return (
                try DailyRideMetricEvidence(value: nil, disposition: .conflicting),
                nil
            )
        }
        let metric = try cumulativeDelta(
            previous.cumulativeDistanceMeters,
            current.cumulativeDistanceMeters
        )
        return (metric, metric.value == nil ? nil : current.distanceSource)
    }

    private static func cumulativeDelta(
        _ previous: DailyRideMetricEvidence,
        _ current: DailyRideMetricEvidence
    ) throws -> DailyRideMetricEvidence {
        if previous.disposition == .conflicting || current.disposition == .conflicting {
            return try DailyRideMetricEvidence(value: nil, disposition: .conflicting)
        }
        guard previous.disposition != .unavailable,
              current.disposition != .unavailable,
              let previousValue = previous.value,
              let currentValue = current.value else {
            return try DailyRideMetricEvidence(value: nil, disposition: .unavailable)
        }
        let delta = currentValue - previousValue
        guard delta.isFinite, delta >= 0 else {
            throw DailyRideSegmentAccumulatorError.invalidCheckpoint
        }
        let disposition: DailyRideMetricDisposition =
            previous.disposition == .knownPartial || current.disposition == .knownPartial
                ? .knownPartial
                : .complete
        return try DailyRideMetricEvidence(value: delta, disposition: disposition)
    }

    private static func unknownBoundaryMetric(
        _ previous: DailyRideMetricEvidence,
        _ current: DailyRideMetricEvidence
    ) throws -> DailyRideMetricEvidence {
        let disposition: DailyRideMetricDisposition =
            previous.disposition == .conflicting || current.disposition == .conflicting
                ? .conflicting
                : .unavailable
        return try DailyRideMetricEvidence(value: nil, disposition: disposition)
    }
}
