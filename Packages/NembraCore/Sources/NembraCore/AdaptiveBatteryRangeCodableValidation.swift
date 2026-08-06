import Foundation

/// Codable restore must cross the same validation boundary as live normalized
/// battery evidence. Synthesized decoding would otherwise assign stored values
/// directly and bypass the throwing initializer.
extension BatterySOCReading {
    private enum CodableValidationKeys: String, CodingKey {
        case percentage
        case provenance
        case receivedAtUptimeNanoseconds
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodableValidationKeys.self)
        let percentage = try container.decode(Double.self, forKey: .percentage)
        let provenance = try container.decode(BatterySOCProvenance.self, forKey: .provenance)
        let uptime = try container.decode(UInt64.self, forKey: .receivedAtUptimeNanoseconds)

        do {
            try self.init(
                percentage: percentage,
                provenance: provenance,
                receivedAtUptimeNanoseconds: uptime
            )
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .percentage,
                in: container,
                debugDescription: "Decoded battery SoC reading violates normalization invariants."
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodableValidationKeys.self)
        try container.encode(percentage, forKey: .percentage)
        try container.encode(provenance, forKey: .provenance)
        try container.encode(receivedAtUptimeNanoseconds, forKey: .receivedAtUptimeNanoseconds)
    }
}

/// Persisted/imported learning windows must not bypass distance or monotonic-time
/// validation merely because their JSON shape is syntactically valid.
extension BatteryRangeLearningWindow {
    private enum CodableValidationKeys: String, CodingKey {
        case distanceMeters
        case distanceCoverage
        case transportGapOccurred
        case startSOC
        case endSOC
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodableValidationKeys.self)
        let distanceMeters = try container.decode(Double.self, forKey: .distanceMeters)
        let distanceCoverage = try container.decode(
            BatteryRangeDistanceCoverage.self,
            forKey: .distanceCoverage
        )
        let transportGapOccurred = try container.decode(Bool.self, forKey: .transportGapOccurred)
        let startSOC = try container.decode(BatterySOCReading.self, forKey: .startSOC)
        let endSOC = try container.decode(BatterySOCReading.self, forKey: .endSOC)

        do {
            try self.init(
                distanceMeters: distanceMeters,
                distanceCoverage: distanceCoverage,
                transportGapOccurred: transportGapOccurred,
                startSOC: startSOC,
                endSOC: endSOC
            )
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .distanceMeters,
                in: container,
                debugDescription: "Decoded battery-range learning window violates evidence invariants."
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodableValidationKeys.self)
        try container.encode(distanceMeters, forKey: .distanceMeters)
        try container.encode(distanceCoverage, forKey: .distanceCoverage)
        try container.encode(transportGapOccurred, forKey: .transportGapOccurred)
        try container.encode(startSOC, forKey: .startSOC)
        try container.encode(endSOC, forKey: .endSOC)
    }
}

/// Policy is configuration rather than telemetry, but invalid restored policy can
/// still crash or corrupt range behavior (for example a non-positive recent
/// capacity). Decode through the validated initializer instead of assigning
/// stored properties directly.
extension AdaptiveBatteryRangePolicy {
    private enum CodableValidationKeys: String, CodingKey {
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
        let container = try decoder.container(keyedBy: CodableValidationKeys.self)

        do {
            try self.init(
                minimumConsumedPercentagePoints: try container.decode(
                    Double.self,
                    forKey: .minimumConsumedPercentagePoints
                ),
                minimumDistanceMeters: try container.decode(Double.self, forKey: .minimumDistanceMeters),
                recentWindowCapacity: try container.decode(Int.self, forKey: .recentWindowCapacity),
                recentWeight: try container.decode(Double.self, forKey: .recentWeight),
                outlierLowerEfficiencyRatio: try container.decode(
                    Double.self,
                    forKey: .outlierLowerEfficiencyRatio
                ),
                outlierUpperEfficiencyRatio: try container.decode(
                    Double.self,
                    forKey: .outlierUpperEfficiencyRatio
                ),
                estimateDeadbandFraction: try container.decode(
                    Double.self,
                    forKey: .estimateDeadbandFraction
                ),
                estimateSmoothingFactor: try container.decode(
                    Double.self,
                    forKey: .estimateSmoothingFactor
                ),
                provisionalEfficiencyMetersPerPercentagePoint: try container.decodeIfPresent(
                    Double.self,
                    forKey: .provisionalEfficiencyMetersPerPercentagePoint
                ),
                lowSOCCautionThresholdPercent: try container.decodeIfPresent(
                    Double.self,
                    forKey: .lowSOCCautionThresholdPercent
                ),
                lowSOCEfficiencyMultiplier: try container.decodeIfPresent(
                    Double.self,
                    forKey: .lowSOCEfficiencyMultiplier
                ),
                lowConfidenceConsumedPercentagePoints: try container.decode(
                    Double.self,
                    forKey: .lowConfidenceConsumedPercentagePoints
                ),
                normalConfidenceConsumedPercentagePoints: try container.decode(
                    Double.self,
                    forKey: .normalConfidenceConsumedPercentagePoints
                ),
                highConfidenceConsumedPercentagePoints: try container.decode(
                    Double.self,
                    forKey: .highConfidenceConsumedPercentagePoints
                )
            )
        } catch let error as DecodingError {
            throw error
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .recentWindowCapacity,
                in: container,
                debugDescription: "Decoded adaptive battery-range policy violates validation invariants."
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodableValidationKeys.self)
        try container.encode(minimumConsumedPercentagePoints, forKey: .minimumConsumedPercentagePoints)
        try container.encode(minimumDistanceMeters, forKey: .minimumDistanceMeters)
        try container.encode(recentWindowCapacity, forKey: .recentWindowCapacity)
        try container.encode(recentWeight, forKey: .recentWeight)
        try container.encode(outlierLowerEfficiencyRatio, forKey: .outlierLowerEfficiencyRatio)
        try container.encode(outlierUpperEfficiencyRatio, forKey: .outlierUpperEfficiencyRatio)
        try container.encode(estimateDeadbandFraction, forKey: .estimateDeadbandFraction)
        try container.encode(estimateSmoothingFactor, forKey: .estimateSmoothingFactor)
        try container.encodeIfPresent(
            provisionalEfficiencyMetersPerPercentagePoint,
            forKey: .provisionalEfficiencyMetersPerPercentagePoint
        )
        try container.encodeIfPresent(lowSOCCautionThresholdPercent, forKey: .lowSOCCautionThresholdPercent)
        try container.encodeIfPresent(lowSOCEfficiencyMultiplier, forKey: .lowSOCEfficiencyMultiplier)
        try container.encode(
            lowConfidenceConsumedPercentagePoints,
            forKey: .lowConfidenceConsumedPercentagePoints
        )
        try container.encode(
            normalConfidenceConsumedPercentagePoints,
            forKey: .normalConfidenceConsumedPercentagePoints
        )
        try container.encode(
            highConfidenceConsumedPercentagePoints,
            forKey: .highConfidenceConsumedPercentagePoints
        )
    }
}
