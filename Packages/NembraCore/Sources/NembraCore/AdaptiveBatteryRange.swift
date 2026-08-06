import Foundation

/// Classifies normalized state-of-charge values before the adaptive range model
/// is allowed to learn from them.
///
/// Raw protocol bytes remain outside this type. A vehicle adapter must first
/// decode raw evidence into a normalized SoC reading and preserve whether that
/// value was actually measured or estimated.
public enum BatterySOCProvenance: String, Codable, Sendable {
    case authoritativeMeasurement
    case estimate
}

public enum BatteryRangeValidationError: Error, Equatable, Sendable {
    case invalidSOCPercentage
    case invalidDistance
    case invalidTimestampOrder
    case invalidPolicy
}

/// One normalized SoC reading. Estimated values are intentionally representable
/// because they may be useful for presentation, but they are never accepted as
/// learning evidence by `AdaptiveBatteryRangeModel`.
public struct BatterySOCReading: Equatable, Codable, Sendable {
    public let percentage: Double
    public let provenance: BatterySOCProvenance
    public let receivedAtUptimeNanoseconds: UInt64

    public init(
        percentage: Double,
        provenance: BatterySOCProvenance,
        receivedAtUptimeNanoseconds: UInt64
    ) throws {
        guard percentage.isFinite, (0...100).contains(percentage) else {
            throw BatteryRangeValidationError.invalidSOCPercentage
        }

        self.percentage = percentage
        self.provenance = provenance
        self.receivedAtUptimeNanoseconds = receivedAtUptimeNanoseconds
    }

    public var isAuthoritativeMeasurement: Bool {
        provenance == .authoritativeMeasurement
    }
}

/// A ride segment that can potentially teach the range model how far this
/// scooter travels for each authoritative battery percentage point consumed.
public struct BatteryRangeLearningWindow: Equatable, Codable, Sendable {
    public let distanceMeters: Double
    public let startSOC: BatterySOCReading
    public let endSOC: BatterySOCReading

    public init(
        distanceMeters: Double,
        startSOC: BatterySOCReading,
        endSOC: BatterySOCReading
    ) throws {
        guard distanceMeters.isFinite, distanceMeters >= 0 else {
            throw BatteryRangeValidationError.invalidDistance
        }
        guard endSOC.receivedAtUptimeNanoseconds > startSOC.receivedAtUptimeNanoseconds else {
            throw BatteryRangeValidationError.invalidTimestampOrder
        }

        self.distanceMeters = distanceMeters
        self.startSOC = startSOC
        self.endSOC = endSOC
    }

    public var consumedPercentagePoints: Double {
        startSOC.percentage - endSOC.percentage
    }
}

public struct BatteryRangeEfficiencySample: Equatable, Codable, Sendable {
    public let distanceMeters: Double
    public let consumedPercentagePoints: Double
    public let metersPerPercentagePoint: Double

    init(distanceMeters: Double, consumedPercentagePoints: Double) {
        self.distanceMeters = distanceMeters
        self.consumedPercentagePoints = consumedPercentagePoints
        self.metersPerPercentagePoint = distanceMeters / consumedPercentagePoints
    }
}

public enum AdaptiveRangeConfidence: String, Codable, Sendable {
    case learning
    case low
    case normal
    case high
}

public enum BatteryRangeLearningRejectionReason: String, Equatable, Sendable {
    case nonAuthoritativeSOC
    case nonConsumptionWindow
    case insufficientSOCConsumption
    case insufficientDistance
    case efficiencyOutlier
}

public enum BatteryRangeLearningDisposition: Equatable, Sendable {
    case accepted
    case rejected(BatteryRangeLearningRejectionReason)
}

public struct BatteryRangeLearningResult: Equatable, Sendable {
    public let disposition: BatteryRangeLearningDisposition
    public let sample: BatteryRangeEfficiencySample?
    public let confidence: AdaptiveRangeConfidence
}

/// Explicit tuning knobs for the learned percentage-based estimator.
///
/// The defaults are supplied by the application/vehicle profile rather than
/// hidden inside the model so ES80 field evidence can later change thresholds
/// without rewriting the algorithm.
public struct AdaptiveBatteryRangePolicy: Equatable, Codable, Sendable {
    public let minimumConsumedPercentagePoints: Double
    public let minimumDistanceMeters: Double
    public let recentWindowCapacity: Int
    public let recentWeight: Double
    public let outlierLowerEfficiencyRatio: Double
    public let outlierUpperEfficiencyRatio: Double
    public let estimateDeadbandFraction: Double
    public let estimateSmoothingFactor: Double
    public let lowSOCCautionThresholdPercent: Double?
    public let lowSOCEfficiencyMultiplier: Double?
    public let lowConfidenceConsumedPercentagePoints: Double
    public let normalConfidenceConsumedPercentagePoints: Double
    public let highConfidenceConsumedPercentagePoints: Double

    public init(
        minimumConsumedPercentagePoints: Double,
        minimumDistanceMeters: Double,
        recentWindowCapacity: Int,
        recentWeight: Double,
        outlierLowerEfficiencyRatio: Double,
        outlierUpperEfficiencyRatio: Double,
        estimateDeadbandFraction: Double,
        estimateSmoothingFactor: Double,
        lowSOCCautionThresholdPercent: Double? = nil,
        lowSOCEfficiencyMultiplier: Double? = nil,
        lowConfidenceConsumedPercentagePoints: Double,
        normalConfidenceConsumedPercentagePoints: Double,
        highConfidenceConsumedPercentagePoints: Double
    ) throws {
        let finiteScalars = [
            minimumConsumedPercentagePoints,
            minimumDistanceMeters,
            recentWeight,
            outlierLowerEfficiencyRatio,
            outlierUpperEfficiencyRatio,
            estimateDeadbandFraction,
            estimateSmoothingFactor,
            lowConfidenceConsumedPercentagePoints,
            normalConfidenceConsumedPercentagePoints,
            highConfidenceConsumedPercentagePoints
        ]
        guard finiteScalars.allSatisfy(\.isFinite),
              minimumConsumedPercentagePoints > 0,
              minimumConsumedPercentagePoints <= 100,
              minimumDistanceMeters > 0,
              recentWindowCapacity > 0,
              (0...1).contains(recentWeight),
              outlierLowerEfficiencyRatio > 0,
              outlierLowerEfficiencyRatio <= 1,
              outlierUpperEfficiencyRatio >= 1,
              outlierUpperEfficiencyRatio >= outlierLowerEfficiencyRatio,
              estimateDeadbandFraction >= 0,
              estimateDeadbandFraction <= 1,
              estimateSmoothingFactor > 0,
              estimateSmoothingFactor <= 1,
              lowConfidenceConsumedPercentagePoints > 0,
              normalConfidenceConsumedPercentagePoints > lowConfidenceConsumedPercentagePoints,
              highConfidenceConsumedPercentagePoints > normalConfidenceConsumedPercentagePoints else {
            throw BatteryRangeValidationError.invalidPolicy
        }

        switch (lowSOCCautionThresholdPercent, lowSOCEfficiencyMultiplier) {
        case (nil, nil):
            break
        case let (threshold?, multiplier?):
            guard threshold.isFinite,
                  threshold > 0,
                  threshold <= 100,
                  multiplier.isFinite,
                  multiplier > 0,
                  multiplier <= 1 else {
                throw BatteryRangeValidationError.invalidPolicy
            }
        default:
            throw BatteryRangeValidationError.invalidPolicy
        }

        self.minimumConsumedPercentagePoints = minimumConsumedPercentagePoints
        self.minimumDistanceMeters = minimumDistanceMeters
        self.recentWindowCapacity = recentWindowCapacity
        self.recentWeight = recentWeight
        self.outlierLowerEfficiencyRatio = outlierLowerEfficiencyRatio
        self.outlierUpperEfficiencyRatio = outlierUpperEfficiencyRatio
        self.estimateDeadbandFraction = estimateDeadbandFraction
        self.estimateSmoothingFactor = estimateSmoothingFactor
        self.lowSOCCautionThresholdPercent = lowSOCCautionThresholdPercent
        self.lowSOCEfficiencyMultiplier = lowSOCEfficiencyMultiplier
        self.lowConfidenceConsumedPercentagePoints = lowConfidenceConsumedPercentagePoints
        self.normalConfidenceConsumedPercentagePoints = normalConfidenceConsumedPercentagePoints
        self.highConfidenceConsumedPercentagePoints = highConfidenceConsumedPercentagePoints
    }
}

public struct AdaptiveBatteryRangeEstimate: Equatable, Codable, Sendable {
    /// Range produced directly from learned efficiency and the current SoC
    /// before display hysteresis/smoothing.
    public let rawRemainingMeters: Double
    /// Range suitable for presentation after deadband and smoothing.
    public let presentedRemainingMeters: Double
    public let learnedMetersPerPercentagePoint: Double
    public let confidence: AdaptiveRangeConfidence
    public let socProvenance: BatterySOCProvenance
    public let lowSOCConservatismApplied: Bool
}

/// Persistable learning state for one physical scooter.
///
/// This model intentionally learns only distance per authoritative battery
/// percentage point. It never invents current, watts, watt-hours, or Wh/mi.
public struct AdaptiveBatteryRangeModel: Equatable, Codable, Sendable {
    public private(set) var historicalEfficiencyMetersPerPercentagePoint: Double?
    public private(set) var historicalConsumedPercentagePoints: Double
    public private(set) var recentSamples: [BatteryRangeEfficiencySample]
    public private(set) var acceptedWindowCount: Int

    public init() {
        historicalEfficiencyMetersPerPercentagePoint = nil
        historicalConsumedPercentagePoints = 0
        recentSamples = []
        acceptedWindowCount = 0
    }

    public var hasLearnedEfficiency: Bool {
        historicalEfficiencyMetersPerPercentagePoint != nil
    }

    public func confidence(using policy: AdaptiveBatteryRangePolicy) -> AdaptiveRangeConfidence {
        let evidence = historicalConsumedPercentagePoints
        if evidence >= policy.highConfidenceConsumedPercentagePoints {
            return .high
        }
        if evidence >= policy.normalConfidenceConsumedPercentagePoints {
            return .normal
        }
        if evidence >= policy.lowConfidenceConsumedPercentagePoints {
            return .low
        }
        return .learning
    }

    public func blendedEfficiencyMetersPerPercentagePoint(
        using policy: AdaptiveBatteryRangePolicy
    ) -> Double? {
        let recentEfficiency = weightedRecentEfficiency()

        switch (historicalEfficiencyMetersPerPercentagePoint, recentEfficiency) {
        case let (historical?, recent?):
            return historical * (1 - policy.recentWeight) + recent * policy.recentWeight
        case let (historical?, nil):
            return historical
        case let (nil, recent?):
            return recent
        case (nil, nil):
            return nil
        }
    }

    public func typicalFullChargeRangeMeters(
        using policy: AdaptiveBatteryRangePolicy
    ) -> Double? {
        blendedEfficiencyMetersPerPercentagePoint(using: policy).map { $0 * 100 }
    }

    @discardableResult
    public mutating func ingest(
        _ window: BatteryRangeLearningWindow,
        policy: AdaptiveBatteryRangePolicy
    ) -> BatteryRangeLearningResult {
        guard window.startSOC.isAuthoritativeMeasurement,
              window.endSOC.isAuthoritativeMeasurement else {
            return rejected(.nonAuthoritativeSOC, policy: policy)
        }

        let consumed = window.consumedPercentagePoints
        guard consumed > 0 else {
            return rejected(.nonConsumptionWindow, policy: policy)
        }
        guard consumed >= policy.minimumConsumedPercentagePoints else {
            return rejected(.insufficientSOCConsumption, policy: policy)
        }
        guard window.distanceMeters >= policy.minimumDistanceMeters else {
            return rejected(.insufficientDistance, policy: policy)
        }

        let sample = BatteryRangeEfficiencySample(
            distanceMeters: window.distanceMeters,
            consumedPercentagePoints: consumed
        )

        if let baseline = blendedEfficiencyMetersPerPercentagePoint(using: policy) {
            let ratio = sample.metersPerPercentagePoint / baseline
            if ratio < policy.outlierLowerEfficiencyRatio || ratio > policy.outlierUpperEfficiencyRatio {
                return rejected(.efficiencyOutlier, policy: policy)
            }
        }

        let oldConsumed = historicalConsumedPercentagePoints
        if let historical = historicalEfficiencyMetersPerPercentagePoint {
            let weightedDistance = historical * oldConsumed + sample.metersPerPercentagePoint * consumed
            historicalConsumedPercentagePoints = oldConsumed + consumed
            historicalEfficiencyMetersPerPercentagePoint = weightedDistance / historicalConsumedPercentagePoints
        } else {
            historicalConsumedPercentagePoints = consumed
            historicalEfficiencyMetersPerPercentagePoint = sample.metersPerPercentagePoint
        }

        recentSamples.append(sample)
        if recentSamples.count > policy.recentWindowCapacity {
            recentSamples.removeFirst(recentSamples.count - policy.recentWindowCapacity)
        }
        acceptedWindowCount += 1

        return BatteryRangeLearningResult(
            disposition: .accepted,
            sample: sample,
            confidence: confidence(using: policy)
        )
    }

    /// Returns `nil` until at least one meaningful authoritative learning window
    /// has been accepted. This prevents the product from silently falling back
    /// to advertised-range multiplication.
    public func estimateRemainingRange(
        at soc: BatterySOCReading,
        previousPresentedRemainingMeters: Double? = nil,
        policy: AdaptiveBatteryRangePolicy
    ) -> AdaptiveBatteryRangeEstimate? {
        guard let efficiency = blendedEfficiencyMetersPerPercentagePoint(using: policy) else {
            return nil
        }

        var rawRemainingMeters = efficiency * soc.percentage
        var lowSOCConservatismApplied = false

        if let threshold = policy.lowSOCCautionThresholdPercent,
           let multiplier = policy.lowSOCEfficiencyMultiplier,
           soc.percentage < threshold {
            let fractionOfThreshold = soc.percentage / threshold
            let gradualMultiplier = multiplier + (1 - multiplier) * fractionOfThreshold
            rawRemainingMeters *= gradualMultiplier
            lowSOCConservatismApplied = true
        }

        let presentedRemainingMeters = smoothEstimate(
            rawRemainingMeters,
            previousPresentedRemainingMeters: previousPresentedRemainingMeters,
            policy: policy
        )

        return AdaptiveBatteryRangeEstimate(
            rawRemainingMeters: rawRemainingMeters,
            presentedRemainingMeters: presentedRemainingMeters,
            learnedMetersPerPercentagePoint: efficiency,
            confidence: confidence(using: policy),
            socProvenance: soc.provenance,
            lowSOCConservatismApplied: lowSOCConservatismApplied
        )
    }

    private func weightedRecentEfficiency() -> Double? {
        let totalConsumed = recentSamples.reduce(0.0) { $0 + $1.consumedPercentagePoints }
        guard totalConsumed > 0 else { return nil }

        let weighted = recentSamples.reduce(0.0) {
            $0 + $1.metersPerPercentagePoint * $1.consumedPercentagePoints
        }
        return weighted / totalConsumed
    }

    private func rejected(
        _ reason: BatteryRangeLearningRejectionReason,
        policy: AdaptiveBatteryRangePolicy
    ) -> BatteryRangeLearningResult {
        BatteryRangeLearningResult(
            disposition: .rejected(reason),
            sample: nil,
            confidence: confidence(using: policy)
        )
    }

    private func smoothEstimate(
        _ rawRemainingMeters: Double,
        previousPresentedRemainingMeters: Double?,
        policy: AdaptiveBatteryRangePolicy
    ) -> Double {
        guard let previous = previousPresentedRemainingMeters,
              previous.isFinite,
              previous >= 0 else {
            return rawRemainingMeters
        }

        let deadbandMeters = max(previous, rawRemainingMeters) * policy.estimateDeadbandFraction
        let delta = rawRemainingMeters - previous
        guard abs(delta) > deadbandMeters else {
            return previous
        }

        return previous + delta * policy.estimateSmoothingFactor
    }
}
