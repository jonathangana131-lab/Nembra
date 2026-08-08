import Foundation

/// Qualification result is deliberately module-owned. Publicly decodable durable
/// evidence is descriptive input, not an authorization token for max wording.
struct RideObservedPeakHistoryAssessment: Equatable, Sendable {
    let telemetryQuality: SpeedTelemetryQualityAssessment
    let failures: [RideObservedPeakReadinessFailure]
    let isObservedMaximumEligible: Bool

    var isReadinessReady: Bool { failures.isEmpty }
}

/// Relaunch-safe evidence required to re-evaluate one completed ride's observed
/// peak quality. There is deliberately no persisted `qualified`, `isReady`, or
/// final-statistics bit: qualification is recomputed from these raw durable inputs.
///
/// This value is public/Codable so a future app persistence adapter can retain the
/// descriptive evidence. Decoding it does not grant authority to promote a peak:
/// the eligibility-bearing assessment is module-owned until persistence and
/// provenance are mechanically sealed inside NembraCore.
public struct RideObservedPeakHistoryEvidence: Codable, Equatable, Sendable {
    public let sessionID: UUID
    public let rideContinuity: RideSessionContinuity
    public let source: SpeedTelemetrySource
    public let beganAfterKnownObservationGap: Bool
    public let knownSelectedSourceInterruptionCount: Int
    public let foreignSourceCallbackCount: Int
    public let peakRejections: RideObservedPeakHistoryRejections
    public let completedPeak: CompletedRidePeakSpeedEvidence?
    public let telemetryBenchmark: RideObservedPeakHistoryBenchmark
    public let policy: RideObservedPeakHistoryPolicy

    package init(
        completedRide: CompletedRideEvidence,
        completedPeak: CompletedRidePeakSpeedEvidence?,
        readiness: RideObservedPeakReadiness
    ) throws {
        guard readiness.sessionID == completedRide.sessionID else {
            throw RideObservedPeakHistoryEvidenceError.sessionMismatch
        }
        guard readiness.source != .motionAssist,
              readiness.source == readiness.telemetryBenchmark.source,
              readiness.policy.telemetry.requiredSource == readiness.source else {
            throw RideObservedPeakHistoryEvidenceError.sourceMismatch
        }

        if let completedPeak {
            do {
                try completedPeak.validate(against: completedRide)
            } catch let error as CompletedRidePeakSpeedEvidenceError {
                switch error {
                case .sessionMismatch:
                    throw RideObservedPeakHistoryEvidenceError.sessionMismatch
                case .continuityMismatch:
                    throw RideObservedPeakHistoryEvidenceError.continuityMismatch
                case .invalidEvidence:
                    throw RideObservedPeakHistoryEvidenceError.evidenceMismatch
                }
            }
        }

        try Self.validatePeakMatch(completedPeak: completedPeak, readiness: readiness)

        try self.init(
            sessionID: completedRide.sessionID,
            rideContinuity: completedRide.continuity,
            source: readiness.source,
            beganAfterKnownObservationGap: readiness.beganAfterKnownObservationGap,
            knownSelectedSourceInterruptionCount: readiness.knownSelectedSourceInterruptionCount,
            foreignSourceCallbackCount: readiness.foreignSourceCallbackCount,
            peakRejections: RideObservedPeakHistoryRejections(readiness.peakRejections),
            completedPeak: completedPeak,
            telemetryBenchmark: RideObservedPeakHistoryBenchmark(readiness.telemetryBenchmark),
            policy: RideObservedPeakHistoryPolicy(readiness.policy)
        )

        // Construction from a live readiness audit must prove this durable form
        // independently reconstructs the same quality result before it can persist.
        let recomputed = try assessment()
        guard recomputed.telemetryQuality == readiness.telemetryQuality,
              recomputed.failures == readiness.failures else {
            throw RideObservedPeakHistoryEvidenceError.evidenceMismatch
        }
    }

    private init(
        sessionID: UUID,
        rideContinuity: RideSessionContinuity,
        source: SpeedTelemetrySource,
        beganAfterKnownObservationGap: Bool,
        knownSelectedSourceInterruptionCount: Int,
        foreignSourceCallbackCount: Int,
        peakRejections: RideObservedPeakHistoryRejections,
        completedPeak: CompletedRidePeakSpeedEvidence?,
        telemetryBenchmark: RideObservedPeakHistoryBenchmark,
        policy: RideObservedPeakHistoryPolicy
    ) throws {
        guard source != .motionAssist,
              knownSelectedSourceInterruptionCount >= 0,
              foreignSourceCallbackCount >= 0 else {
            throw RideObservedPeakHistoryEvidenceError.invalidCount
        }
        guard telemetryBenchmark.source == source,
              policy.requiredSource == source else {
            throw RideObservedPeakHistoryEvidenceError.sourceMismatch
        }
        if beganAfterKnownObservationGap && knownSelectedSourceInterruptionCount == 0 {
            throw RideObservedPeakHistoryEvidenceError.evidenceMismatch
        }

        try RideObservedPeakHistoryIntegrity.validate(
            beganAfterKnownObservationGap: beganAfterKnownObservationGap,
            knownSelectedSourceInterruptionCount: knownSelectedSourceInterruptionCount,
            foreignSourceCallbackCount: foreignSourceCallbackCount,
            peakRejections: peakRejections,
            completedPeak: completedPeak,
            telemetryBenchmark: telemetryBenchmark
        )

        if let completedPeak {
            guard completedPeak.sessionID == sessionID,
                  completedPeak.rideContinuity == rideContinuity,
                  completedPeak.source == source,
                  completedPeak.beganAfterKnownObservationGap == beganAfterKnownObservationGap,
                  completedPeak.knownInterruptionCount == knownSelectedSourceInterruptionCount,
                  completedPeak.qualityRejectedSampleCount
                    == peakRejections.selectedSourceQualityRejectedSampleCount else {
                throw RideObservedPeakHistoryEvidenceError.evidenceMismatch
            }
        }

        self.sessionID = sessionID
        self.rideContinuity = rideContinuity
        self.source = source
        self.beganAfterKnownObservationGap = beganAfterKnownObservationGap
        self.knownSelectedSourceInterruptionCount = knownSelectedSourceInterruptionCount
        self.foreignSourceCallbackCount = foreignSourceCallbackCount
        self.peakRejections = peakRejections
        self.completedPeak = completedPeak
        self.telemetryBenchmark = telemetryBenchmark
        self.policy = policy
    }

    package func validate(against completedRide: CompletedRideEvidence) throws {
        guard completedRide.sessionID == sessionID else {
            throw RideObservedPeakHistoryEvidenceError.sessionMismatch
        }
        guard completedRide.continuity == rideContinuity else {
            throw RideObservedPeakHistoryEvidenceError.continuityMismatch
        }
        if let completedPeak {
            do {
                try completedPeak.validate(against: completedRide)
            } catch let error as CompletedRidePeakSpeedEvidenceError {
                switch error {
                case .sessionMismatch:
                    throw RideObservedPeakHistoryEvidenceError.sessionMismatch
                case .continuityMismatch:
                    throw RideObservedPeakHistoryEvidenceError.continuityMismatch
                case .invalidEvidence:
                    throw RideObservedPeakHistoryEvidenceError.evidenceMismatch
                }
            }
        }
    }

    /// Recomputes the exact readiness dimensions from durable evidence and then
    /// applies the stronger statistics gate that forbids any selected-source gap.
    /// Module-only by design: public Codable snapshots are not provenance authority.
    func assessment() throws -> RideObservedPeakHistoryAssessment {
        let runtimePolicy = try policy.runtimePolicy()
        let benchmark = telemetryBenchmark.runtimeSummary
        let telemetryQuality = benchmark.qualityAssessment(using: runtimePolicy.telemetry)
        var failures: [RideObservedPeakReadinessFailure] = []

        if let completedPeak {
            if completedPeak.source != benchmark.source {
                failures.append(.selectedSourceMismatch(
                    peak: completedPeak.source,
                    benchmark: benchmark.source
                ))
            }
            if completedPeak.observationContinuity != .noRecordedSelectedSourceEvidenceLoss {
                failures.append(.partialPeakObservation)
            }
            if completedPeak.source == .gps,
               completedPeak.maximumAllowedSpeedAccuracyMetersPerSecond == nil {
                failures.append(.gpsPeakAccuracyPolicyUnavailable)
            }
        } else {
            failures.append(.peakUnavailable)
        }

        let minimumIntervalsForJitterEvidence = 2
        if benchmark.intervalCount < minimumIntervalsForJitterEvidence {
            failures.append(.insufficientJitterIntervalEvidence(
                required: minimumIntervalsForJitterEvidence,
                actual: benchmark.intervalCount
            ))
        }

        if foreignSourceCallbackCount > 0 {
            failures.append(.foreignSourceTraffic(callbackCount: foreignSourceCallbackCount))
        }

        if !telemetryQuality.isQualified {
            failures.append(.telemetryQualityFailed(telemetryQuality.failures))
        }

        let eligible = failures.isEmpty
            && knownSelectedSourceInterruptionCount == 0
            && completedPeak?.observationContinuity == .noRecordedSelectedSourceEvidenceLoss
            && completedPeak?.source != .motionAssist

        return RideObservedPeakHistoryAssessment(
            telemetryQuality: telemetryQuality,
            failures: failures,
            isObservedMaximumEligible: eligible
        )
    }

    private static func validatePeakMatch(
        completedPeak: CompletedRidePeakSpeedEvidence?,
        readiness: RideObservedPeakReadiness
    ) throws {
        switch (completedPeak, readiness.peakEvidence) {
        case (nil, nil):
            return
        case let (.some(durablePeak), .some(livePeak)):
            guard durablePeak.sessionID == livePeak.sessionID,
                  durablePeak.beganAfterKnownObservationGap == livePeak.beganAfterKnownObservationGap,
                  durablePeak.source == livePeak.policy.source,
                  durablePeak.metersPerSecond == livePeak.peakEvidence.peak.metersPerSecond,
                  durablePeak.speedAccuracyMetersPerSecond == livePeak.peakEvidence.peak.speedAccuracyMetersPerSecond,
                  durablePeak.maximumAllowedSpeedAccuracyMetersPerSecond == livePeak.policy.maximumSpeedAccuracyMetersPerSecond,
                  durablePeak.acceptedSampleCount == livePeak.peakEvidence.acceptedSampleCount,
                  durablePeak.qualityRejectedSampleCount == livePeak.peakEvidence.qualityRejectedSampleCount,
                  durablePeak.knownInterruptionCount == livePeak.peakEvidence.knownInterruptionCount,
                  durablePeak.observationContinuity == livePeak.peakEvidence.continuity else {
                throw RideObservedPeakHistoryEvidenceError.evidenceMismatch
            }
        case (.some, nil), (nil, .some):
            throw RideObservedPeakHistoryEvidenceError.evidenceMismatch
        }
    }

    private enum CodingKeys: String, CodingKey {
        case sessionID, rideContinuity, source, beganAfterKnownObservationGap
        case knownSelectedSourceInterruptionCount, foreignSourceCallbackCount
        case peakRejections, completedPeak, telemetryBenchmark, policy
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                sessionID: c.decode(UUID.self, forKey: .sessionID),
                rideContinuity: c.decode(RideSessionContinuity.self, forKey: .rideContinuity),
                source: c.decode(SpeedTelemetrySource.self, forKey: .source),
                beganAfterKnownObservationGap: c.decode(Bool.self, forKey: .beganAfterKnownObservationGap),
                knownSelectedSourceInterruptionCount: c.decode(Int.self, forKey: .knownSelectedSourceInterruptionCount),
                foreignSourceCallbackCount: c.decode(Int.self, forKey: .foreignSourceCallbackCount),
                peakRejections: c.decode(RideObservedPeakHistoryRejections.self, forKey: .peakRejections),
                completedPeak: c.decodeIfPresent(CompletedRidePeakSpeedEvidence.self, forKey: .completedPeak),
                telemetryBenchmark: c.decode(RideObservedPeakHistoryBenchmark.self, forKey: .telemetryBenchmark),
                policy: c.decode(RideObservedPeakHistoryPolicy.self, forKey: .policy)
            )
        } catch {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Observed-peak history evidence is invalid: \(error)."
            ))
        }
    }
}
