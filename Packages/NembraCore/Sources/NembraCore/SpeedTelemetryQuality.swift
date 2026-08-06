import Foundation

public enum SpeedTelemetryQualityPolicyError: Error, Equatable, Sendable {
    case invalidMinimumAcceptedSampleCount
    case invalidMaximumRejectedSampleFraction
    case invalidMinimumDeliveryLatencySampleFraction
    case invalidThreshold
}

/// Evidence requirements for deciding whether one measured speed source is
/// suitable for a specific feature. Every threshold is injected by the caller;
/// this type deliberately contains no guessed ES80 cadence, latency, jitter, or
/// resolution constants.
public struct SpeedTelemetryQualityPolicy: Equatable, Sendable {
    public let requiredSource: SpeedTelemetrySource?
    public let minimumAcceptedSampleCount: Int
    public let maximumRejectedSampleFraction: Double?
    public let maximumMeanIntervalMilliseconds: Double?
    public let maximumObservedIntervalMilliseconds: Double?
    public let maximumJitterStandardDeviationMilliseconds: Double?
    public let minimumDeliveryLatencySampleFraction: Double?
    public let maximumMeanDeliveryLatencyMilliseconds: Double?
    public let maximumEmpiricalSpeedStepKilometersPerHour: Double?

    public init(
        requiredSource: SpeedTelemetrySource? = nil,
        minimumAcceptedSampleCount: Int = 1,
        maximumRejectedSampleFraction: Double? = nil,
        maximumMeanIntervalMilliseconds: Double? = nil,
        maximumObservedIntervalMilliseconds: Double? = nil,
        maximumJitterStandardDeviationMilliseconds: Double? = nil,
        minimumDeliveryLatencySampleFraction: Double? = nil,
        maximumMeanDeliveryLatencyMilliseconds: Double? = nil,
        maximumEmpiricalSpeedStepKilometersPerHour: Double? = nil
    ) throws {
        guard minimumAcceptedSampleCount > 0 else {
            throw SpeedTelemetryQualityPolicyError.invalidMinimumAcceptedSampleCount
        }
        if let maximumRejectedSampleFraction {
            guard maximumRejectedSampleFraction.isFinite,
                  (0...1).contains(maximumRejectedSampleFraction) else {
                throw SpeedTelemetryQualityPolicyError.invalidMaximumRejectedSampleFraction
            }
        }
        if let minimumDeliveryLatencySampleFraction {
            guard minimumDeliveryLatencySampleFraction.isFinite,
                  (0...1).contains(minimumDeliveryLatencySampleFraction) else {
                throw SpeedTelemetryQualityPolicyError.invalidMinimumDeliveryLatencySampleFraction
            }
        }
        let thresholds = [
            maximumMeanIntervalMilliseconds,
            maximumObservedIntervalMilliseconds,
            maximumJitterStandardDeviationMilliseconds,
            maximumMeanDeliveryLatencyMilliseconds,
            maximumEmpiricalSpeedStepKilometersPerHour
        ]
        guard thresholds.allSatisfy({ threshold in
            guard let threshold else { return true }
            return threshold.isFinite && threshold >= 0
        }) else {
            throw SpeedTelemetryQualityPolicyError.invalidThreshold
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
}

public enum SpeedTelemetryQualityFailure: Equatable, Sendable {
    case sourceMismatch(expected: SpeedTelemetrySource, actual: SpeedTelemetrySource)
    case insufficientAcceptedSamples(required: Int, actual: Int)
    case rejectedSampleFractionExceeded(maximum: Double, actual: Double)
    case missingIntervalEvidence
    case meanIntervalExceeded(maximumMilliseconds: Double, actualMilliseconds: Double)
    case observedIntervalExceeded(maximumMilliseconds: Double, actualMilliseconds: Double)
    case jitterExceeded(maximumMilliseconds: Double, actualMilliseconds: Double)
    case missingDeliveryLatencyEvidence
    case deliveryLatencySampleFractionBelowMinimum(minimum: Double, actual: Double)
    case deliveryLatencyExceeded(maximumMilliseconds: Double, actualMilliseconds: Double)
    case missingSpeedResolutionEvidence
    case speedResolutionStepExceeded(
        maximumKilometersPerHour: Double,
        actualKilometersPerHour: Double
    )
}

public struct SpeedTelemetryQualityAssessment: Equatable, Sendable {
    public let source: SpeedTelemetrySource
    public let failures: [SpeedTelemetryQualityFailure]

    public var isQualified: Bool {
        failures.isEmpty
    }
}

public extension TelemetryBenchmarkSummary {
    /// Applies caller-selected evidence requirements to an already measured
    /// benchmark summary. This does not rank sources, invent missing metrics, or
    /// promote a source to hardware truth; it only states whether the summary
    /// satisfies the supplied policy.
    func qualityAssessment(
        using policy: SpeedTelemetryQualityPolicy
    ) -> SpeedTelemetryQualityAssessment {
        var failures: [SpeedTelemetryQualityFailure] = []

        if let requiredSource = policy.requiredSource, source != requiredSource {
            failures.append(.sourceMismatch(expected: requiredSource, actual: source))
        }

        if acceptedSampleCount < policy.minimumAcceptedSampleCount {
            failures.append(.insufficientAcceptedSamples(
                required: policy.minimumAcceptedSampleCount,
                actual: acceptedSampleCount
            ))
        }

        if let maximumRejectedSampleFraction = policy.maximumRejectedSampleFraction {
            let total = Double(acceptedSampleCount) + Double(rejectedSampleCount)
            let actualFraction = total > 0 ? Double(rejectedSampleCount) / total : 0
            if actualFraction > maximumRejectedSampleFraction {
                failures.append(.rejectedSampleFractionExceeded(
                    maximum: maximumRejectedSampleFraction,
                    actual: actualFraction
                ))
            }
        }

        let requiresIntervalEvidence =
            policy.maximumMeanIntervalMilliseconds != nil ||
            policy.maximumObservedIntervalMilliseconds != nil ||
            policy.maximumJitterStandardDeviationMilliseconds != nil

        if requiresIntervalEvidence && intervalCount == 0 {
            failures.append(.missingIntervalEvidence)
        } else if intervalCount > 0 {
            if let maximum = policy.maximumMeanIntervalMilliseconds,
               let actual = meanIntervalMilliseconds,
               actual > maximum {
                failures.append(.meanIntervalExceeded(
                    maximumMilliseconds: maximum,
                    actualMilliseconds: actual
                ))
            }
            if let maximum = policy.maximumObservedIntervalMilliseconds,
               let actual = maximumIntervalMilliseconds,
               actual > maximum {
                failures.append(.observedIntervalExceeded(
                    maximumMilliseconds: maximum,
                    actualMilliseconds: actual
                ))
            }
            if let maximum = policy.maximumJitterStandardDeviationMilliseconds,
               let actual = intervalJitterStandardDeviationMilliseconds,
               actual > maximum {
                failures.append(.jitterExceeded(
                    maximumMilliseconds: maximum,
                    actualMilliseconds: actual
                ))
            }
        }

        let requiresDeliveryLatencyEvidence =
            (policy.minimumDeliveryLatencySampleFraction ?? 0) > 0 ||
            policy.maximumMeanDeliveryLatencyMilliseconds != nil
        if requiresDeliveryLatencyEvidence && deliveryLatencySampleCount == 0 {
            failures.append(.missingDeliveryLatencyEvidence)
        }

        if let minimum = policy.minimumDeliveryLatencySampleFraction {
            let actualFraction = acceptedSampleCount > 0
                ? Double(deliveryLatencySampleCount) / Double(acceptedSampleCount)
                : 0
            if actualFraction < minimum {
                failures.append(.deliveryLatencySampleFractionBelowMinimum(
                    minimum: minimum,
                    actual: actualFraction
                ))
            }
        }

        if let maximum = policy.maximumMeanDeliveryLatencyMilliseconds,
           let actual = meanDeliveryLatencyMilliseconds,
           deliveryLatencySampleCount > 0,
           actual > maximum {
            failures.append(.deliveryLatencyExceeded(
                maximumMilliseconds: maximum,
                actualMilliseconds: actual
            ))
        }

        if let maximum = policy.maximumEmpiricalSpeedStepKilometersPerHour {
            if let actual = empiricalMinimumNonzeroSpeedStepKilometersPerHour {
                if actual > maximum {
                    failures.append(.speedResolutionStepExceeded(
                        maximumKilometersPerHour: maximum,
                        actualKilometersPerHour: actual
                    ))
                }
            } else {
                failures.append(.missingSpeedResolutionEvidence)
            }
        }

        return SpeedTelemetryQualityAssessment(source: source, failures: failures)
    }
}
