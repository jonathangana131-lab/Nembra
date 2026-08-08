import Foundation

public enum RideObservedPeakHistoryEvidenceError: Error, Equatable, Sendable {
    case sessionMismatch
    case continuityMismatch
    case sourceMismatch
    case evidenceMismatch
    case invalidCount
    case invalidBenchmark
    case invalidPolicy
}

/// Codable mirror of the feature policy used to decide whether one ride's
/// observed peak is reportable. The policy is persisted as inputs, not as a
/// cached qualification verdict, so a relaunch can run the same validation again.
public struct RideObservedPeakHistoryPolicy: Codable, Equatable, Sendable {
    public let requiredSource: SpeedTelemetrySource
    public let minimumAcceptedSampleCount: Int
    public let maximumRejectedSampleFraction: Double
    public let maximumMeanIntervalMilliseconds: Double
    public let maximumObservedIntervalMilliseconds: Double
    public let maximumJitterStandardDeviationMilliseconds: Double
    public let minimumDeliveryLatencySampleFraction: Double?
    public let maximumMeanDeliveryLatencyMilliseconds: Double?
    public let maximumEmpiricalSpeedStepKilometersPerHour: Double

    package init(_ policy: RideObservedPeakQualityPolicy) throws {
        guard let requiredSource = policy.telemetry.requiredSource,
              let maximumRejectedSampleFraction = policy.telemetry.maximumRejectedSampleFraction,
              let maximumMeanIntervalMilliseconds = policy.telemetry.maximumMeanIntervalMilliseconds,
              let maximumObservedIntervalMilliseconds = policy.telemetry.maximumObservedIntervalMilliseconds,
              let maximumJitterStandardDeviationMilliseconds = policy.telemetry.maximumJitterStandardDeviationMilliseconds,
              let maximumEmpiricalSpeedStepKilometersPerHour = policy.telemetry.maximumEmpiricalSpeedStepKilometersPerHour else {
            throw RideObservedPeakHistoryEvidenceError.invalidPolicy
        }

        try self.init(
            requiredSource: requiredSource,
            minimumAcceptedSampleCount: policy.telemetry.minimumAcceptedSampleCount,
            maximumRejectedSampleFraction: maximumRejectedSampleFraction,
            maximumMeanIntervalMilliseconds: maximumMeanIntervalMilliseconds,
            maximumObservedIntervalMilliseconds: maximumObservedIntervalMilliseconds,
            maximumJitterStandardDeviationMilliseconds: maximumJitterStandardDeviationMilliseconds,
            minimumDeliveryLatencySampleFraction: policy.telemetry.minimumDeliveryLatencySampleFraction,
            maximumMeanDeliveryLatencyMilliseconds: policy.telemetry.maximumMeanDeliveryLatencyMilliseconds,
            maximumEmpiricalSpeedStepKilometersPerHour: maximumEmpiricalSpeedStepKilometersPerHour
        )
    }

    private init(
        requiredSource: SpeedTelemetrySource,
        minimumAcceptedSampleCount: Int,
        maximumRejectedSampleFraction: Double,
        maximumMeanIntervalMilliseconds: Double,
        maximumObservedIntervalMilliseconds: Double,
        maximumJitterStandardDeviationMilliseconds: Double,
        minimumDeliveryLatencySampleFraction: Double?,
        maximumMeanDeliveryLatencyMilliseconds: Double?,
        maximumEmpiricalSpeedStepKilometersPerHour: Double
    ) throws {
        do {
            let telemetry = try SpeedTelemetryQualityPolicy(
                requiredSource: requiredSource,
                minimumAcceptedSampleCount: minimumAcceptedSampleCount,
                maximumRejectedSampleFraction: maximumRejectedSampleFraction,
                maximumMeanIntervalMilliseconds: maximumMeanIntervalMilliseconds,
                maximumObservedIntervalMilliseconds: maximumObservedIntervalMilliseconds,
                maximumJitterStandardDeviationMilliseconds: maximumJitterStandardDeviationMilliseconds,
                minimumDeliveryLatencySampleFraction: minimumDeliveryLatencySampleFraction,
                maximumMeanDeliveryLatencyMilliseconds: maximumMeanDeliveryLatencyMilliseconds,
                maximumEmpiricalSpeedStepKilometersPerHour: maximumEmpiricalSpeedStepKilometersPerHour
            )
            _ = try RideObservedPeakQualityPolicy(telemetry: telemetry)
        } catch {
            throw RideObservedPeakHistoryEvidenceError.invalidPolicy
        }

        self.requiredSource = requiredSource
        self.minimumAcceptedSampleCount = minimumAcceptedSampleCount
        self.maximumRejectedSampleFraction = maximumRejectedSampleFraction
        self.maximumMeanIntervalMilliseconds = maximumMeanIntervalMilliseconds
        self.maximumObservedIntervalMilliseconds = maximumObservedIntervalMilliseconds
        self.maximumJitterStandardDeviationMilliseconds = maximumJitterStandardDeviationMilliseconds
        self.minimumDeliveryLatencySampleFraction = minimumDeliveryLatencySampleFraction
        self.maximumMeanDeliveryLatencyMilliseconds = maximumMeanDeliveryLatencyMilliseconds
        self.maximumEmpiricalSpeedStepKilometersPerHour = maximumEmpiricalSpeedStepKilometersPerHour
    }

    package func runtimePolicy() throws -> RideObservedPeakQualityPolicy {
        do {
            return try RideObservedPeakQualityPolicy(
                telemetry: SpeedTelemetryQualityPolicy(
                    requiredSource: requiredSource,
                    minimumAcceptedSampleCount: minimumAcceptedSampleCount,
                    maximumRejectedSampleFraction: maximumRejectedSampleFraction,
                    maximumMeanIntervalMilliseconds: maximumMeanIntervalMilliseconds,
                    maximumObservedIntervalMilliseconds: maximumObservedIntervalMilliseconds,
                    maximumJitterStandardDeviationMilliseconds: maximumJitterStandardDeviationMilliseconds,
                    minimumDeliveryLatencySampleFraction: minimumDeliveryLatencySampleFraction,
                    maximumMeanDeliveryLatencyMilliseconds: maximumMeanDeliveryLatencyMilliseconds,
                    maximumEmpiricalSpeedStepKilometersPerHour: maximumEmpiricalSpeedStepKilometersPerHour
                )
            )
        } catch {
            throw RideObservedPeakHistoryEvidenceError.invalidPolicy
        }
    }

    private enum CodingKeys: String, CodingKey {
        case requiredSource
        case minimumAcceptedSampleCount
        case maximumRejectedSampleFraction
        case maximumMeanIntervalMilliseconds
        case maximumObservedIntervalMilliseconds
        case maximumJitterStandardDeviationMilliseconds
        case minimumDeliveryLatencySampleFraction
        case maximumMeanDeliveryLatencyMilliseconds
        case maximumEmpiricalSpeedStepKilometersPerHour
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                requiredSource: container.decode(SpeedTelemetrySource.self, forKey: .requiredSource),
                minimumAcceptedSampleCount: container.decode(Int.self, forKey: .minimumAcceptedSampleCount),
                maximumRejectedSampleFraction: container.decode(Double.self, forKey: .maximumRejectedSampleFraction),
                maximumMeanIntervalMilliseconds: container.decode(Double.self, forKey: .maximumMeanIntervalMilliseconds),
                maximumObservedIntervalMilliseconds: container.decode(Double.self, forKey: .maximumObservedIntervalMilliseconds),
                maximumJitterStandardDeviationMilliseconds: container.decode(Double.self, forKey: .maximumJitterStandardDeviationMilliseconds),
                minimumDeliveryLatencySampleFraction: container.decodeIfPresent(Double.self, forKey: .minimumDeliveryLatencySampleFraction),
                maximumMeanDeliveryLatencyMilliseconds: container.decodeIfPresent(Double.self, forKey: .maximumMeanDeliveryLatencyMilliseconds),
                maximumEmpiricalSpeedStepKilometersPerHour: container.decode(Double.self, forKey: .maximumEmpiricalSpeedStepKilometersPerHour)
            )
        } catch {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Observed-peak history policy is structurally invalid: \(error)."
            ))
        }
    }
}

/// Durable raw benchmark facts needed to recompute telemetry qualification after
/// process death. No interpolated display sample or cached pass/fail bit is stored.
public struct RideObservedPeakHistoryBenchmark: Codable, Equatable, Sendable {
    public let source: SpeedTelemetrySource
    public let acceptedSampleCount: Int
    public let rejectedSampleCount: Int
    public let observationSegmentCount: Int
    public let knownObservationInterruptionCount: Int
    public let intervalCount: Int
    public let observedDurationSeconds: Double
    public let effectiveSampleRateHertz: Double?
    public let meanIntervalMilliseconds: Double?
    public let minimumIntervalMilliseconds: Double?
    public let maximumIntervalMilliseconds: Double?
    public let intervalJitterStandardDeviationMilliseconds: Double?
    public let duplicateSpeedValueCount: Int
    public let empiricalMinimumNonzeroSpeedStepKilometersPerHour: Double?
    public let deliveryLatencySampleCount: Int
    public let meanDeliveryLatencyMilliseconds: Double?
    public let minimumDeliveryLatencyMilliseconds: Double?
    public let maximumDeliveryLatencyMilliseconds: Double?
    public let deliveryLatencyStandardDeviationMilliseconds: Double?

    package init(_ summary: TelemetryBenchmarkSummary) throws {
        try self.init(
            source: summary.source,
            acceptedSampleCount: summary.acceptedSampleCount,
            rejectedSampleCount: summary.rejectedSampleCount,
            observationSegmentCount: summary.observationSegmentCount,
            knownObservationInterruptionCount: summary.knownObservationInterruptionCount,
            intervalCount: summary.intervalCount,
            observedDurationSeconds: summary.observedDurationSeconds,
            effectiveSampleRateHertz: summary.effectiveSampleRateHertz,
            meanIntervalMilliseconds: summary.meanIntervalMilliseconds,
            minimumIntervalMilliseconds: summary.minimumIntervalMilliseconds,
            maximumIntervalMilliseconds: summary.maximumIntervalMilliseconds,
            intervalJitterStandardDeviationMilliseconds: summary.intervalJitterStandardDeviationMilliseconds,
            duplicateSpeedValueCount: summary.duplicateSpeedValueCount,
            empiricalMinimumNonzeroSpeedStepKilometersPerHour: summary.empiricalMinimumNonzeroSpeedStepKilometersPerHour,
            deliveryLatencySampleCount: summary.deliveryLatencySampleCount,
            meanDeliveryLatencyMilliseconds: summary.meanDeliveryLatencyMilliseconds,
            minimumDeliveryLatencyMilliseconds: summary.minimumDeliveryLatencyMilliseconds,
            maximumDeliveryLatencyMilliseconds: summary.maximumDeliveryLatencyMilliseconds,
            deliveryLatencyStandardDeviationMilliseconds: summary.deliveryLatencyStandardDeviationMilliseconds
        )
    }

    private init(
        source: SpeedTelemetrySource,
        acceptedSampleCount: Int,
        rejectedSampleCount: Int,
        observationSegmentCount: Int,
        knownObservationInterruptionCount: Int,
        intervalCount: Int,
        observedDurationSeconds: Double,
        effectiveSampleRateHertz: Double?,
        meanIntervalMilliseconds: Double?,
        minimumIntervalMilliseconds: Double?,
        maximumIntervalMilliseconds: Double?,
        intervalJitterStandardDeviationMilliseconds: Double?,
        duplicateSpeedValueCount: Int,
        empiricalMinimumNonzeroSpeedStepKilometersPerHour: Double?,
        deliveryLatencySampleCount: Int,
        meanDeliveryLatencyMilliseconds: Double?,
        minimumDeliveryLatencyMilliseconds: Double?,
        maximumDeliveryLatencyMilliseconds: Double?,
        deliveryLatencyStandardDeviationMilliseconds: Double?
    ) throws {
        guard source != .motionAssist,
              acceptedSampleCount >= 0,
              rejectedSampleCount >= 0,
              observationSegmentCount >= 0,
              knownObservationInterruptionCount >= 0,
              intervalCount >= 0,
              duplicateSpeedValueCount >= 0,
              deliveryLatencySampleCount >= 0,
              deliveryLatencySampleCount <= acceptedSampleCount,
              observedDurationSeconds.isFinite,
              observedDurationSeconds >= 0 else {
            throw RideObservedPeakHistoryEvidenceError.invalidBenchmark
        }

        if acceptedSampleCount == 0 {
            guard observationSegmentCount == 0,
                  knownObservationInterruptionCount == 0,
                  intervalCount == 0 else {
                throw RideObservedPeakHistoryEvidenceError.invalidBenchmark
            }
        } else {
            guard observationSegmentCount > 0,
                  observationSegmentCount <= acceptedSampleCount,
                  knownObservationInterruptionCount <= observationSegmentCount,
                  intervalCount == acceptedSampleCount - observationSegmentCount else {
                throw RideObservedPeakHistoryEvidenceError.invalidBenchmark
            }
        }

        guard duplicateSpeedValueCount <= intervalCount else {
            throw RideObservedPeakHistoryEvidenceError.invalidBenchmark
        }

        if intervalCount == 0 {
            guard observedDurationSeconds == 0,
                  effectiveSampleRateHertz == nil,
                  meanIntervalMilliseconds == nil,
                  minimumIntervalMilliseconds == nil,
                  maximumIntervalMilliseconds == nil,
                  intervalJitterStandardDeviationMilliseconds == nil else {
                throw RideObservedPeakHistoryEvidenceError.invalidBenchmark
            }
        } else {
            guard observedDurationSeconds > 0,
                  let effectiveSampleRateHertz,
                  let meanIntervalMilliseconds,
                  let minimumIntervalMilliseconds,
                  let maximumIntervalMilliseconds,
                  let intervalJitterStandardDeviationMilliseconds,
                  effectiveSampleRateHertz.isFinite,
                  effectiveSampleRateHertz > 0,
                  meanIntervalMilliseconds.isFinite,
                  meanIntervalMilliseconds > 0,
                  minimumIntervalMilliseconds.isFinite,
                  minimumIntervalMilliseconds > 0,
                  maximumIntervalMilliseconds.isFinite,
                  maximumIntervalMilliseconds >= meanIntervalMilliseconds,
                  meanIntervalMilliseconds >= minimumIntervalMilliseconds,
                  intervalJitterStandardDeviationMilliseconds.isFinite,
                  intervalJitterStandardDeviationMilliseconds >= 0 else {
                throw RideObservedPeakHistoryEvidenceError.invalidBenchmark
            }
        }

        if let step = empiricalMinimumNonzeroSpeedStepKilometersPerHour {
            guard step.isFinite, step > 0 else {
                throw RideObservedPeakHistoryEvidenceError.invalidBenchmark
            }
        }

        let latencyValues = [
            meanDeliveryLatencyMilliseconds,
            minimumDeliveryLatencyMilliseconds,
            maximumDeliveryLatencyMilliseconds,
            deliveryLatencyStandardDeviationMilliseconds
        ]
        if deliveryLatencySampleCount == 0 {
            guard latencyValues.allSatisfy({ $0 == nil }) else {
                throw RideObservedPeakHistoryEvidenceError.invalidBenchmark
            }
        } else {
            guard let meanDeliveryLatencyMilliseconds,
                  let minimumDeliveryLatencyMilliseconds,
                  let maximumDeliveryLatencyMilliseconds,
                  let deliveryLatencyStandardDeviationMilliseconds,
                  meanDeliveryLatencyMilliseconds.isFinite,
                  minimumDeliveryLatencyMilliseconds.isFinite,
                  maximumDeliveryLatencyMilliseconds.isFinite,
                  deliveryLatencyStandardDeviationMilliseconds.isFinite,
                  minimumDeliveryLatencyMilliseconds >= 0,
                  meanDeliveryLatencyMilliseconds >= minimumDeliveryLatencyMilliseconds,
                  maximumDeliveryLatencyMilliseconds >= meanDeliveryLatencyMilliseconds,
                  deliveryLatencyStandardDeviationMilliseconds >= 0 else {
                throw RideObservedPeakHistoryEvidenceError.invalidBenchmark
            }
        }

        self.source = source
        self.acceptedSampleCount = acceptedSampleCount
        self.rejectedSampleCount = rejectedSampleCount
        self.observationSegmentCount = observationSegmentCount
        self.knownObservationInterruptionCount = knownObservationInterruptionCount
        self.intervalCount = intervalCount
        self.observedDurationSeconds = observedDurationSeconds
        self.effectiveSampleRateHertz = effectiveSampleRateHertz
        self.meanIntervalMilliseconds = meanIntervalMilliseconds
        self.minimumIntervalMilliseconds = minimumIntervalMilliseconds
        self.maximumIntervalMilliseconds = maximumIntervalMilliseconds
        self.intervalJitterStandardDeviationMilliseconds = intervalJitterStandardDeviationMilliseconds
        self.duplicateSpeedValueCount = duplicateSpeedValueCount
        self.empiricalMinimumNonzeroSpeedStepKilometersPerHour = empiricalMinimumNonzeroSpeedStepKilometersPerHour
        self.deliveryLatencySampleCount = deliveryLatencySampleCount
        self.meanDeliveryLatencyMilliseconds = meanDeliveryLatencyMilliseconds
        self.minimumDeliveryLatencyMilliseconds = minimumDeliveryLatencyMilliseconds
        self.maximumDeliveryLatencyMilliseconds = maximumDeliveryLatencyMilliseconds
        self.deliveryLatencyStandardDeviationMilliseconds = deliveryLatencyStandardDeviationMilliseconds
    }

    package var runtimeSummary: TelemetryBenchmarkSummary {
        TelemetryBenchmarkSummary(
            source: source,
            acceptedSampleCount: acceptedSampleCount,
            rejectedSampleCount: rejectedSampleCount,
            observationSegmentCount: observationSegmentCount,
            knownObservationInterruptionCount: knownObservationInterruptionCount,
            intervalCount: intervalCount,
            observedDurationSeconds: observedDurationSeconds,
            effectiveSampleRateHertz: effectiveSampleRateHertz,
            meanIntervalMilliseconds: meanIntervalMilliseconds,
            minimumIntervalMilliseconds: minimumIntervalMilliseconds,
            maximumIntervalMilliseconds: maximumIntervalMilliseconds,
            intervalJitterStandardDeviationMilliseconds: intervalJitterStandardDeviationMilliseconds,
            duplicateSpeedValueCount: duplicateSpeedValueCount,
            empiricalMinimumNonzeroSpeedStepKilometersPerHour: empiricalMinimumNonzeroSpeedStepKilometersPerHour,
            deliveryLatencySampleCount: deliveryLatencySampleCount,
            meanDeliveryLatencyMilliseconds: meanDeliveryLatencyMilliseconds,
            minimumDeliveryLatencyMilliseconds: minimumDeliveryLatencyMilliseconds,
            maximumDeliveryLatencyMilliseconds: maximumDeliveryLatencyMilliseconds,
            deliveryLatencyStandardDeviationMilliseconds: deliveryLatencyStandardDeviationMilliseconds
        )
    }

    private enum CodingKeys: String, CodingKey {
        case source, acceptedSampleCount, rejectedSampleCount, observationSegmentCount
        case knownObservationInterruptionCount, intervalCount, observedDurationSeconds
        case effectiveSampleRateHertz, meanIntervalMilliseconds, minimumIntervalMilliseconds
        case maximumIntervalMilliseconds, intervalJitterStandardDeviationMilliseconds
        case duplicateSpeedValueCount, empiricalMinimumNonzeroSpeedStepKilometersPerHour
        case deliveryLatencySampleCount, meanDeliveryLatencyMilliseconds
        case minimumDeliveryLatencyMilliseconds, maximumDeliveryLatencyMilliseconds
        case deliveryLatencyStandardDeviationMilliseconds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                source: container.decode(SpeedTelemetrySource.self, forKey: .source),
                acceptedSampleCount: container.decode(Int.self, forKey: .acceptedSampleCount),
                rejectedSampleCount: container.decode(Int.self, forKey: .rejectedSampleCount),
                observationSegmentCount: container.decode(Int.self, forKey: .observationSegmentCount),
                knownObservationInterruptionCount: container.decode(Int.self, forKey: .knownObservationInterruptionCount),
                intervalCount: container.decode(Int.self, forKey: .intervalCount),
                observedDurationSeconds: container.decode(Double.self, forKey: .observedDurationSeconds),
                effectiveSampleRateHertz: container.decodeIfPresent(Double.self, forKey: .effectiveSampleRateHertz),
                meanIntervalMilliseconds: container.decodeIfPresent(Double.self, forKey: .meanIntervalMilliseconds),
                minimumIntervalMilliseconds: container.decodeIfPresent(Double.self, forKey: .minimumIntervalMilliseconds),
                maximumIntervalMilliseconds: container.decodeIfPresent(Double.self, forKey: .maximumIntervalMilliseconds),
                intervalJitterStandardDeviationMilliseconds: container.decodeIfPresent(Double.self, forKey: .intervalJitterStandardDeviationMilliseconds),
                duplicateSpeedValueCount: container.decode(Int.self, forKey: .duplicateSpeedValueCount),
                empiricalMinimumNonzeroSpeedStepKilometersPerHour: container.decodeIfPresent(Double.self, forKey: .empiricalMinimumNonzeroSpeedStepKilometersPerHour),
                deliveryLatencySampleCount: container.decode(Int.self, forKey: .deliveryLatencySampleCount),
                meanDeliveryLatencyMilliseconds: container.decodeIfPresent(Double.self, forKey: .meanDeliveryLatencyMilliseconds),
                minimumDeliveryLatencyMilliseconds: container.decodeIfPresent(Double.self, forKey: .minimumDeliveryLatencyMilliseconds),
                maximumDeliveryLatencyMilliseconds: container.decodeIfPresent(Double.self, forKey: .maximumDeliveryLatencyMilliseconds),
                deliveryLatencyStandardDeviationMilliseconds: container.decodeIfPresent(Double.self, forKey: .deliveryLatencyStandardDeviationMilliseconds)
            )
        } catch {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Observed-peak benchmark history is structurally invalid: \(error)."
            ))
        }
    }
}

/// Constant-memory peak-pipeline rejection provenance retained across relaunch.
public struct RideObservedPeakHistoryRejections: Codable, Equatable, Sendable {
    public let nonAuthoritativeSampleCount: Int
    public let sourceMismatchSampleCount: Int
    public let nonIncreasingTimestampCount: Int
    public let nonFiniteDerivedSpeedCount: Int
    public let speedAccuracyUnavailableCount: Int
    public let speedAccuracyExceededCount: Int

    package init(_ summary: RideSpeedEvidencePeakRejectionSummary) throws {
        try self.init(
            nonAuthoritativeSampleCount: summary.nonAuthoritativeSampleCount,
            sourceMismatchSampleCount: summary.sourceMismatchSampleCount,
            nonIncreasingTimestampCount: summary.nonIncreasingTimestampCount,
            nonFiniteDerivedSpeedCount: summary.nonFiniteDerivedSpeedCount,
            speedAccuracyUnavailableCount: summary.speedAccuracyUnavailableCount,
            speedAccuracyExceededCount: summary.speedAccuracyExceededCount
        )
    }

    private init(
        nonAuthoritativeSampleCount: Int,
        sourceMismatchSampleCount: Int,
        nonIncreasingTimestampCount: Int,
        nonFiniteDerivedSpeedCount: Int,
        speedAccuracyUnavailableCount: Int,
        speedAccuracyExceededCount: Int
    ) throws {
        let values = [
            nonAuthoritativeSampleCount,
            sourceMismatchSampleCount,
            nonIncreasingTimestampCount,
            nonFiniteDerivedSpeedCount,
            speedAccuracyUnavailableCount,
            speedAccuracyExceededCount
        ]
        guard values.allSatisfy({ $0 >= 0 }) else {
            throw RideObservedPeakHistoryEvidenceError.invalidCount
        }
        var total = 0
        for value in values {
            let addition = total.addingReportingOverflow(value)
            guard !addition.overflow else {
                throw RideObservedPeakHistoryEvidenceError.invalidCount
            }
            total = addition.partialValue
        }

        self.nonAuthoritativeSampleCount = nonAuthoritativeSampleCount
        self.sourceMismatchSampleCount = sourceMismatchSampleCount
        self.nonIncreasingTimestampCount = nonIncreasingTimestampCount
        self.nonFiniteDerivedSpeedCount = nonFiniteDerivedSpeedCount
        self.speedAccuracyUnavailableCount = speedAccuracyUnavailableCount
        self.speedAccuracyExceededCount = speedAccuracyExceededCount
    }

    package var selectedSourceQualityRejectedSampleCount: Int {
        nonIncreasingTimestampCount
            + nonFiniteDerivedSpeedCount
            + speedAccuracyUnavailableCount
            + speedAccuracyExceededCount
    }

    private enum CodingKeys: String, CodingKey {
        case nonAuthoritativeSampleCount, sourceMismatchSampleCount, nonIncreasingTimestampCount
        case nonFiniteDerivedSpeedCount, speedAccuracyUnavailableCount, speedAccuracyExceededCount
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                nonAuthoritativeSampleCount: container.decode(Int.self, forKey: .nonAuthoritativeSampleCount),
                sourceMismatchSampleCount: container.decode(Int.self, forKey: .sourceMismatchSampleCount),
                nonIncreasingTimestampCount: container.decode(Int.self, forKey: .nonIncreasingTimestampCount),
                nonFiniteDerivedSpeedCount: container.decode(Int.self, forKey: .nonFiniteDerivedSpeedCount),
                speedAccuracyUnavailableCount: container.decode(Int.self, forKey: .speedAccuracyUnavailableCount),
                speedAccuracyExceededCount: container.decode(Int.self, forKey: .speedAccuracyExceededCount)
            )
        } catch {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Observed-peak rejection history is structurally invalid: \(error)."
            ))
        }
    }
}

public struct RideObservedPeakHistoryAssessment: Equatable, Sendable {
    public let telemetryQuality: SpeedTelemetryQualityAssessment
    public let failures: [RideObservedPeakReadinessFailure]
    public let isObservedMaximumEligible: Bool

    public var isReadinessReady: Bool { failures.isEmpty }
}

/// Relaunch-safe evidence required to re-evaluate one completed ride's observed
/// peak quality. This deliberately stores no `isReady`, `qualified`, or final
/// statistics eligibility bit. Those are recomputed from the durable evidence.
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
        let benchmark = try RideObservedPeakHistoryBenchmark(readiness.telemetryBenchmark)
        let policy = try RideObservedPeakHistoryPolicy(readiness.policy)
        let rejections = try RideObservedPeakHistoryRejections(readiness.peakRejections)

        try self.init(
            sessionID: completedRide.sessionID,
            rideContinuity: completedRide.continuity,
            source: readiness.source,
            beganAfterKnownObservationGap: readiness.beganAfterKnownObservationGap,
            knownSelectedSourceInterruptionCount: readiness.knownSelectedSourceInterruptionCount,
            foreignSourceCallbackCount: readiness.foreignSourceCallbackCount,
            peakRejections: rejections,
            completedPeak: completedPeak,
            telemetryBenchmark: benchmark,
            policy: policy
        )

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

        if let completedPeak {
            guard completedPeak.sessionID == sessionID,
                  completedPeak.rideContinuity == rideContinuity,
                  completedPeak.source == source,
                  completedPeak.beganAfterKnownObservationGap == beganAfterKnownObservationGap,
                  completedPeak.knownInterruptionCount == knownSelectedSourceInterruptionCount,
                  completedPeak.qualityRejectedSampleCount == peakRejections.selectedSourceQualityRejectedSampleCount else {
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

    public func assessment() throws -> RideObservedPeakHistoryAssessment {
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
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                sessionID: container.decode(UUID.self, forKey: .sessionID),
                rideContinuity: container.decode(RideSessionContinuity.self, forKey: .rideContinuity),
                source: container.decode(SpeedTelemetrySource.self, forKey: .source),
                beganAfterKnownObservationGap: container.decode(Bool.self, forKey: .beganAfterKnownObservationGap),
                knownSelectedSourceInterruptionCount: container.decode(Int.self, forKey: .knownSelectedSourceInterruptionCount),
                foreignSourceCallbackCount: container.decode(Int.self, forKey: .foreignSourceCallbackCount),
                peakRejections: container.decode(RideObservedPeakHistoryRejections.self, forKey: .peakRejections),
                completedPeak: container.decodeIfPresent(CompletedRidePeakSpeedEvidence.self, forKey: .completedPeak),
                telemetryBenchmark: container.decode(RideObservedPeakHistoryBenchmark.self, forKey: .telemetryBenchmark),
                policy: container.decode(RideObservedPeakHistoryPolicy.self, forKey: .policy)
            )
        } catch {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Observed-peak history evidence is structurally invalid: \(error)."
            ))
        }
    }
}

public enum RideHistoryObservedPeakCommitResult: Equatable, Sendable {
    case inserted
    case alreadyPresent
}

public enum RideHistoryObservedPeakStoreError: Error, Equatable, Sendable {
    case sessionConflict(UUID)
}

public struct RideHistoryObservedPeakRecord: Codable, Equatable, Sendable {
    public let evidence: RideObservedPeakHistoryEvidence

    public init(evidence: RideObservedPeakHistoryEvidence) {
        self.evidence = evidence
    }

    public var sessionID: UUID { evidence.sessionID }
}

/// Supplemental immutable storage for observed-peak quality evidence. This stays
/// additive to base ride history so current app persistence owners can adopt it
/// without rewriting the existing completed-ride schema.
public protocol RideHistoryObservedPeakStore: Sendable {
    func commit(_ record: RideHistoryObservedPeakRecord) async throws -> RideHistoryObservedPeakCommitResult
    func record(sessionID: UUID) async throws -> RideHistoryObservedPeakRecord?
}

public enum RideHistoryObservedPeakJoinError: Error, Equatable, Sendable {
    case completedRideMismatch(UUID)
}

/// Runtime-only trusted join between base completed history and its observed-peak
/// quality attachment. Durable storage remains independently validated records.
public struct RideHistoryObservedPeakJoinedRecord: Equatable, Sendable {
    public let historyRecord: RideHistoryRecord
    public let observedPeakRecord: RideHistoryObservedPeakRecord

#if SWIFT_PACKAGE
    package init(
        historyRecord: RideHistoryRecord,
        observedPeakRecord: RideHistoryObservedPeakRecord
    ) throws {
        try Self.validate(historyRecord: historyRecord, observedPeakRecord: observedPeakRecord)
        self.historyRecord = historyRecord
        self.observedPeakRecord = observedPeakRecord
    }
#else
    fileprivate init(
        historyRecord: RideHistoryRecord,
        observedPeakRecord: RideHistoryObservedPeakRecord
    ) throws {
        try Self.validate(historyRecord: historyRecord, observedPeakRecord: observedPeakRecord)
        self.historyRecord = historyRecord
        self.observedPeakRecord = observedPeakRecord
    }
#endif

    public var sessionID: UUID { historyRecord.sessionID }

    public func assessment() throws -> RideObservedPeakHistoryAssessment {
        try observedPeakRecord.evidence.assessment()
    }

    private static func validate(
        historyRecord: RideHistoryRecord,
        observedPeakRecord: RideHistoryObservedPeakRecord
    ) throws {
        do {
            try observedPeakRecord.evidence.validate(against: historyRecord.evidence)
        } catch {
            throw RideHistoryObservedPeakJoinError.completedRideMismatch(historyRecord.sessionID)
        }
    }
}

public enum RideHistoryObservedPeakCommitCoordinatorError: Error, Equatable, Sendable {
    case missingCompletedRide(UUID)
    case completedRideMismatch(UUID)
    case durableVerificationFailed(UUID)
}

/// Commits only after base completed history exists, then requires an exact
/// durable read-back. A missing attachment is ordinary unavailability; an orphan
/// attachment is durable inconsistency and fails closed.
public actor RideHistoryObservedPeakCommitCoordinator {
    private let historyStore: any RideHistoryStore
    private let observedPeakStore: any RideHistoryObservedPeakStore

    public init(
        historyStore: any RideHistoryStore,
        observedPeakStore: any RideHistoryObservedPeakStore
    ) {
        self.historyStore = historyStore
        self.observedPeakStore = observedPeakStore
    }

    @discardableResult
    public func commit(
        _ evidence: RideObservedPeakHistoryEvidence
    ) async throws -> RideHistoryObservedPeakCommitResult {
        guard let historyRecord = try await historyStore.record(sessionID: evidence.sessionID) else {
            throw RideHistoryObservedPeakCommitCoordinatorError.missingCompletedRide(evidence.sessionID)
        }

        do {
            try evidence.validate(against: historyRecord.evidence)
        } catch {
            throw RideHistoryObservedPeakCommitCoordinatorError.completedRideMismatch(evidence.sessionID)
        }

        let record = RideHistoryObservedPeakRecord(evidence: evidence)
        let result = try await observedPeakStore.commit(record)
        guard try await observedPeakStore.record(sessionID: record.sessionID) == record else {
            throw RideHistoryObservedPeakCommitCoordinatorError.durableVerificationFailed(record.sessionID)
        }
        return result
    }

    public func joinedRecord(
        sessionID: UUID
    ) async throws -> RideHistoryObservedPeakJoinedRecord? {
        let historyRecord = try await historyStore.record(sessionID: sessionID)
        let observedPeakRecord = try await observedPeakStore.record(sessionID: sessionID)

        switch (historyRecord, observedPeakRecord) {
        case (nil, nil), (.some, nil):
            return nil
        case (nil, .some):
            throw RideHistoryObservedPeakCommitCoordinatorError.missingCompletedRide(sessionID)
        case let (.some(historyRecord), .some(observedPeakRecord)):
            do {
                return try RideHistoryObservedPeakJoinedRecord(
                    historyRecord: historyRecord,
                    observedPeakRecord: observedPeakRecord
                )
            } catch {
                throw RideHistoryObservedPeakCommitCoordinatorError.completedRideMismatch(sessionID)
            }
        }
    }
}
