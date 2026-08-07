import Foundation

public enum AccelerationEvidenceSessionPolicyError: Error, Equatable, Sendable {
    case runSourceRequired
    case telemetrySourceRequired
    case sourceMismatch(run: SpeedTelemetrySource, telemetry: SpeedTelemetrySource)
    case runMaximumSampleIntervalRequired
    case gpsSpeedAccuracyRequirementRequired
    case minimumAcceptedSampleCountInsufficientForJitter(required: Int, actual: Int)
    case rejectedFractionRequirementRequired
    case meanIntervalRequirementRequired
    case maximumIntervalRequirementRequired
    case jitterRequirementRequired
    case speedResolutionRequirementRequired
    case gpsLatencyCoverageRequirementRequired
    case gpsLatencyRequirementRequired
}

/// Couples one acceleration observation policy to one explicit measured speed
/// source and a complete caller-supplied telemetry-quality policy.
///
/// This type chooses no ES80 thresholds. It only prevents product reporting from
/// silently omitting evidence dimensions the acceleration feature depends on.
public struct AccelerationEvidenceSessionPolicy: Equatable, Sendable {
    public let run: AccelerationRunPolicy
    public let telemetry: SpeedTelemetryQualityPolicy
    public let source: SpeedTelemetrySource

    public init(
        run: AccelerationRunPolicy,
        telemetry: SpeedTelemetryQualityPolicy
    ) throws {
        guard let runSource = run.requiredSource else {
            throw AccelerationEvidenceSessionPolicyError.runSourceRequired
        }
        guard let telemetrySource = telemetry.requiredSource else {
            throw AccelerationEvidenceSessionPolicyError.telemetrySourceRequired
        }
        guard runSource == telemetrySource else {
            throw AccelerationEvidenceSessionPolicyError.sourceMismatch(
                run: runSource,
                telemetry: telemetrySource
            )
        }
        guard run.maximumSampleIntervalNanoseconds != nil else {
            throw AccelerationEvidenceSessionPolicyError.runMaximumSampleIntervalRequired
        }
        if runSource == .gps, run.maximumSpeedAccuracyMetersPerSecond == nil {
            throw AccelerationEvidenceSessionPolicyError.gpsSpeedAccuracyRequirementRequired
        }

        let minimumSamplesForJitterEvidence = 3
        guard telemetry.minimumAcceptedSampleCount >= minimumSamplesForJitterEvidence else {
            throw AccelerationEvidenceSessionPolicyError
                .minimumAcceptedSampleCountInsufficientForJitter(
                    required: minimumSamplesForJitterEvidence,
                    actual: telemetry.minimumAcceptedSampleCount
                )
        }
        guard telemetry.maximumRejectedSampleFraction != nil else {
            throw AccelerationEvidenceSessionPolicyError.rejectedFractionRequirementRequired
        }
        guard telemetry.maximumMeanIntervalMilliseconds != nil else {
            throw AccelerationEvidenceSessionPolicyError.meanIntervalRequirementRequired
        }
        guard telemetry.maximumObservedIntervalMilliseconds != nil else {
            throw AccelerationEvidenceSessionPolicyError.maximumIntervalRequirementRequired
        }
        guard telemetry.maximumJitterStandardDeviationMilliseconds != nil else {
            throw AccelerationEvidenceSessionPolicyError.jitterRequirementRequired
        }
        guard telemetry.maximumEmpiricalSpeedStepKilometersPerHour != nil else {
            throw AccelerationEvidenceSessionPolicyError.speedResolutionRequirementRequired
        }

        if runSource == .gps {
            guard let coverage = telemetry.minimumDeliveryLatencySampleFraction,
                  coverage > 0 else {
                throw AccelerationEvidenceSessionPolicyError.gpsLatencyCoverageRequirementRequired
            }
            guard telemetry.maximumMeanDeliveryLatencyMilliseconds != nil else {
                throw AccelerationEvidenceSessionPolicyError.gpsLatencyRequirementRequired
            }
        }

        self.run = run
        self.telemetry = telemetry
        self.source = runSource
    }
}

public enum AccelerationEvidenceSessionRecordResult: Equatable, Sendable {
    /// The session is bound to one explicit source. Other providers may coexist
    /// in the app, but their callbacks are not acceleration evidence for this run.
    case ignoredForeignSource(expected: SpeedTelemetrySource, actual: SpeedTelemetrySource)
    /// A completed, invalidated, or continuity-broken session is immutable.
    case ignoredAfterTerminalEvidence
    /// Both components saw the same selected-source callback before the session
    /// became terminal. The benchmark result remains explicit rather than hidden.
    case processed(benchmark: TelemetryBenchmarkRecordResult, runState: AccelerationRunState)
}

public struct AccelerationEvidenceSessionSnapshot: Equatable, Sendable {
    public let policy: AccelerationEvidenceSessionPolicy
    public let runState: AccelerationRunState
    public let telemetryBenchmark: TelemetryBenchmarkSummary
    public let ignoredForeignSourceCallbackCount: Int
    public let selectedSourceBenchmarkRejectionCount: Int
    public let knownObservationInterruptionCount: Int
    public let continuityWasBroken: Bool

    fileprivate init(
        policy: AccelerationEvidenceSessionPolicy,
        runState: AccelerationRunState,
        telemetryBenchmark: TelemetryBenchmarkSummary,
        ignoredForeignSourceCallbackCount: Int,
        selectedSourceBenchmarkRejectionCount: Int,
        knownObservationInterruptionCount: Int,
        continuityWasBroken: Bool
    ) {
        self.policy = policy
        self.runState = runState
        self.telemetryBenchmark = telemetryBenchmark
        self.ignoredForeignSourceCallbackCount = ignoredForeignSourceCallbackCount
        self.selectedSourceBenchmarkRejectionCount = selectedSourceBenchmarkRejectionCount
        self.knownObservationInterruptionCount = knownObservationInterruptionCount
        self.continuityWasBroken = continuityWasBroken
    }
}

/// Owns the measurement clock and quality evidence for exactly one in-memory
/// acceleration observation attempt.
///
/// The exact selected-source callback is sent to `TelemetryBenchmarkCollector`
/// and `AccelerationRunEvaluator` in the same call. Once the evaluator becomes
/// terminal, or a known observation gap breaks a partially observed attempt, the
/// session freezes so post-run traffic cannot make an earlier result look better.
public struct AccelerationEvidenceSession: Sendable {
    public let policy: AccelerationEvidenceSessionPolicy

    private var evaluator: AccelerationRunEvaluator
    private var benchmark: TelemetryBenchmarkCollector
    private var ignoredForeignSourceCallbackCount = 0
    private var selectedSourceBenchmarkRejectionCount = 0
    private var knownObservationInterruptionCount = 0
    private var continuityWasBroken = false

    public init(policy: AccelerationEvidenceSessionPolicy) {
        self.policy = policy
        self.evaluator = AccelerationRunEvaluator(policy: policy.run)
        self.benchmark = TelemetryBenchmarkCollector(source: policy.source)
    }

    public var state: AccelerationRunState {
        evaluator.state
    }

    @discardableResult
    public mutating func record(
        _ sample: SpeedTelemetrySample
    ) -> AccelerationEvidenceSessionRecordResult {
        guard !isTerminalEvidence else {
            return .ignoredAfterTerminalEvidence
        }
        guard sample.source == policy.source else {
            ignoredForeignSourceCallbackCount += 1
            return .ignoredForeignSource(expected: policy.source, actual: sample.source)
        }

        let benchmarkResult = benchmark.record(sample)
        if case .rejected = benchmarkResult {
            selectedSourceBenchmarkRejectionCount += 1
        }

        evaluator.accept(sample)
        return .processed(benchmark: benchmarkResult, runState: evaluator.state)
    }

    /// Records a known interruption in the run's evidence path.
    ///
    /// If selected-source evidence already exists, the session is permanently
    /// continuity-broken even when the underlying evaluator is still waiting for
    /// a valid standstill anchor. A new attempt must be created rather than
    /// stitching quality statistics across missing observation time.
    public mutating func interrupt(_ interruption: AccelerationRunInterruption) {
        guard !isTerminalEvidence else { return }

        if interruption != .operatorCancelled,
           benchmark.summary.acceptedSampleCount > 0 {
            knownObservationInterruptionCount += 1
            continuityWasBroken = true
        }

        evaluator.interrupt(interruption)
    }

    public var snapshot: AccelerationEvidenceSessionSnapshot {
        AccelerationEvidenceSessionSnapshot(
            policy: policy,
            runState: evaluator.state,
            telemetryBenchmark: benchmark.summary,
            ignoredForeignSourceCallbackCount: ignoredForeignSourceCallbackCount,
            selectedSourceBenchmarkRejectionCount: selectedSourceBenchmarkRejectionCount,
            knownObservationInterruptionCount: knownObservationInterruptionCount,
            continuityWasBroken: continuityWasBroken
        )
    }

    private var isTerminalEvidence: Bool {
        if continuityWasBroken { return true }
        switch evaluator.state {
        case .completed, .invalidated:
            return true
        case .waitingForStandstill, .armed, .running:
            return false
        }
    }
}

public enum AccelerationEvidenceReadinessFailure: Equatable, Sendable {
    case runIncomplete
    case runInvalidated(AccelerationRunInvalidationReason)
    case resultSourceMismatch(expected: SpeedTelemetrySource, actual: SpeedTelemetrySource)
    case selectedSourceBenchmarkRejectedSamples(count: Int)
    case knownObservationInterruption(count: Int)
    case telemetryQualityFailed([SpeedTelemetryQualityFailure])
}

/// Software evidence readiness for product reporting of one observed run.
///
/// `isReady` means this session satisfies the caller's supplied policy. It does
/// not validate those numeric thresholds for physical ES80 hardware, does not
/// convert receive-clock elapsed time into exact physical crossing time, and does
/// not make display interpolation into evidence.
public struct AccelerationEvidenceReadiness: Equatable, Sendable {
    public let result: AccelerationRunResult?
    public let telemetryQuality: SpeedTelemetryQualityAssessment
    public let failures: [AccelerationEvidenceReadinessFailure]

    public var isReady: Bool { failures.isEmpty }

    fileprivate init(
        result: AccelerationRunResult?,
        telemetryQuality: SpeedTelemetryQualityAssessment,
        failures: [AccelerationEvidenceReadinessFailure]
    ) {
        self.result = result
        self.telemetryQuality = telemetryQuality
        self.failures = failures
    }
}

public extension AccelerationEvidenceSessionSnapshot {
    func readiness() -> AccelerationEvidenceReadiness {
        let telemetryQuality = telemetryBenchmark.qualityAssessment(using: policy.telemetry)
        var failures: [AccelerationEvidenceReadinessFailure] = []
        var result: AccelerationRunResult?

        switch runState {
        case let .completed(completed):
            result = completed
            if completed.source != policy.source {
                failures.append(.resultSourceMismatch(
                    expected: policy.source,
                    actual: completed.source
                ))
            }
        case let .invalidated(reason):
            failures.append(.runInvalidated(reason))
        case .waitingForStandstill, .armed, .running:
            failures.append(.runIncomplete)
        }

        if selectedSourceBenchmarkRejectionCount > 0 {
            failures.append(.selectedSourceBenchmarkRejectedSamples(
                count: selectedSourceBenchmarkRejectionCount
            ))
        }
        if knownObservationInterruptionCount > 0 || continuityWasBroken {
            failures.append(.knownObservationInterruption(
                count: max(knownObservationInterruptionCount, 1)
            ))
        }
        if !telemetryQuality.isQualified {
            failures.append(.telemetryQualityFailed(telemetryQuality.failures))
        }

        return AccelerationEvidenceReadiness(
            result: result,
            telemetryQuality: telemetryQuality,
            failures: failures
        )
    }
}
