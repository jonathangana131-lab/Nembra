import Foundation

public enum RideSessionDurationEvidenceError: Error, Equatable, Sendable {
    case invalidProcessSegment
    case sessionMismatch
    case conflictingProcessGeneration
    case processGenerationReused
    case unexpectedSequence
    case missingRecoveryGap
    case sequenceExhausted
    case durationOverflow
}

/// Coverage of the elapsed-time evidence Nembra actually observed for a ride session.
///
/// `partial` means at least one process interruption separated two observed monotonic
/// segments. The missing interval is never reconstructed from wall-clock timestamps.
public enum RideSessionDurationCoverage: String, Codable, Equatable, Sendable {
    case unknown
    case complete
    case partial
}

/// Durable projection of one process-local monotonic observation interval.
///
/// Uptime values themselves are deliberately not persisted because they are meaningful
/// only inside their originating process/boot epoch. Only their checked difference is
/// durable. A new process generation must be represented by a new sequence entry.
public struct RideSessionDurationProcessSegment: Codable, Equatable, Sendable {
    public let sessionID: UUID
    public let processGenerationID: UUID
    public let sequenceNumber: UInt64
    public let observedDurationNanoseconds: UInt64
    public let followsUnobservedInterval: Bool

    public init(
        sessionID: UUID,
        processGenerationID: UUID,
        sequenceNumber: UInt64,
        observedFromUptimeNanoseconds: UInt64,
        observedThroughUptimeNanoseconds: UInt64,
        followsUnobservedInterval: Bool
    ) throws {
        guard observedThroughUptimeNanoseconds >= observedFromUptimeNanoseconds else {
            throw RideSessionDurationEvidenceError.invalidProcessSegment
        }

        self.sessionID = sessionID
        self.processGenerationID = processGenerationID
        self.sequenceNumber = sequenceNumber
        self.observedDurationNanoseconds =
            observedThroughUptimeNanoseconds - observedFromUptimeNanoseconds
        self.followsUnobservedInterval = followsUnobservedInterval
    }

    private enum CodingKeys: String, CodingKey {
        case sessionID
        case processGenerationID
        case sequenceNumber
        case observedDurationNanoseconds
        case followsUnobservedInterval
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.sessionID = try container.decode(UUID.self, forKey: .sessionID)
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
    public let processSegmentCount: Int

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

/// Crash-safe ride-session elapsed-time evidence assembled from process-local monotonic
/// segments. It never uses `Date` subtraction to fill process gaps.
///
/// A caller may checkpoint the current process generation repeatedly. Replaying the same
/// generation with a longer duration extends that segment by only the new delta; an older
/// checkpoint is ignored. A different process generation must use the next sequence number
/// and explicitly declare the recovery gap.
public struct RideSessionDurationEvidenceAccumulator: Codable, Equatable, Sendable {
    public let sessionID: UUID
    private var processSegments: [RideSessionDurationProcessSegment]
    private var totalObservedDurationNanoseconds: UInt64

    public init(sessionID: UUID) {
        self.sessionID = sessionID
        self.processSegments = []
        self.totalObservedDurationNanoseconds = 0
    }

    public var snapshot: RideSessionDurationEvidenceSnapshot {
        let duration: UInt64? = processSegments.isEmpty
            ? nil
            : totalObservedDurationNanoseconds
        let coverage: RideSessionDurationCoverage
        if processSegments.isEmpty {
            coverage = .unknown
        } else if processSegments.contains(where: \.followsUnobservedInterval) {
            coverage = .partial
        } else {
            coverage = .complete
        }

        return RideSessionDurationEvidenceSnapshot(
            sessionID: sessionID,
            observedDurationNanoseconds: duration,
            coverage: coverage,
            processSegmentCount: processSegments.count
        )
    }

    @discardableResult
    public mutating func upsert(
        _ segment: RideSessionDurationProcessSegment
    ) throws -> RideSessionDurationUpsertResult {
        guard segment.sessionID == sessionID else {
            throw RideSessionDurationEvidenceError.sessionMismatch
        }

        if let existingIndex = processSegments.firstIndex(
            where: { $0.sequenceNumber == segment.sequenceNumber }
        ) {
            let existing = processSegments[existingIndex]
            guard existing.processGenerationID == segment.processGenerationID,
                  existing.followsUnobservedInterval == segment.followsUnobservedInterval else {
                throw RideSessionDurationEvidenceError.conflictingProcessGeneration
            }

            if segment.observedDurationNanoseconds == existing.observedDurationNanoseconds {
                return .idempotentReplay
            }
            if segment.observedDurationNanoseconds < existing.observedDurationNanoseconds {
                return .staleReplayIgnored
            }

            let additional = segment.observedDurationNanoseconds - existing.observedDurationNanoseconds
            let (newTotal, overflow) = totalObservedDurationNanoseconds
                .addingReportingOverflow(additional)
            guard !overflow else {
                throw RideSessionDurationEvidenceError.durationOverflow
            }

            processSegments[existingIndex] = segment
            totalObservedDurationNanoseconds = newTotal
            return .extended(additionalNanoseconds: additional)
        }

        guard !processSegments.contains(
            where: { $0.processGenerationID == segment.processGenerationID }
        ) else {
            throw RideSessionDurationEvidenceError.processGenerationReused
        }

        let expectedSequence: UInt64
        if let lastSequence = processSegments.last?.sequenceNumber {
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
            guard !segment.followsUnobservedInterval else {
                throw RideSessionDurationEvidenceError.missingRecoveryGap
            }
        } else {
            guard segment.followsUnobservedInterval else {
                throw RideSessionDurationEvidenceError.missingRecoveryGap
            }
        }

        let (newTotal, overflow) = totalObservedDurationNanoseconds
            .addingReportingOverflow(segment.observedDurationNanoseconds)
        guard !overflow else {
            throw RideSessionDurationEvidenceError.durationOverflow
        }

        processSegments.append(segment)
        totalObservedDurationNanoseconds = newTotal
        return .inserted
    }

    private enum CodingKeys: String, CodingKey {
        case sessionID
        case processSegments
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedSessionID = try container.decode(UUID.self, forKey: .sessionID)
        let decodedSegments = try container.decode(
            [RideSessionDurationProcessSegment].self,
            forKey: .processSegments
        )

        self.init(sessionID: decodedSessionID)
        do {
            for segment in decodedSegments {
                try upsert(segment)
            }
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
        try container.encode(processSegments, forKey: .processSegments)
    }
}
