import Foundation

public struct RideSpeedEvidenceRecordResult: Equatable, Sendable {
    public let peak: PeakSpeedRecordResult
    public let benchmark: TelemetryBenchmarkRecordResult

    fileprivate init(peak: PeakSpeedRecordResult, benchmark: TelemetryBenchmarkRecordResult) {
        self.peak = peak
        self.benchmark = benchmark
    }
}

public struct RideSpeedEvidenceSessionSnapshot: Equatable, Sendable {
    public let sessionID: UUID
    public let source: SpeedTelemetrySource
    public let beganAfterKnownObservationGap: Bool
    /// Foreign authoritative callbacks are source-switch/mixing evidence. They
    /// block peak reporting independently of a generic rejection-fraction policy.
    public let foreignSourceCallbackCount: Int
    public let peakEvidence: RidePeakSpeedEvidence?
    public let telemetryBenchmark: TelemetryBenchmarkSummary

    fileprivate init(
        sessionID: UUID,
        source: SpeedTelemetrySource,
        beganAfterKnownObservationGap: Bool,
        foreignSourceCallbackCount: Int,
        peakEvidence: RidePeakSpeedEvidence?,
        telemetryBenchmark: TelemetryBenchmarkSummary
    ) {
        self.sessionID = sessionID
        self.source = source
        self.beganAfterKnownObservationGap = beganAfterKnownObservationGap
        self.foreignSourceCallbackCount = foreignSourceCallbackCount
        self.peakEvidence = peakEvidence
        self.telemetryBenchmark = telemetryBenchmark
    }
}

/// Owns peak and raw telemetry-quality evidence for one immutable ride/source.
public struct RideSpeedEvidenceSessionAccumulator: Sendable {
    public let sessionID: UUID
    public let source: SpeedTelemetrySource
    public let beganAfterKnownObservationGap: Bool

    private var peakAccumulator: RidePeakSpeedEvidenceAccumulator
    private var benchmarkCollector: TelemetryBenchmarkCollector
    private var foreignSourceCallbackCount = 0

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
        // Benchmark first so raw source-arrival evidence is independent of a
        // peak-specific GPS accuracy gate. Both receive the exact callback.
        let benchmarkResult = benchmarkCollector.record(sample)
        let peakResult = peakAccumulator.record(sample)

        if case .rejected(.sourceMismatch) = benchmarkResult {
            foreignSourceCallbackCount += 1
        }

        return RideSpeedEvidenceRecordResult(peak: peakResult, benchmark: benchmarkResult)
    }

    /// The benchmark starts a new segment only after accepted evidence; an
    /// initial pre-observation recovery gap is separately retained by the ride
    /// peak accumulator and `beganAfterKnownObservationGap`.
    public mutating func recordInterruption(_ interruption: PeakSpeedInterruption) {
        peakAccumulator.recordInterruption(interruption)
        benchmarkCollector.markKnownObservationInterruption()
    }

    public var snapshot: RideSpeedEvidenceSessionSnapshot {
        RideSpeedEvidenceSessionSnapshot(
            sessionID: sessionID,
            source: source,
            beganAfterKnownObservationGap: beganAfterKnownObservationGap,
            foreignSourceCallbackCount: foreignSourceCallbackCount,
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
/// strong enough to report. This type chooses no numeric thresholds; it only
/// requires callers to provide the evidence dimensions peak reporting cannot
/// silently ignore.
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
    case selectedSourceMismatch(peak: SpeedTelemetrySource, benchmark: SpeedTelemetrySource)
    case foreignSourceTraffic(callbackCount: Int)
    case partialPeakObservation
    case gpsPeakAccuracyPolicyUnavailable
    case telemetryQualityFailed([SpeedTelemetryQualityFailure])
}

/// `isReady` means software evidence satisfies the caller-supplied feature
/// policy. It does not mean those thresholds are physically validated for ES80.
public struct RideObservedPeakReadiness: Equatable, Sendable {
    public let sessionID: UUID
    public let source: SpeedTelemetrySource
    public let peakEvidence: RidePeakSpeedEvidence?
    public let telemetryQuality: SpeedTelemetryQualityAssessment
    public let failures: [RideObservedPeakReadinessFailure]

    public var isReady: Bool { failures.isEmpty }

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
    /// Benchmark quality cannot repair a partial peak observation. Foreign-source
    /// traffic also fails independently of the caller's generic rejection limit.
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

        if foreignSourceCallbackCount > 0 {
            failures.append(.foreignSourceTraffic(callbackCount: foreignSourceCallbackCount))
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
