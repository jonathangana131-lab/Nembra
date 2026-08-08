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

/// Codable mirror of the complete caller-supplied telemetry policy needed to
/// re-evaluate an observed peak after relaunch. No qualification verdict is stored.
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
            _ = try RideObservedPeakQualityPolicy(
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
        let c = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                requiredSource: c.decode(SpeedTelemetrySource.self, forKey: .requiredSource),
                minimumAcceptedSampleCount: c.decode(Int.self, forKey: .minimumAcceptedSampleCount),
                maximumRejectedSampleFraction: c.decode(Double.self, forKey: .maximumRejectedSampleFraction),
                maximumMeanIntervalMilliseconds: c.decode(Double.self, forKey: .maximumMeanIntervalMilliseconds),
                maximumObservedIntervalMilliseconds: c.decode(Double.self, forKey: .maximumObservedIntervalMilliseconds),
                maximumJitterStandardDeviationMilliseconds: c.decode(Double.self, forKey: .maximumJitterStandardDeviationMilliseconds),
                minimumDeliveryLatencySampleFraction: c.decodeIfPresent(Double.self, forKey: .minimumDeliveryLatencySampleFraction),
                maximumMeanDeliveryLatencyMilliseconds: c.decodeIfPresent(Double.self, forKey: .maximumMeanDeliveryLatencyMilliseconds),
                maximumEmpiricalSpeedStepKilometersPerHour: c.decode(Double.self, forKey: .maximumEmpiricalSpeedStepKilometersPerHour)
            )
        } catch {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Observed-peak history policy is invalid: \(error)."
            ))
        }
    }
}

/// Durable raw benchmark facts. These inputs can be re-assessed under the
/// retained policy; no display interpolation or cached quality result is persisted.
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
                  let rate = effectiveSampleRateHertz,
                  let mean = meanIntervalMilliseconds,
                  let minimum = minimumIntervalMilliseconds,
                  let maximum = maximumIntervalMilliseconds,
                  let jitter = intervalJitterStandardDeviationMilliseconds,
                  rate.isFinite, rate > 0,
                  mean.isFinite, mean > 0,
                  minimum.isFinite, minimum > 0,
                  maximum.isFinite, maximum >= mean,
                  mean >= minimum,
                  jitter.isFinite, jitter >= 0 else {
                throw RideObservedPeakHistoryEvidenceError.invalidBenchmark
            }
        }

        if let step = empiricalMinimumNonzeroSpeedStepKilometersPerHour {
            guard step.isFinite, step > 0 else {
                throw RideObservedPeakHistoryEvidenceError.invalidBenchmark
            }
        }

        if deliveryLatencySampleCount == 0 {
            guard meanDeliveryLatencyMilliseconds == nil,
                  minimumDeliveryLatencyMilliseconds == nil,
                  maximumDeliveryLatencyMilliseconds == nil,
                  deliveryLatencyStandardDeviationMilliseconds == nil else {
                throw RideObservedPeakHistoryEvidenceError.invalidBenchmark
            }
        } else {
            guard let mean = meanDeliveryLatencyMilliseconds,
                  let minimum = minimumDeliveryLatencyMilliseconds,
                  let maximum = maximumDeliveryLatencyMilliseconds,
                  let deviation = deliveryLatencyStandardDeviationMilliseconds,
                  mean.isFinite, minimum.isFinite, maximum.isFinite, deviation.isFinite,
                  minimum >= 0, mean >= minimum, maximum >= mean, deviation >= 0 else {
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
        let c = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                source: c.decode(SpeedTelemetrySource.self, forKey: .source),
                acceptedSampleCount: c.decode(Int.self, forKey: .acceptedSampleCount),
                rejectedSampleCount: c.decode(Int.self, forKey: .rejectedSampleCount),
                observationSegmentCount: c.decode(Int.self, forKey: .observationSegmentCount),
                knownObservationInterruptionCount: c.decode(Int.self, forKey: .knownObservationInterruptionCount),
                intervalCount: c.decode(Int.self, forKey: .intervalCount),
                observedDurationSeconds: c.decode(Double.self, forKey: .observedDurationSeconds),
                effectiveSampleRateHertz: c.decodeIfPresent(Double.self, forKey: .effectiveSampleRateHertz),
                meanIntervalMilliseconds: c.decodeIfPresent(Double.self, forKey: .meanIntervalMilliseconds),
                minimumIntervalMilliseconds: c.decodeIfPresent(Double.self, forKey: .minimumIntervalMilliseconds),
                maximumIntervalMilliseconds: c.decodeIfPresent(Double.self, forKey: .maximumIntervalMilliseconds),
                intervalJitterStandardDeviationMilliseconds: c.decodeIfPresent(Double.self, forKey: .intervalJitterStandardDeviationMilliseconds),
                duplicateSpeedValueCount: c.decode(Int.self, forKey: .duplicateSpeedValueCount),
                empiricalMinimumNonzeroSpeedStepKilometersPerHour: c.decodeIfPresent(Double.self, forKey: .empiricalMinimumNonzeroSpeedStepKilometersPerHour),
                deliveryLatencySampleCount: c.decode(Int.self, forKey: .deliveryLatencySampleCount),
                meanDeliveryLatencyMilliseconds: c.decodeIfPresent(Double.self, forKey: .meanDeliveryLatencyMilliseconds),
                minimumDeliveryLatencyMilliseconds: c.decodeIfPresent(Double.self, forKey: .minimumDeliveryLatencyMilliseconds),
                maximumDeliveryLatencyMilliseconds: c.decodeIfPresent(Double.self, forKey: .maximumDeliveryLatencyMilliseconds),
                deliveryLatencyStandardDeviationMilliseconds: c.decodeIfPresent(Double.self, forKey: .deliveryLatencyStandardDeviationMilliseconds)
            )
        } catch {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Observed-peak benchmark history is invalid: \(error)."
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
        var total = 0
        for value in values {
            guard value >= 0 else { throw RideObservedPeakHistoryEvidenceError.invalidCount }
            let addition = total.addingReportingOverflow(value)
            guard !addition.overflow else { throw RideObservedPeakHistoryEvidenceError.invalidCount }
            total = addition.partialValue
        }

        self.nonAuthoritativeSampleCount = nonAuthoritativeSampleCount
        self.sourceMismatchSampleCount = sourceMismatchSampleCount
        self.nonIncreasingTimestampCount = nonIncreasingTimestampCount
        self.nonFiniteDerivedSpeedCount = nonFiniteDerivedSpeedCount
        self.speedAccuracyUnavailableCount = speedAccuracyUnavailableCount
        self.speedAccuracyExceededCount = speedAccuracyExceededCount
    }

    package var totalRejectedSampleCount: Int {
        nonAuthoritativeSampleCount
            + sourceMismatchSampleCount
            + nonIncreasingTimestampCount
            + nonFiniteDerivedSpeedCount
            + speedAccuracyUnavailableCount
            + speedAccuracyExceededCount
    }

    private enum CodingKeys: String, CodingKey {
        case nonAuthoritativeSampleCount, sourceMismatchSampleCount, nonIncreasingTimestampCount
        case nonFiniteDerivedSpeedCount, speedAccuracyUnavailableCount, speedAccuracyExceededCount
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                nonAuthoritativeSampleCount: c.decode(Int.self, forKey: .nonAuthoritativeSampleCount),
                sourceMismatchSampleCount: c.decode(Int.self, forKey: .sourceMismatchSampleCount),
                nonIncreasingTimestampCount: c.decode(Int.self, forKey: .nonIncreasingTimestampCount),
                nonFiniteDerivedSpeedCount: c.decode(Int.self, forKey: .nonFiniteDerivedSpeedCount),
                speedAccuracyUnavailableCount: c.decode(Int.self, forKey: .speedAccuracyUnavailableCount),
                speedAccuracyExceededCount: c.decode(Int.self, forKey: .speedAccuracyExceededCount)
            )
        } catch {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Observed-peak rejection history is invalid: \(error)."
            ))
        }
    }
}
