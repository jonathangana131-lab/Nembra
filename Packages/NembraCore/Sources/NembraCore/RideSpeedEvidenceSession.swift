import Foundation

/// Result of feeding one raw speed callback through the two evidence pipelines
/// that must stay mechanically attached to the same ride session.
public struct RideSpeedEvidenceRecordResult: Equatable, Sendable {
    public let peak: PeakSpeedRecordResult
    public let benchmark: TelemetryBenchmarkRecordResult

    fileprivate init(
        peak: PeakSpeedRecordResult,
        benchmark: TelemetryBenchmarkRecordResult
    ) {
        self.peak = peak
        self.benchmark = benchmark
    }
}

/// Immutable same-ride snapshot of peak and raw-source quality evidence.
///
/// There is deliberately no public initializer. The snapshot can only be emitted
/// by `RideSpeedEvidenceSessionAccumulator`, which feeds both collectors from the
/// same callback/interruption stream and fixes both to one selected source.
public struct RideSpeedEvidenceSessionSnapshot: Equatable, Sendable {
    public let sessionID: UUID
    public let source: SpeedTelemetrySource
    public let beganAfterKnownObservationGap: Bool
    public let peakEvidence: RidePeakSpeedEvidence?
    public let telemetryBenchmark: TelemetryBenchmarkSummary

    fileprivate init(
        sessionID: UUID,
        source: SpeedTelemetrySource,
        beganAfterKnownObservationGap: Bool,
        peakEvidence: RidePeakSpeedEvidence?,
        telemetryBenchmark: TelemetryBenchmarkSummary
    ) {
        self.sessionID = sessionID
        self.source = source
        self.beganAfterKnownObservationGap = beganAfterKnownObservationGap
        self.peakEvidence = peakEvidence
        self.telemetryBenchmark = telemetryBenchmark
    }
}

/// Owns peak-speed and raw telemetry-quality accumulation for one immutable ride
/// session and one authoritative source.
///
/// A caller cannot separately supply a peak from one ride and a benchmark from
/// another. Every callback reaches both collectors in one method and every known
/// observation interruption reaches both evidence pipelines in one method.
public struct RideSpeedEvidenceSessionAccumulator: Sendable {
    public let sessionID: UUID
    public let source: SpeedTelemetrySource
    public let beganAfterKnownObservationGap: Bool

    private var peakAccumulator: RidePeakSpeedEvidenceAccumulator
    private var benchmarkCollector: TelemetryBenchmarkCollector

    public init(
        sessionID: UUID,
        peakPolicy: PeakSpeedPolicy,
        beginsAfterKnownObservationGap: Bool = false
    ) {
        self.sessionID = sessionID
        self.source = peakPolicy.source
        self.beganAfterKnownObservationGap = beginsAfterKnownObservationGap
        self.peakAccumulator = RidePeakSpeedEvidenceAccumulator(
            sessionID: sessionID,
            policy: peakPolicy,
            beginsAfterKnownObservationGap: beginsAfterKnownObservationGap
        )
        self.benchmarkCollector = TelemetryBenchmarkCollector(source: peakPolicy.source)
    }

    @discardableResult
    public mutating func record(_ sample: SpeedTelemetrySample) -> RideSpeedEvidenceRecordResult {
        // Benchmark first so its source-arrival evidence is independent of a
        // peak-specific GPS accuracy gate. Both still receive the exact callback.
        let benchmarkResult = benchmarkCollector.record(sample)
        let peakResult = peakAccumulator.record(sample)
        return RideSpeedEvidenceRecordResult(
            peak: peakResult,
            benchmark: benchmarkResult
        )
    }

    /// Records one known selected-source observation break in both pipelines.
    ///
    /// The benchmark dependency deliberately starts a new segment only after it
    /// has accepted evidence; an initial pre-observation recovery gap is instead
    /// preserved by `beganAfterKnownObservationGap` and by the peak accumulator.
    public mutating func recordInterruption(_ interruption: PeakSpeedInterruption) {
        peakAccumulator.recordInterruption(interruption)
        benchmarkCollector.markKnownObservationInterruption()
    }

    public var snapshot: RideSpeedEvidenceSessionSnapshot {
        RideSpeedEvidenceSessionSnapshot(
            sessionID: sessionID,
            source: source,
            beganAfterKnownObservationGap: beganAfterKnownObservationGap,
            peakEvidence: peakAccumulator.evidence,
            telemetryBenchmark: benchmarkCollector.summary
        )
    }
}

public enum RideObservedPeakQualityPolicyError: Error, Equatable, Sendable {
    case sourceRequirementRequired
    case nonAuthoritativeSource
    case rejectedFractionRequirementRequired
    case meanIntervalRequirementRequired
    case maximumIntervalRequirementRequired
    case jitterRequirementRequired
    case speedResolutionRequirementRequired
    case gpsLatencyCoverageRequirementRequired
    case gpsLatencyRequirementRequired
}

/// Feature-level requirements for deciding whether a same-ride observed peak is
/// strong enough to be reportable.
///
/// This type chooses **no numeric thresholds**. It only requires the caller to
/// supply explicit thresholds for the evidence dimensions a peak-speed feature
/// must not silently ignore: rejection rate, cadence, worst observed interval,
/// jitter and empirical speed resolution. GPS additionally requires explicit
/// delivery-latency coverage and latency limits because Core Location supplies a
/// measurement timestamp that can support that check.
public struct RideObservedPeakQualityPolicy: Equatable, Sendable {
    public let telemetry: SpeedTelemetryQualityPolicy

    public init(telemetry: SpeedTelemetryQualityPolicy) throws {
        guard let requiredSource = telemetry.requiredSource else {
            throw RideObservedPeakQualityPolicyError.sourceRequirementRequired
        }
        guard requiredSource != .motionAssist else {
            throw RideObservedPeakQualityPolicyError.nonAuthoritativeSource
        }
        guard telemetry.maximumRejectedSampleFraction != nil else {
            throw RideObservedPeakQualityPolicyError.rejectedFractionRequirementRequired
        }
        guard telemetry.maximumMeanIntervalMilliseconds != nil else {
            throw RideObservedPeakQualityPolicyError.meanIntervalRequirementRequired
        }
        guard telemetry.maximumObservedIntervalMilliseconds != nil else {
            throw RideObservedPeakQualityPolicyError.maximumIntervalRequirementRequired
        }
        guard telemetry.maximumJitterStandardDeviationMilliseconds != nil else {
            throw RideObservedPeakQualityPolicyError.jitterRequirementRequired
        }
        guard telemetry.maximumEmpiricalSpeedStepKilometersPerHour != nil else {
            throw RideObservedPeakQualityPolicyError.speedResolutionRequirementRequired
        }

        if requiredSource == .gps {
            guard let coverage = telemetry.minimumDeliveryLatencySampleFraction,
                  coverage > 0 else {
                throw RideObservedPeakQualityPolicyError.gpsLatencyCoverageRequirementRequired
            }
            guard telemetry.maximumMeanDeliveryLatencyMilliseconds != nil else {
                throw RideObservedPeakQualityPolicyError.gpsLatencyRequirementRequired
            }
        }

        self.telemetry = telemetry
    }
}

public enum RideObservedPeakReadinessFailure: Equatable, Sendable {
    case peakUnavailable
    case selectedSourceMismatch(
        peak: SpeedTelemetrySource,
        benchmark: SpeedTelemetrySource
    )
    case partialPeakObservation
    case gpsPeakAccuracyPolicyUnavailable
    case telemetryQualityFailed([SpeedTelemetryQualityFailure])
}

/// Same-ride decision evidence for whether Nembra may report an observed peak.
///
/// `isReady` means the supplied software evidence satisfies the supplied feature
/// policy. It does **not** mean the policy thresholds themselves have been
/// physically validated for the AOVOPRO ES80.
public struct RideObservedPeakReadiness: Equatable, Sendable {
    public let sessionID: UUID
    public let source: SpeedTelemetrySource
    public let peakEvidence: RidePeakSpeedEvidence?
    public let telemetryQuality: SpeedTelemetryQualityAssessment
    public let failures: [RideObservedPeakReadinessFailure]

    public var isReady: Bool {
        failures.isEmpty
    }

    fileprivate init(
        sessionID: UUID,
        source: SpeedTelemetrySource,
        peakEvidence: RidePeakSpeedEvidence?,
        telemetryQuality: SpeedTelemetryQualityAssessment,
        failures: [RideObservedPeakReadinessFailure]
    ) {
        self.sessionID = sessionID
        self.source = source
        self.peakEvidence = peakEvidence
        self.telemetryQuality = telemetryQuality
        self.failures = failures
    }
}

public extension RideSpeedEvidenceSessionSnapshot {
    /// Evaluates a reportable observed peak using evidence collected from this
    /// exact ride/source session.
    ///
    /// The benchmark quality check cannot repair partial peak observation. A
    /// source may have excellent cadence while the ride still contains a known
    /// transport/app gap or a peak-specific quality rejection; that remains a
    /// separate failure.
    func observedPeakReadiness(
        using policy: RideObservedPeakQualityPolicy
    ) -> RideObservedPeakReadiness {
        let telemetryQuality = telemetryBenchmark.qualityAssessment(using: policy.telemetry)
        var failures: [RideObservedPeakReadinessFailure] = []

        if let peakEvidence {
            if peakEvidence.policy.source != telemetryBenchmark.source {
                failures.append(.selectedSourceMismatch(
                    peak: peakEvidence.policy.source,
                    benchmark: telemetryBenchmark.source
                ))
            }

            if peakEvidence.peakEvidence.continuity != .noRecordedSelectedSourceEvidenceLoss {
                failures.append(.partialPeakObservation)
            }

            if peakEvidence.policy.source == .gps,
               peakEvidence.policy.maximumSpeedAccuracyMetersPerSecond == nil {
                failures.append(.gpsPeakAccuracyPolicyUnavailable)
            }
        } else {
            failures.append(.peakUnavailable)
        }

        if !telemetryQuality.isQualified {
            failures.append(.telemetryQualityFailed(telemetryQuality.failures))
        }

        return RideObservedPeakReadiness(
            sessionID: sessionID,
            source: source,
            peakEvidence: peakEvidence,
            telemetryQuality: telemetryQuality,
            failures: failures
        )
    }
}
