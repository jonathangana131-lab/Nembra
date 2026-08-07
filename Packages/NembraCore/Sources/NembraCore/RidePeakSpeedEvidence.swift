import Foundation

/// Session-bound peak-speed evidence produced only by a ride-owned accumulator.
///
/// `PeakSpeedEvidence` itself is intentionally reusable and session-local. This
/// wrapper adds the immutable ride identity needed before any later persistence
/// or statistics layer can join the observed maximum to a completed ride.
public struct RidePeakSpeedEvidence: Equatable, Sendable {
    public let sessionID: UUID
    public let policy: PeakSpeedPolicy
    public let peakEvidence: PeakSpeedEvidence

    fileprivate init(
        sessionID: UUID,
        policy: PeakSpeedPolicy,
        peakEvidence: PeakSpeedEvidence
    ) {
        self.sessionID = sessionID
        self.policy = policy
        self.peakEvidence = peakEvidence
    }
}

/// Owns one `PeakSpeedEvidenceAccumulator` for exactly one ride session.
///
/// There is deliberately no reset API. A new ride must create a new accumulator
/// with a new session identity rather than erasing evidence-loss history and
/// reusing an old binding.
public struct RidePeakSpeedEvidenceAccumulator: Sendable {
    public let sessionID: UUID
    private var peakAccumulator: PeakSpeedEvidenceAccumulator

    /// - Parameter beginsAfterKnownObservationGap: Set only when this ride-bound
    ///   observer starts after a known interval in which selected-source peak
    ///   evidence was unavailable (for example after conservative checkpoint
    ///   recovery). The gap is recorded immediately; it is never reconstructed.
    public init(
        sessionID: UUID,
        policy: PeakSpeedPolicy,
        beginsAfterKnownObservationGap: Bool = false
    ) {
        self.sessionID = sessionID

        var accumulator = PeakSpeedEvidenceAccumulator(policy: policy)
        if beginsAfterKnownObservationGap {
            accumulator.recordInterruption(.applicationLifecycleInterrupted)
        }
        self.peakAccumulator = accumulator
    }

    public var policy: PeakSpeedPolicy {
        peakAccumulator.policy
    }

    @discardableResult
    public mutating func record(_ sample: SpeedTelemetrySample) -> PeakSpeedRecordResult {
        peakAccumulator.record(sample)
    }

    public mutating func recordInterruption(_ interruption: PeakSpeedInterruption) {
        peakAccumulator.recordInterruption(interruption)
    }

    /// Nil means no authoritative selected-source peak has been accepted yet.
    /// Known gaps/rejections remain retained internally and will be reflected in
    /// continuity if a later valid measurement establishes a peak.
    public var evidence: RidePeakSpeedEvidence? {
        guard let peakEvidence = peakAccumulator.evidence else { return nil }
        return RidePeakSpeedEvidence(
            sessionID: sessionID,
            policy: peakAccumulator.policy,
            peakEvidence: peakEvidence
        )
    }
}

public enum CompletedRidePeakSpeedEvidenceError: Error, Equatable, Sendable {
    case sessionMismatch
    case continuityMismatch
    case invalidEvidence
}

/// Durable observed-peak evidence bound to one immutable completed ride.
///
/// This projection intentionally strips process-local receive uptime. Uptime is
/// ordering evidence inside the live process and is not meaningful after process
/// recovery/relaunch. Durable history keeps only the measured peak, source and
/// accuracy policy/provenance, evidence-loss counts, and ride identity/continuity.
///
/// This is still **observed peak** evidence, not proof of exact physical top
/// speed. A future user-facing peak-speed statistic must additionally require an
/// appropriate telemetry-quality assessment for the selected source.
public struct CompletedRidePeakSpeedEvidence: Codable, Equatable, Sendable {
    public let sessionID: UUID
    public let rideContinuity: RideSessionContinuity
    public let source: SpeedTelemetrySource
    public let metersPerSecond: Double
    public let speedAccuracyMetersPerSecond: Double?
    public let maximumAllowedSpeedAccuracyMetersPerSecond: Double?
    public let acceptedSampleCount: Int
    public let qualityRejectedSampleCount: Int
    public let knownInterruptionCount: Int
    public let observationContinuity: PeakSpeedObservationContinuity

    public init(
        completedRide: CompletedRideEvidence,
        ridePeak: RidePeakSpeedEvidence
    ) throws {
        guard completedRide.sessionID == ridePeak.sessionID else {
            throw CompletedRidePeakSpeedEvidenceError.sessionMismatch
        }

        // Checkpoint recovery proves at least one interval of the ride existed
        // outside this process-local peak observer. A recovered ride may retain a
        // numeric observed peak, but it cannot claim no recorded evidence loss.
        if completedRide.continuity == .recoveredCheckpoint,
           ridePeak.peakEvidence.continuity != .partialSelectedSourceEvidence {
            throw CompletedRidePeakSpeedEvidenceError.continuityMismatch
        }

        try self.init(
            sessionID: completedRide.sessionID,
            rideContinuity: completedRide.continuity,
            source: ridePeak.policy.source,
            metersPerSecond: ridePeak.peakEvidence.peak.metersPerSecond,
            speedAccuracyMetersPerSecond: ridePeak.peakEvidence.peak.speedAccuracyMetersPerSecond,
            maximumAllowedSpeedAccuracyMetersPerSecond:
                ridePeak.policy.maximumSpeedAccuracyMetersPerSecond,
            acceptedSampleCount: ridePeak.peakEvidence.acceptedSampleCount,
            qualityRejectedSampleCount: ridePeak.peakEvidence.qualityRejectedSampleCount,
            knownInterruptionCount: ridePeak.peakEvidence.knownInterruptionCount,
            observationContinuity: ridePeak.peakEvidence.continuity
        )
    }

    /// Verifies that this durable projection still belongs to the completed ride
    /// a caller is about to join it with. This never consults wall-clock deltas.
    public func validate(against completedRide: CompletedRideEvidence) throws {
        guard completedRide.sessionID == sessionID else {
            throw CompletedRidePeakSpeedEvidenceError.sessionMismatch
        }
        guard completedRide.continuity == rideContinuity else {
            throw CompletedRidePeakSpeedEvidenceError.continuityMismatch
        }
    }

    public var kilometersPerHour: Double {
        metersPerSecond * 3.6
    }

    private init(
        sessionID: UUID,
        rideContinuity: RideSessionContinuity,
        source: SpeedTelemetrySource,
        metersPerSecond: Double,
        speedAccuracyMetersPerSecond: Double?,
        maximumAllowedSpeedAccuracyMetersPerSecond: Double?,
        acceptedSampleCount: Int,
        qualityRejectedSampleCount: Int,
        knownInterruptionCount: Int,
        observationContinuity: PeakSpeedObservationContinuity
    ) throws {
        guard source != .motionAssist,
              metersPerSecond.isFinite,
              metersPerSecond >= 0 else {
            throw CompletedRidePeakSpeedEvidenceError.invalidEvidence
        }

        let kilometersPerHour = metersPerSecond * 3.6
        guard kilometersPerHour.isFinite, kilometersPerHour >= 0 else {
            throw CompletedRidePeakSpeedEvidenceError.invalidEvidence
        }

        if let speedAccuracyMetersPerSecond {
            guard speedAccuracyMetersPerSecond.isFinite,
                  speedAccuracyMetersPerSecond >= 0 else {
                throw CompletedRidePeakSpeedEvidenceError.invalidEvidence
            }
        }

        if let maximumAllowedSpeedAccuracyMetersPerSecond {
            guard maximumAllowedSpeedAccuracyMetersPerSecond.isFinite,
                  maximumAllowedSpeedAccuracyMetersPerSecond >= 0,
                  let speedAccuracyMetersPerSecond,
                  speedAccuracyMetersPerSecond <= maximumAllowedSpeedAccuracyMetersPerSecond else {
                throw CompletedRidePeakSpeedEvidenceError.invalidEvidence
            }
        }

        guard acceptedSampleCount > 0,
              qualityRejectedSampleCount >= 0,
              knownInterruptionCount >= 0 else {
            throw CompletedRidePeakSpeedEvidenceError.invalidEvidence
        }

        switch observationContinuity {
        case .noRecordedSelectedSourceEvidenceLoss:
            guard qualityRejectedSampleCount == 0,
                  knownInterruptionCount == 0 else {
                throw CompletedRidePeakSpeedEvidenceError.invalidEvidence
            }
        case .partialSelectedSourceEvidence:
            guard qualityRejectedSampleCount > 0 || knownInterruptionCount > 0 else {
                throw CompletedRidePeakSpeedEvidenceError.invalidEvidence
            }
        }

        if rideContinuity == .recoveredCheckpoint,
           observationContinuity != .partialSelectedSourceEvidence {
            throw CompletedRidePeakSpeedEvidenceError.invalidEvidence
        }

        self.sessionID = sessionID
        self.rideContinuity = rideContinuity
        self.source = source
        self.metersPerSecond = metersPerSecond
        self.speedAccuracyMetersPerSecond = speedAccuracyMetersPerSecond
        self.maximumAllowedSpeedAccuracyMetersPerSecond =
            maximumAllowedSpeedAccuracyMetersPerSecond
        self.acceptedSampleCount = acceptedSampleCount
        self.qualityRejectedSampleCount = qualityRejectedSampleCount
        self.knownInterruptionCount = knownInterruptionCount
        self.observationContinuity = observationContinuity
    }

    private enum CodingKeys: String, CodingKey {
        case sessionID
        case rideContinuity
        case source
        case metersPerSecond
        case speedAccuracyMetersPerSecond
        case maximumAllowedSpeedAccuracyMetersPerSecond
        case acceptedSampleCount
        case qualityRejectedSampleCount
        case knownInterruptionCount
        case observationContinuity
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                sessionID: container.decode(UUID.self, forKey: .sessionID),
                rideContinuity: container.decode(RideSessionContinuity.self, forKey: .rideContinuity),
                source: container.decode(SpeedTelemetrySource.self, forKey: .source),
                metersPerSecond: container.decode(Double.self, forKey: .metersPerSecond),
                speedAccuracyMetersPerSecond: container.decodeIfPresent(
                    Double.self,
                    forKey: .speedAccuracyMetersPerSecond
                ),
                maximumAllowedSpeedAccuracyMetersPerSecond: container.decodeIfPresent(
                    Double.self,
                    forKey: .maximumAllowedSpeedAccuracyMetersPerSecond
                ),
                acceptedSampleCount: container.decode(Int.self, forKey: .acceptedSampleCount),
                qualityRejectedSampleCount: container.decode(
                    Int.self,
                    forKey: .qualityRejectedSampleCount
                ),
                knownInterruptionCount: container.decode(Int.self, forKey: .knownInterruptionCount),
                observationContinuity: container.decode(
                    PeakSpeedObservationContinuity.self,
                    forKey: .observationContinuity
                )
            )
        } catch let error as CompletedRidePeakSpeedEvidenceError {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Completed ride peak-speed evidence is structurally invalid: \(error)."
                )
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sessionID, forKey: .sessionID)
        try container.encode(rideContinuity, forKey: .rideContinuity)
        try container.encode(source, forKey: .source)
        try container.encode(metersPerSecond, forKey: .metersPerSecond)
        try container.encodeIfPresent(
            speedAccuracyMetersPerSecond,
            forKey: .speedAccuracyMetersPerSecond
        )
        try container.encodeIfPresent(
            maximumAllowedSpeedAccuracyMetersPerSecond,
            forKey: .maximumAllowedSpeedAccuracyMetersPerSecond
        )
        try container.encode(acceptedSampleCount, forKey: .acceptedSampleCount)
        try container.encode(qualityRejectedSampleCount, forKey: .qualityRejectedSampleCount)
        try container.encode(knownInterruptionCount, forKey: .knownInterruptionCount)
        try container.encode(observationContinuity, forKey: .observationContinuity)
    }
}
