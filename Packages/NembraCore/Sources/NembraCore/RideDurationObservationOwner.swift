import Foundation

public enum RideDurationObservationOwnerError: Error, Equatable, Sendable {
    case sessionAlreadyActive
    case noActiveSession
    case sessionMismatch
    case nonMonotonicObservation
    case sequenceExhausted
}

/// Owns exactly one active ride-duration observation authority.
///
/// The owner converts explicit lifecycle boundaries plus process-local monotonic
/// uptime into `RideSessionDurationEvidenceAccumulator` segments. It never uses
/// `Date`, never advances on a display timer, and never fills an interval after
/// `markObservationGap` until a new segment is explicitly observed.
///
/// This is application-lifecycle integration, not scooter telemetry. A caller is
/// responsible for invoking it only from the single authoritative ride lifecycle.
public struct RideDurationObservationOwner: Sendable {
    private struct ActiveSegment: Sendable {
        let sessionID: UUID
        let segmentID: UUID
        let processGenerationID: UUID
        let sequenceNumber: UInt64
        let beganAtUptimeNanoseconds: UInt64
        var observedThroughUptimeNanoseconds: UInt64
        let followsUnobservedInterval: Bool
    }

    private var accumulator: RideSessionDurationEvidenceAccumulator?
    private var activeSegment: ActiveSegment?
    private var nextSegmentFollowsGap = false
    private var lastSeenUptimeNanoseconds: UInt64?

    public init() {}

    public var activeSessionID: UUID? {
        accumulator?.sessionID
    }

    public var snapshot: RideSessionDurationEvidenceSnapshot? {
        accumulator?.snapshot
    }

    /// Begins one ride/session observation authority.
    ///
    /// `beginsAfterUnobservedInterval` must be true when attaching to a recovered
    /// ride whose earlier elapsed interval was not observed in this process.
    public mutating func begin(
        sessionID: UUID,
        processGenerationID: UUID,
        atUptimeNanoseconds uptime: UInt64,
        beginsAfterUnobservedInterval: Bool = false
    ) throws {
        guard accumulator == nil else {
            throw RideDurationObservationOwnerError.sessionAlreadyActive
        }

        accumulator = RideSessionDurationEvidenceAccumulator(
            sessionID: sessionID,
            beginsAfterUnobservedInterval: beginsAfterUnobservedInterval
        )
        activeSegment = nil
        nextSegmentFollowsGap = beginsAfterUnobservedInterval
        lastSeenUptimeNanoseconds = uptime

        try startSegment(
            sessionID: sessionID,
            processGenerationID: processGenerationID,
            atUptimeNanoseconds: uptime
        )
    }

    /// Extends the current contiguous observation segment through an authoritative
    /// lifecycle observation. The exact monotonic delta is accumulated; no wall
    /// clock or render cadence participates.
    public mutating func observe(
        sessionID: UUID,
        atUptimeNanoseconds uptime: UInt64
    ) throws {
        guard let accumulator else {
            throw RideDurationObservationOwnerError.noActiveSession
        }
        guard accumulator.sessionID == sessionID else {
            throw RideDurationObservationOwnerError.sessionMismatch
        }
        guard var segment = activeSegment else {
            // A rejected callback inside an explicit observation gap must not
            // advance the chronology floor. The same timestamp may be the first
            // legitimate boundary supplied to `resumeObservation` afterward.
            throw RideDurationObservationOwnerError.noActiveSession
        }
        try admitMonotonic(uptime)

        segment.observedThroughUptimeNanoseconds = uptime
        activeSegment = segment
        try upsertActiveSegment()
    }

    /// Ends the current contiguous segment at a known observation boundary and
    /// records that subsequent elapsed time is unknown until `resumeObservation`.
    public mutating func markObservationGap(
        sessionID: UUID,
        atUptimeNanoseconds uptime: UInt64
    ) throws {
        try observe(sessionID: sessionID, atUptimeNanoseconds: uptime)
        activeSegment = nil
        nextSegmentFollowsGap = true
    }

    /// Starts a fresh contiguous segment after an explicit gap/recovery boundary.
    public mutating func resumeObservation(
        sessionID: UUID,
        processGenerationID: UUID,
        atUptimeNanoseconds uptime: UInt64
    ) throws {
        guard let accumulator else {
            throw RideDurationObservationOwnerError.noActiveSession
        }
        guard accumulator.sessionID == sessionID else {
            throw RideDurationObservationOwnerError.sessionMismatch
        }
        guard activeSegment == nil else {
            throw RideDurationObservationOwnerError.sessionAlreadyActive
        }
        try admitMonotonic(uptime)
        try startSegment(
            sessionID: sessionID,
            processGenerationID: processGenerationID,
            atUptimeNanoseconds: uptime
        )
    }

    /// Finalizes the currently observed boundary and releases this owner for the
    /// next ride. The returned snapshot remains truth-qualified complete/partial.
    public mutating func end(
        sessionID: UUID,
        atUptimeNanoseconds uptime: UInt64
    ) throws -> RideSessionDurationEvidenceSnapshot {
        guard let accumulator else {
            throw RideDurationObservationOwnerError.noActiveSession
        }
        guard accumulator.sessionID == sessionID else {
            throw RideDurationObservationOwnerError.sessionMismatch
        }

        if activeSegment != nil {
            try observe(sessionID: sessionID, atUptimeNanoseconds: uptime)
        } else {
            try admitMonotonic(uptime)
        }

        guard let result = self.accumulator?.snapshot else {
            throw RideDurationObservationOwnerError.noActiveSession
        }
        self.accumulator = nil
        activeSegment = nil
        nextSegmentFollowsGap = false
        lastSeenUptimeNanoseconds = nil
        return result
    }

    private mutating func startSegment(
        sessionID: UUID,
        processGenerationID: UUID,
        atUptimeNanoseconds uptime: UInt64
    ) throws {
        guard let accumulator else {
            throw RideDurationObservationOwnerError.noActiveSession
        }
        let sequence = UInt64(accumulator.snapshot.observationSegmentCount)
        guard sequence < UInt64.max else {
            throw RideDurationObservationOwnerError.sequenceExhausted
        }

        activeSegment = ActiveSegment(
            sessionID: sessionID,
            segmentID: UUID(),
            processGenerationID: processGenerationID,
            sequenceNumber: sequence,
            beganAtUptimeNanoseconds: uptime,
            observedThroughUptimeNanoseconds: uptime,
            followsUnobservedInterval: nextSegmentFollowsGap
        )
        nextSegmentFollowsGap = false
        try upsertActiveSegment()
    }

    private mutating func upsertActiveSegment() throws {
        guard let segment = activeSegment,
              var accumulator else {
            throw RideDurationObservationOwnerError.noActiveSession
        }

        let evidence = try RideSessionDurationObservedSegment(
            sessionID: segment.sessionID,
            segmentID: segment.segmentID,
            processGenerationID: segment.processGenerationID,
            sequenceNumber: segment.sequenceNumber,
            observedFromUptimeNanoseconds: segment.beganAtUptimeNanoseconds,
            observedThroughUptimeNanoseconds: segment.observedThroughUptimeNanoseconds,
            followsUnobservedInterval: segment.followsUnobservedInterval
        )
        _ = try accumulator.upsert(evidence)
        self.accumulator = accumulator
    }

    private mutating func admitMonotonic(_ uptime: UInt64) throws {
        if let lastSeenUptimeNanoseconds,
           uptime <= lastSeenUptimeNanoseconds {
            throw RideDurationObservationOwnerError.nonMonotonicObservation
        }
        lastSeenUptimeNanoseconds = uptime
    }
}
