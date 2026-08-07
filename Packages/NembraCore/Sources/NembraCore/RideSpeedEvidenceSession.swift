import Foundation

public struct RideSpeedEvidenceRecordResult: Equatable, Sendable {
    public let peak: PeakSpeedRecordResult
    public let benchmark: TelemetryBenchmarkRecordResult

    fileprivate init(peak: PeakSpeedRecordResult, benchmark: TelemetryBenchmarkRecordResult) {
        self.peak = peak
        self.benchmark = benchmark
    }
}

/// Constant-memory accounting of every peak-pipeline rejection observed by one
/// ride-owned speed-evidence session.
///
/// `RidePeakSpeedEvidence` can exist only after at least one peak sample is
/// accepted. Keeping this summary separately preserves why an all-rejected
/// session produced no peak at all without storing an unbounded event log.
public struct RideSpeedEvidencePeakRejectionSummary: Equatable, Sendable {
    public let nonAuthoritativeSampleCount: Int
    public let sourceMismatchSampleCount: Int
    public let nonIncreasingTimestampCount: Int
    public let nonFiniteDerivedSpeedCount: Int
    public let speedAccuracyUnavailableCount: Int
    public let speedAccuracyExceededCount: Int

    public var totalRejectedSampleCount: Int {
        nonAuthoritativeSampleCount
            + sourceMismatchSampleCount
            + nonIncreasingTimestampCount
            + nonFiniteDerivedSpeedCount
            + speedAccuracyUnavailableCount
            + speedAccuracyExceededCount
    }

    /// Matches the selected-source quality-rejection categories counted by
    /// `PeakSpeedEvidence.qualityRejectedSampleCount` after a peak exists.
    /// Foreign/non-authoritative traffic remains separate provenance.
    public var selectedSourceQualityRejectedSampleCount: Int {
        nonIncreasingTimestampCount
            + nonFiniteDerivedSpeedCount
            + speedAccuracyUnavailableCount
            + speedAccuracyExceededCount
    }

    fileprivate init(
        nonAuthoritativeSampleCount: Int,
        sourceMismatchSampleCount: Int,
        nonIncreasingTimestampCount: Int,
        nonFiniteDerivedSpeedCount: Int,
        speedAccuracyUnavailableCount: Int,
        speedAccuracyExceededCount: Int
    ) {
        self.nonAuthoritativeSampleCount = nonAuthoritativeSampleCount
        self.sourceMismatchSampleCount = sourceMismatchSampleCount
        self.nonIncreasingTimestampCount = nonIncreasingTimestampCount
        self.nonFiniteDerivedSpeedCount = nonFiniteDerivedSpeedCount
        self.speedAccuracyUnavailableCount = speedAccuracyUnavailableCount
        self.speedAccuracyExceededCount = speedAccuracyExceededCount
    }
}

/// A gap in the selected speed-evidence source, not an arbitrary ride/vehicle event.
///
/// This intentionally omits `vehicleConnectionLost`: a scooter disconnect is a
/// selected-source gap only when scooter BLE is the selected speed source. A
/// caller must translate the physical event to `.selectedSourceUnavailable` only
/// after making that source-specific determination.
public enum RideSpeedEvidenceSessionInterruption: Equatable, Sendable {
    case selectedSourceUnavailable
    case applicationLifecycleInterrupted
}

public struct RideSpeedEvidenceSessionSnapshot: Equatable, Sendable {
    public let sessionID: UUID
    public let source: SpeedTelemetrySource
    public let beganAfterKnownObservationGap: Bool
    /// Callbacks from any source other than this session's selected source are
    /// source-switch/mixing evidence and independently block peak reporting.
    public let foreignSourceCallbackCount: Int
    public let peakRejections: RideSpeedEvidencePeakRejectionSummary
    public let peakEvidence: RidePeakSpeedEvidence?
    public let telemetryBenchmark: TelemetryBenchmarkSummary

    fileprivate init(
        sessionID: UUID,
        source: SpeedTelemetrySource,
        beganAfterKnownObservationGap: Bool,
        foreignSourceCallbackCount: Int,
        peakRejections: RideSpeedEvidencePeakRejectionSummary,
        peakEvidence: RidePeakSpeedEvidence?,
        telemetryBenchmark: TelemetryBenchmarkSummary
    ) {
        self.sessionID = sessionID
        self.source = source
        self.beganAfterKnownObservationGap = beganAfterKnownObservationGap
        self.foreignSourceCallbackCount = foreignSourceCallbackCount
        self.peakRejections = peakRejections
        self.peakEvidence = peakEvidence
        self.telemetryBenchmark = telemetryBenchmark
    }
}

/// Owns peak and raw telemetry-quality evidence for one immutable ride/source.
///
/// Live construction and operation are package-sealed until the ride lifecycle
/// has a mechanically bound owner for this observer. A public initializer taking
/// only a caller-selected ride UUID would reopen the same evidence-reset hole that
/// `RidePeakSpeedEvidenceAccumulator` deliberately closes: unrelated code could
/// create another clean observer for the same UUID and discard earlier loss.
public struct RideSpeedEvidenceSessionAccumulator: Sendable {
    public let sessionID: UUID
    public let source: SpeedTelemetrySource
    public let beganAfterKnownObservationGap: Bool

    private var peakAccumulator: RidePeakSpeedEvidenceAccumulator
    private var benchmarkCollector: TelemetryBenchmarkCollector
    private var peakRejectionAccumulator = RideSpeedEvidencePeakRejectionAccumulator()
    private var foreignSourceCallbackCount = 0
    /// One logical source outage can produce repeated lifecycle callbacks. Keep
    /// the outage pending until accepted selected-source benchmark evidence
    /// resumes so duplicate notifications cannot inflate durable peak-loss counts.
    private var selectedSourceInterruptionPending: Bool

    package init(
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
        self.selectedSourceInterruptionPending = beginsAfterKnownObservationGap
    }

    @discardableResult
    package mutating func record(_ sample: SpeedTelemetrySample) -> RideSpeedEvidenceRecordResult {
        // Benchmark first so raw source-arrival evidence is independent of a
        // peak-specific GPS accuracy gate. Both receive the exact callback.
        let benchmarkResult = benchmarkCollector.record(sample)
        let peakResult = peakAccumulator.record(sample)

        if case let .rejected(rejection) = peakResult {
            peakRejectionAccumulator.record(rejection)
        }

        switch benchmarkResult {
        case .accepted:
            // The selected raw source has produced accepted benchmark evidence
            // again, so a future interruption represents a new logical gap even
            // if this exact sample failed a stricter peak-specific accuracy gate.
            selectedSourceInterruptionPending = false

        case .rejected(.sourceMismatch):
            foreignSourceCallbackCount += 1

        case .rejected:
            // Rejected selected-source evidence does not prove the source stream
            // has resumed cleanly; preserve any pending logical interruption.
            break
        }

        return RideSpeedEvidenceRecordResult(peak: peakResult, benchmark: benchmarkResult)
    }

    /// Records a gap only after the trusted lifecycle owner has determined the
    /// selected speed source itself was unavailable. This prevents an unrelated
    /// vehicle event (for example BLE disconnect while GPS remains healthy) from
    /// destroying otherwise valid GPS evidence.
    ///
    /// Repeated notifications while the same outage is still pending are a no-op.
    /// The next accepted selected-source benchmark sample re-arms interruption
    /// recording for a later distinct outage.
    package mutating func recordInterruption(
        _ interruption: RideSpeedEvidenceSessionInterruption
    ) {
        guard !selectedSourceInterruptionPending else { return }
        selectedSourceInterruptionPending = true

        let peakInterruption: PeakSpeedInterruption
        switch interruption {
        case .selectedSourceUnavailable:
            peakInterruption = .sourceUnavailable
        case .applicationLifecycleInterrupted:
            peakInterruption = .applicationLifecycleInterrupted
        }

        peakAccumulator.recordInterruption(peakInterruption)
        benchmarkCollector.markKnownObservationInterruption()
    }

    package var snapshot: RideSpeedEvidenceSessionSnapshot {
        RideSpeedEvidenceSessionSnapshot(
            sessionID: sessionID,
            source: source,
            beganAfterKnownObservationGap: beganAfterKnownObservationGap,
            foreignSourceCallbackCount: foreignSourceCallbackCount,
            peakRejections: peakRejectionAccumulator.summary,
            peakEvidence: peakAccumulator.evidence,
            telemetryBenchmark: benchmarkCollector.summary
        )
    }
}

public enum RideObservedPeakQualityPolicyError: Error, Equatable, Sendable {
    case sourceRequirementRequired
    case nonAuthoritativeSource
    case minimumAcceptedSampleCountInsufficientForJitter(required: Int, actual: Int)
    case rejectedFractionRequirementRequired
    case meanIntervalRequirementRequired
    case maximumIntervalRequirementRequired
    case jitterRequirementRequired
    case speedResolutionRequirementRequired
    case gpsLatencyCoverageRequirementRequired
    case gpsLatencyRequirementRequired
}

/// Feature-level requirements for deciding whether a same-ride observed peak is
/// strong enough to report. This type chooses no ES80-specific numeric thresholds;
/// it only requires callers to provide the evidence dimensions peak reporting
/// cannot silently ignore.
public struct RideObservedPeakQualityPolicy: Equatable, Sendable {
    public let telemetry: SpeedTelemetryQualityPolicy

    public init(telemetry: SpeedTelemetryQualityPolicy) throws {
        guard let requiredSource = telemetry.requiredSource else {
            throw RideObservedPeakQualityPolicyError.sourceRequirementRequired
        }
        guard requiredSource != .motionAssist else {
            throw RideObservedPeakQualityPolicyError.nonAuthoritativeSource
        }

        // Report missing feature dimensions before evaluating the statistical
        // shape of those dimensions. A caller that never requested jitter should
        // get `jitterRequirementRequired`, not a sample-floor error for jitter.
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

        // Jitter is variation between intervals. Two accepted samples provide
        // only one interval, whose population standard deviation is trivially
        // zero and therefore is not meaningful jitter evidence. Requiring at
        // least three accepted samples is a statistical shape invariant (two
        // intervals), not a guessed ES80 cadence or quality threshold.
        let minimumSamplesForJitterEvidence = 3
        guard telemetry.minimumAcceptedSampleCount >= minimumSamplesForJitterEvidence else {
            throw RideObservedPeakQualityPolicyError
                .minimumAcceptedSampleCountInsufficientForJitter(
                    required: minimumSamplesForJitterEvidence,
                    actual: telemetry.minimumAcceptedSampleCount
                )
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
    case insufficientJitterIntervalEvidence(required: Int, actual: Int)
    case gpsPeakAccuracyPolicyUnavailable
    case telemetryQualityFailed([SpeedTelemetryQualityFailure])
}

/// Immutable audit result for one same-ride observed-peak quality decision.
///
/// `isReady` means the retained benchmark satisfied the retained caller-supplied
/// policy and the peak-specific truth checks below. Keeping the session topology,
/// peak-rejection summary, policy, and raw benchmark prevents a later consumer
/// from seeing only an untraceable boolean/assessment after failed-session
/// provenance or thresholds have been lost. This type is intentionally not
/// Codable and does not claim those thresholds have been physically validated
/// for AOVOPRO ES80.
public struct RideObservedPeakReadiness: Equatable, Sendable {
    public let sessionID: UUID
    public let source: SpeedTelemetrySource
    public let beganAfterKnownObservationGap: Bool
    public let foreignSourceCallbackCount: Int
    public let peakRejections: RideSpeedEvidencePeakRejectionSummary
    public let peakEvidence: RidePeakSpeedEvidence?
    public let telemetryBenchmark: TelemetryBenchmarkSummary
    public let policy: RideObservedPeakQualityPolicy
    public let telemetryQuality: SpeedTelemetryQualityAssessment
    public let failures: [RideObservedPeakReadinessFailure]

    public var isReady: Bool { failures.isEmpty }

    fileprivate init(
        sessionID: UUID,
        source: SpeedTelemetrySource,
        beganAfterKnownObservationGap: Bool,
        foreignSourceCallbackCount: Int,
        peakRejections: RideSpeedEvidencePeakRejectionSummary,
        peakEvidence: RidePeakSpeedEvidence?,
        telemetryBenchmark: TelemetryBenchmarkSummary,
        policy: RideObservedPeakQualityPolicy,
        telemetryQuality: SpeedTelemetryQualityAssessment,
        failures: [RideObservedPeakReadinessFailure]
    ) {
        self.sessionID = sessionID
        self.source = source
        self.beganAfterKnownObservationGap = beganAfterKnownObservationGap
        self.foreignSourceCallbackCount = foreignSourceCallbackCount
        self.peakRejections = peakRejections
        self.peakEvidence = peakEvidence
        self.telemetryBenchmark = telemetryBenchmark
        self.policy = policy
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

        // The wrapper requires a jitter ceiling, so the ride must actually
        // contain at least two observed intra-segment timing intervals. Three
        // accepted samples alone are not enough if a known gap splits them 2+1.
        let minimumIntervalsForJitterEvidence = 2
        if telemetryBenchmark.intervalCount < minimumIntervalsForJitterEvidence {
            failures.append(.insufficientJitterIntervalEvidence(
                required: minimumIntervalsForJitterEvidence,
                actual: telemetryBenchmark.intervalCount
            ))
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
            beganAfterKnownObservationGap: beganAfterKnownObservationGap,
            foreignSourceCallbackCount: foreignSourceCallbackCount,
            peakRejections: peakRejections,
            peakEvidence: peakEvidence,
            telemetryBenchmark: telemetryBenchmark,
            policy: policy,
            telemetryQuality: telemetryQuality,
            failures: failures
        )
    }
}

private struct RideSpeedEvidencePeakRejectionAccumulator: Sendable {
    private var nonAuthoritativeSampleCount = 0
    private var sourceMismatchSampleCount = 0
    private var nonIncreasingTimestampCount = 0
    private var nonFiniteDerivedSpeedCount = 0
    private var speedAccuracyUnavailableCount = 0
    private var speedAccuracyExceededCount = 0

    mutating func record(_ rejection: PeakSpeedRecordRejection) {
        switch rejection {
        case .nonAuthoritativeSample:
            nonAuthoritativeSampleCount += 1
        case .sourceMismatch:
            sourceMismatchSampleCount += 1
        case .nonIncreasingTimestamp:
            nonIncreasingTimestampCount += 1
        case .nonFiniteDerivedSpeed:
            nonFiniteDerivedSpeedCount += 1
        case .speedAccuracyUnavailable:
            speedAccuracyUnavailableCount += 1
        case .speedAccuracyExceeded:
            speedAccuracyExceededCount += 1
        }
    }

    var summary: RideSpeedEvidencePeakRejectionSummary {
        RideSpeedEvidencePeakRejectionSummary(
            nonAuthoritativeSampleCount: nonAuthoritativeSampleCount,
            sourceMismatchSampleCount: sourceMismatchSampleCount,
            nonIncreasingTimestampCount: nonIncreasingTimestampCount,
            nonFiniteDerivedSpeedCount: nonFiniteDerivedSpeedCount,
            speedAccuracyUnavailableCount: speedAccuracyUnavailableCount,
            speedAccuracyExceededCount: speedAccuracyExceededCount
        )
    }
}
