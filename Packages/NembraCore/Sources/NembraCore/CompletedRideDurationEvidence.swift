import Foundation

public enum CompletedRideDurationEvidenceError: Error, Equatable, Sendable {
    case sessionMismatch
    case continuityMismatch
    case invalidDurationEvidence
}

/// Durable elapsed-time evidence bound to one immutable completed ride.
///
/// This type exists specifically so History/Statistics never need to infer ride
/// duration by subtracting `CompletedRideEvidence` wall-clock dates. Those dates
/// remain timeline/presentation evidence and may legitimately move backward or
/// jump forward when the system clock changes during a ride.
///
/// `observedDurationNanoseconds` is the sum of process-local monotonic intervals
/// Nembra actually observed. `coverage == .partial` means at least one elapsed
/// interval is explicitly unknown; that missing time must not be reconstructed
/// from wall-clock timestamps. `nil` with `.unknown` is unavailable evidence,
/// not a measured zero-duration ride.
public struct CompletedRideDurationEvidence: Codable, Equatable, Sendable {
    public let sessionID: UUID
    public let rideContinuity: RideSessionContinuity
    public let observedDurationNanoseconds: UInt64?
    public let coverage: RideSessionDurationCoverage
    public let observationSegmentCount: Int

    /// Binds duration evidence to a completed ride without consulting wall-clock
    /// deltas. The completed ride's continuity is retained as a cross-check at
    /// future persistence/read boundaries.
    public init(
        completedRide: CompletedRideEvidence,
        duration: RideSessionDurationEvidenceSnapshot
    ) throws {
        guard completedRide.sessionID == duration.sessionID else {
            throw CompletedRideDurationEvidenceError.sessionMismatch
        }

        try self.init(
            sessionID: completedRide.sessionID,
            rideContinuity: completedRide.continuity,
            observedDurationNanoseconds: duration.observedDurationNanoseconds,
            coverage: duration.coverage,
            observationSegmentCount: duration.observationSegmentCount
        )
    }

    /// Verifies that this immutable duration projection still belongs to the
    /// supplied completed-ride evidence before a caller joins the two records.
    public func validate(against completedRide: CompletedRideEvidence) throws {
        guard completedRide.sessionID == sessionID else {
            throw CompletedRideDurationEvidenceError.sessionMismatch
        }
        guard completedRide.continuity == rideContinuity else {
            throw CompletedRideDurationEvidenceError.continuityMismatch
        }
    }

    private init(
        sessionID: UUID,
        rideContinuity: RideSessionContinuity,
        observedDurationNanoseconds: UInt64?,
        coverage: RideSessionDurationCoverage,
        observationSegmentCount: Int
    ) throws {
        guard observationSegmentCount >= 0 else {
            throw CompletedRideDurationEvidenceError.invalidDurationEvidence
        }

        switch observedDurationNanoseconds {
        case nil:
            guard coverage == .unknown,
                  observationSegmentCount == 0 else {
                throw CompletedRideDurationEvidenceError.invalidDurationEvidence
            }

        case .some:
            guard coverage != .unknown,
                  observationSegmentCount > 0 else {
                throw CompletedRideDurationEvidenceError.invalidDurationEvidence
            }

            // The duration accumulator can report complete coverage only when
            // exactly one contiguous observation segment exists. Every segment
            // after sequence zero must explicitly follow an unobserved interval,
            // which makes coverage partial. Reject impossible durable states at
            // this binding/decoding boundary instead of letting forged history
            // claim complete process-local elapsed-time coverage.
            if coverage == .complete,
               observationSegmentCount != 1 {
                throw CompletedRideDurationEvidenceError.invalidDurationEvidence
            }
        }

        // A ride reconstructed from a durable checkpoint necessarily crossed a
        // process interval that this process-local monotonic model could not
        // observe. It may have partial or unavailable duration evidence, but it
        // cannot truthfully claim complete elapsed-time coverage.
        if rideContinuity == .recoveredCheckpoint,
           coverage == .complete {
            throw CompletedRideDurationEvidenceError.invalidDurationEvidence
        }

        self.sessionID = sessionID
        self.rideContinuity = rideContinuity
        self.observedDurationNanoseconds = observedDurationNanoseconds
        self.coverage = coverage
        self.observationSegmentCount = observationSegmentCount
    }

    private enum CodingKeys: String, CodingKey {
        case sessionID
        case rideContinuity
        case observedDurationNanoseconds
        case coverage
        case observationSegmentCount
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                sessionID: container.decode(UUID.self, forKey: .sessionID),
                rideContinuity: container.decode(RideSessionContinuity.self, forKey: .rideContinuity),
                observedDurationNanoseconds: container.decodeIfPresent(
                    UInt64.self,
                    forKey: .observedDurationNanoseconds
                ),
                coverage: container.decode(
                    RideSessionDurationCoverage.self,
                    forKey: .coverage
                ),
                observationSegmentCount: container.decode(
                    Int.self,
                    forKey: .observationSegmentCount
                )
            )
        } catch let error as CompletedRideDurationEvidenceError {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Completed ride duration evidence is structurally invalid: \(error)."
                )
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sessionID, forKey: .sessionID)
        try container.encode(rideContinuity, forKey: .rideContinuity)
        try container.encodeIfPresent(
            observedDurationNanoseconds,
            forKey: .observedDurationNanoseconds
        )
        try container.encode(coverage, forKey: .coverage)
        try container.encode(observationSegmentCount, forKey: .observationSegmentCount)
    }
}
