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
    /// The attempt benchmark saw the selected-source callback before the timing
    /// evaluator consumed that exact sample. Final reporting quality comes from
    /// the separately maintained retained timing-trace benchmark.
    case processed(benchmark: TelemetryBenchmarkRecordResult, runState: AccelerationRunState)
}

public struct AccelerationEvidenceSessionSnapshot: Equatable, Sendable {
    public let policy: AccelerationEvidenceSessionPolicy
    public let runState: AccelerationRunState

    /// Diagnostic quality summary for every selected-source callback observed by
    /// this attempt before it became terminal. It can include superseded
    /// stationary anchors or timing-quality-rejected packets and is therefore not
    /// the reporting authority for a completed result.
    public let attemptStreamBenchmark: TelemetryBenchmarkSummary

    /// Quality summary containing only the final stationary anchor plus timing
    /// samples the evaluator accepted after launch. It is available only when a
    /// run completes and is the reporting authority for telemetry quality.
    public let timingTraceBenchmark: TelemetryBenchmarkSummary?

    public let ignoredForeignSourceCallbackCount: Int
    public let knownObservationInterruptionCount: Int
    public let continuityWasBroken: Bool

    fileprivate init(
        policy: AccelerationEvidenceSessionPolicy,
        runState: AccelerationRunState,
        attemptStreamBenchmark: TelemetryBenchmarkSummary,
        timingTraceBenchmark: TelemetryBenchmarkSummary?,
        ignoredForeignSourceCallbackCount: Int,
        knownObservationInterruptionCount: Int,
        continuityWasBroken: Bool
    ) {
        self.policy = policy
        self.runState = runState
        self.attemptStreamBenchmark = attemptStreamBenchmark
        self.timingTraceBenchmark = timingTraceBenchmark
        self.ignoredForeignSourceCallbackCount = ignoredForeignSourceCallbackCount
        self.knownObservationInterruptionCount = knownObservationInterruptionCount
        self.continuityWasBroken = continuityWasBroken
    }
}

/// Owns the measurement clock and quality evidence for exactly one in-memory
/// acceleration observation attempt.
///
/// The exact selected-source callback is sent to `TelemetryBenchmarkCollector`
/// and `AccelerationRunEvaluator` in the same call. A second constant-memory
/// collector tracks only the evaluator's current retained timing trace: it resets
/// when a newer accepted stationary anchor supersedes the old anchor, skips
/// timing-quality-rejected packets, and freezes when the evaluator becomes
/// terminal. Post-run traffic therefore cannot make an earlier result look better.
public struct AccelerationEvidenceSession: Sendable {
    public let policy: AccelerationEvidenceSessionPolicy

    private var evaluator: AccelerationRunEvaluator
    private var attemptBenchmark: TelemetryBenchmarkCollector
    private var timingTraceBenchmarkCollector: TelemetryBenchmarkCollector?
    private var hasSelectedSourceObservation = false
    private var ignoredForeignSourceCallbackCount = 0
    private var knownObservationInterruptionCount = 0
    private var continuityWasBroken = false

    public init(policy: AccelerationEvidenceSessionPolicy) {
        self.policy = policy
        self.evaluator = AccelerationRunEvaluator(policy: policy.run)
        self.attemptBenchmark = TelemetryBenchmarkCollector(source: policy.source)
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

        hasSelectedSourceObservation = true
        let benchmarkResult = attemptBenchmark.record(sample)
        let stateBefore = evaluator.state
        evaluator.accept(sample)
        updateTimingTrace(
            sample: sample,
            stateBefore: stateBefore,
            stateAfter: evaluator.state
        )
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
           hasSelectedSourceObservation {
            knownObservationInterruptionCount += 1
            continuityWasBroken = true
        }

        evaluator.interrupt(interruption)
    }

    public var snapshot: AccelerationEvidenceSessionSnapshot {
        let traceBenchmark: TelemetryBenchmarkSummary?
        if case .completed = evaluator.state {
            traceBenchmark = timingTraceBenchmarkCollector?.summary
        } else {
            traceBenchmark = nil
        }

        return AccelerationEvidenceSessionSnapshot(
            policy: policy,
            runState: evaluator.state,
            attemptStreamBenchmark: attemptBenchmark.summary,
            timingTraceBenchmark: traceBenchmark,
            ignoredForeignSourceCallbackCount: ignoredForeignSourceCallbackCount,
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

    private mutating func updateTimingTrace(
        sample: SpeedTelemetrySample,
        stateBefore: AccelerationRunState,
        stateAfter: AccelerationRunState
    ) {
        switch (stateBefore, stateAfter) {
        case (.waitingForStandstill, .armed):
            resetTimingTrace(to: sample)

        case (.armed, .armed):
            // With an explicit required source, a same-state stationary callback
            // is a new anchor only when it passed the evaluator's accuracy gate.
            // A moving or poor-accuracy callback leaves the prior anchor intact.
            if sample.metersPerSecond <= policy.run.stationaryMaximumMetersPerSecond,
               timingAccuracyIsAcceptable(sample) {
                resetTimingTrace(to: sample)
            }

        case (.armed, .running), (.armed, .completed),
             (.running, .running), (.running, .completed):
            // Any other evaluator rejection from these states is terminal
            // (chronology, gap, source change, return to stationary). If the state
            // advanced/remained nonterminal and accuracy passes, this sample is
            // part of the retained timing trace.
            if timingAccuracyIsAcceptable(sample) {
                timingTraceBenchmarkCollector?.record(sample)
            }

        case (.waitingForStandstill, .waitingForStandstill),
             (.waitingForStandstill, .running),
             (.waitingForStandstill, .completed),
             (.waitingForStandstill, .invalidated),
             (.armed, .waitingForStandstill),
             (.armed, .invalidated),
             (.running, .waitingForStandstill),
             (.running, .armed),
             (.running, .invalidated),
             (.completed, _),
             (.invalidated, _):
            break
        }
    }

    private mutating func resetTimingTrace(to stationaryAnchor: SpeedTelemetrySample) {
        var collector = TelemetryBenchmarkCollector(source: policy.source)
        collector.record(stationaryAnchor)
        timingTraceBenchmarkCollector = collector
    }

    private func timingAccuracyIsAcceptable(_ sample: SpeedTelemetrySample) -> Bool {
        guard let maximum = policy.run.maximumSpeedAccuracyMetersPerSecond else {
            return true
        }
        guard let accuracy = sample.speedAccuracyMetersPerSecond else {
            return false
        }
        return accuracy <= maximum
    }
}

public enum AccelerationEvidenceReadinessFailure: Equatable, Sendable {
    case runIncomplete
    case runInvalidated(AccelerationRunInvalidationReason)
    case resultSourceMismatch(expected: SpeedTelemetrySource, actual: SpeedTelemetrySource)
    case timingTraceBenchmarkUnavailable
    case insufficientTimingEvidenceSamples(required: Int, actual: Int)
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
        let qualityBenchmark = timingTraceBenchmark ?? attemptStreamBenchmark
        let telemetryQuality = qualityBenchmark.qualityAssessment(using: policy.telemetry)
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
            if timingTraceBenchmark == nil {
                failures.append(.timingTraceBenchmarkUnavailable)
            }
            if completed.timingEvidenceSampleCount < policy.telemetry.minimumAcceptedSampleCount {
                failures.append(.insufficientTimingEvidenceSamples(
                    required: policy.telemetry.minimumAcceptedSampleCount,
                    actual: completed.timingEvidenceSampleCount
                ))
            }
        case let .invalidated(reason):
            failures.append(.runInvalidated(reason))
        case .waitingForStandstill, .armed, .running:
            failures.append(.runIncomplete)
        }

        if let timingTraceBenchmark,
           timingTraceBenchmark.rejectedSampleCount > 0 {
            failures.append(.selectedSourceBenchmarkRejectedSamples(
                count: timingTraceBenchmark.rejectedSampleCount
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
