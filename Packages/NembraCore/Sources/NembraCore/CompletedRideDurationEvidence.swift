import Foundation

public enum CompletedRideDurationEvidenceError: Error, Equatable, Sendable {
    case sessionMismatch
    case continuityMismatch
    case invalidDurationEvidence
}

/// Durable elapsed-time evidence bound to one immutable completed ride.
///
/// This authoritative type is deliberately **not Decodable**. Generic persisted,
/// imported, or caller-authored bytes cannot become observed monotonic-duration
/// authority merely by matching a ride UUID and continuity label.
///
/// `observedDurationNanoseconds` is the sum of process-local monotonic intervals
/// Nembra actually observed. `coverage == .partial` means at least one elapsed
/// interval is explicitly unknown; that missing time must not be reconstructed
/// from wall-clock timestamps. `nil` with `.unknown` is unavailable evidence,
/// not a measured zero-duration ride.
public struct CompletedRideDurationEvidence: Equatable, Sendable {
    public let sessionID: UUID
    public let rideContinuity: RideSessionContinuity
    public let observedDurationNanoseconds: UInt64?
    public let coverage: RideSessionDurationCoverage
    public let observationSegmentCount: Int

    /// Binds package-produced duration evidence to a completed ride without
    /// consulting wall-clock deltas.
    public init(
        completedRide: CompletedRideEvidence,
        duration: RideSessionDurationEvidenceSnapshot
    ) throws {
        guard completedRide.sessionID == duration.sessionID else {
            throw CompletedRideDurationEvidenceError.sessionMismatch
        }

        try CompletedRideDurationEvidenceValidation.validate(
            rideContinuity: completedRide.continuity,
            observedDurationNanoseconds: duration.observedDurationNanoseconds,
            coverage: duration.coverage,
            observationSegmentCount: duration.observationSegmentCount
        )

        self.sessionID = completedRide.sessionID
        self.rideContinuity = completedRide.continuity
        self.observedDurationNanoseconds = duration.observedDurationNanoseconds
        self.coverage = duration.coverage
        self.observationSegmentCount = duration.observationSegmentCount
    }

    /// Verifies that this already-authoritative immutable projection still belongs
    /// to the supplied completed ride.
    public func validate(against completedRide: CompletedRideEvidence) throws {
        guard completedRide.sessionID == sessionID else {
            throw CompletedRideDurationEvidenceError.sessionMismatch
        }
        guard completedRide.continuity == rideContinuity else {
            throw CompletedRideDurationEvidenceError.continuityMismatch
        }
    }

    /// Non-authoritative Codable representation for durable storage and offline QA.
    ///
    /// Converting accepted evidence to an archive is one-way in this contract.
    /// There is intentionally no archive -> `CompletedRideDurationEvidence`
    /// initializer. A future ride store must define an explicit trusted restore
    /// authority boundary before persisted bytes can regain production evidence
    /// status.
    public var persistenceArchive: CompletedRideDurationEvidenceArchive {
        CompletedRideDurationEvidenceArchive(
            validatedSessionID: sessionID,
            rideContinuity: rideContinuity,
            observedDurationNanoseconds: observedDurationNanoseconds,
            coverage: coverage,
            observationSegmentCount: observationSegmentCount
        )
    }
}

/// Structurally validated but **non-authoritative** persisted representation of
/// completed ride duration fields.
///
/// This type may be freely decoded from disk, fixtures, imports, or caller-authored
/// bytes because it cannot be passed where `CompletedRideDurationEvidence` is
/// required. Structural validity is not production evidence authority.
public struct CompletedRideDurationEvidenceArchive: Codable, Equatable, Sendable {
    public let sessionID: UUID
    public let rideContinuity: RideSessionContinuity
    public let observedDurationNanoseconds: UInt64?
    public let coverage: RideSessionDurationCoverage
    public let observationSegmentCount: Int

    public init(
        sessionID: UUID,
        rideContinuity: RideSessionContinuity,
        observedDurationNanoseconds: UInt64?,
        coverage: RideSessionDurationCoverage,
        observationSegmentCount: Int
    ) throws {
        try CompletedRideDurationEvidenceValidation.validate(
            rideContinuity: rideContinuity,
            observedDurationNanoseconds: observedDurationNanoseconds,
            coverage: coverage,
            observationSegmentCount: observationSegmentCount
        )

        self.sessionID = sessionID
        self.rideContinuity = rideContinuity
        self.observedDurationNanoseconds = observedDurationNanoseconds
        self.coverage = coverage
        self.observationSegmentCount = observationSegmentCount
    }

    fileprivate init(
        validatedSessionID sessionID: UUID,
        rideContinuity: RideSessionContinuity,
        observedDurationNanoseconds: UInt64?,
        coverage: RideSessionDurationCoverage,
        observationSegmentCount: Int
    ) {
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
                    debugDescription: "Completed ride duration archive is structurally invalid: \(error)."
                )
            )
        }
    }
}

private enum CompletedRideDurationEvidenceValidation {
    static func validate(
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
            // which makes coverage partial.
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
    }
}