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
///
/// Codable is a storage/wire representation only. Decoding generic bytes can
/// reconstruct structurally valid fields, but it deliberately does not restore
/// production authority. A trusted NembraCore storage adapter must rebind decoded
/// fields to the exact immutable completed ride before the evidence may re-enter
/// History/Statistics as observed duration truth.
public struct CompletedRideDurationEvidence: Codable, Equatable, Sendable {
    private enum Authority: Equatable, Sendable {
        case trusted
        case importedUntrusted
    }

    public let sessionID: UUID
    public let rideContinuity: RideSessionContinuity
    public let observedDurationNanoseconds: UInt64?
    public let coverage: RideSessionDurationCoverage
    public let observationSegmentCount: Int
    private let authority: Authority

    /// True only for lifecycle-bound evidence or evidence explicitly rebound by a
    /// trusted NembraCore storage boundary. Generic Codable import is always false.
    public var isTrustedForProduction: Bool {
        authority == .trusted
    }

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
            observationSegmentCount: duration.observationSegmentCount,
            authority: .trusted
        )
    }

    /// Verifies that this immutable duration projection is trusted for production
    /// use and still belongs to the supplied completed-ride evidence.
    ///
    /// Generic decoded/imported evidence fails here even when its visible fields
    /// match a real ride. This prevents persisted or caller-authored JSON from
    /// becoming fresh observed-duration authority merely by matching UUID and
    /// continuity metadata.
    public func validate(against completedRide: CompletedRideEvidence) throws {
        guard isTrustedForProduction else {
            throw CompletedRideDurationEvidenceError.invalidDurationEvidence
        }
        try validateIdentity(against: completedRide)
    }

#if SWIFT_PACKAGE
    /// Re-establishes production authority only at a trusted package storage
    /// boundary after rebinding imported fields to the exact immutable ride.
    ///
    /// External package clients cannot call this. Generic Codable remains useful
    /// for durable storage and offline inspection without becoming an authority
    /// minting surface.
    package static func trustedRestored(
        _ imported: CompletedRideDurationEvidence,
        matching completedRide: CompletedRideEvidence
    ) throws -> CompletedRideDurationEvidence {
        try imported.validateIdentity(against: completedRide)
        return try CompletedRideDurationEvidence(
            sessionID: imported.sessionID,
            rideContinuity: imported.rideContinuity,
            observedDurationNanoseconds: imported.observedDurationNanoseconds,
            coverage: imported.coverage,
            observationSegmentCount: imported.observationSegmentCount,
            authority: .trusted
        )
    }
#endif

    private func validateIdentity(against completedRide: CompletedRideEvidence) throws {
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
        observationSegmentCount: Int,
        authority: Authority
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
            // this binding/decoding boundary instead of letting malformed history
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
        self.authority = authority
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
                ),
                authority: .importedUntrusted
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