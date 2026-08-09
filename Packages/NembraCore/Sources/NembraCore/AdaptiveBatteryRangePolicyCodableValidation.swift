import Foundation

/// `AdaptiveBatteryRangePolicy` has a validating designated initializer, but synthesized
/// `Decodable` would otherwise assign stored properties directly and bypass those invariants.
///
/// Persisted accepted-range checkpoints carry the policy that admitted each candidate so replay
/// can reproduce the original decision. Decoding that policy must therefore cross the same
/// validation boundary as live construction before any persisted history can be replayed into
/// accepted model state.
extension AdaptiveBatteryRangePolicy {
    private enum ValidatedCodingKeys: String, CodingKey {
        case minimumConsumedPercentagePoints
        case minimumDistanceMeters
        case recentWindowCapacity
        case recentWeight
        case outlierLowerEfficiencyRatio
        case outlierUpperEfficiencyRatio
        case estimateDeadbandFraction
        case estimateSmoothingFactor
        case provisionalEfficiencyMetersPerPercentagePoint
        case lowSOCCautionThresholdPercent
        case lowSOCEfficiencyMultiplier
        case lowConfidenceConsumedPercentagePoints
        case normalConfidenceConsumedPercentagePoints
        case highConfidenceConsumedPercentagePoints
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: ValidatedCodingKeys.self)
        try self.init(
            minimumConsumedPercentagePoints: container.decode(
                Double.self,
                forKey: .minimumConsumedPercentagePoints
            ),
            minimumDistanceMeters: container.decode(
                Double.self,
                forKey: .minimumDistanceMeters
            ),
            recentWindowCapacity: container.decode(
                Int.self,
                forKey: .recentWindowCapacity
            ),
            recentWeight: container.decode(
                Double.self,
                forKey: .recentWeight
            ),
            outlierLowerEfficiencyRatio: container.decode(
                Double.self,
                forKey: .outlierLowerEfficiencyRatio
            ),
            outlierUpperEfficiencyRatio: container.decode(
                Double.self,
                forKey: .outlierUpperEfficiencyRatio
            ),
            estimateDeadbandFraction: container.decode(
                Double.self,
                forKey: .estimateDeadbandFraction
            ),
            estimateSmoothingFactor: container.decode(
                Double.self,
                forKey: .estimateSmoothingFactor
            ),
            provisionalEfficiencyMetersPerPercentagePoint: container.decodeIfPresent(
                Double.self,
                forKey: .provisionalEfficiencyMetersPerPercentagePoint
            ),
            lowSOCCautionThresholdPercent: container.decodeIfPresent(
                Double.self,
                forKey: .lowSOCCautionThresholdPercent
            ),
            lowSOCEfficiencyMultiplier: container.decodeIfPresent(
                Double.self,
                forKey: .lowSOCEfficiencyMultiplier
            ),
            lowConfidenceConsumedPercentagePoints: container.decode(
                Double.self,
                forKey: .lowConfidenceConsumedPercentagePoints
            ),
            normalConfidenceConsumedPercentagePoints: container.decode(
                Double.self,
                forKey: .normalConfidenceConsumedPercentagePoints
            ),
            highConfidenceConsumedPercentagePoints: container.decode(
                Double.self,
                forKey: .highConfidenceConsumedPercentagePoints
            )
        )
    }
}
