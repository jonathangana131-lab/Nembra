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

/// Range estimates are derived presentation/domain output rather than telemetry,
/// but they are Codable. Decoding must therefore reject impossible values instead
/// of allowing malformed storage/imports to create believable-looking range.
extension AdaptiveBatteryRangeEstimate {
    private enum CodableValidationKeys: String, CodingKey {
        case rawRemainingMeters
        case presentedRemainingMeters
        case metersPerPercentagePoint
        case basis
        case confidence
        case socProvenance
        case lowSOCConservatismApplied
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodableValidationKeys.self)
        let rawRemainingMeters = try container.decode(Double.self, forKey: .rawRemainingMeters)
        let presentedRemainingMeters = try container.decode(Double.self, forKey: .presentedRemainingMeters)
        let metersPerPercentagePoint = try container.decode(Double.self, forKey: .metersPerPercentagePoint)
        let basis = try container.decode(AdaptiveRangeEstimateBasis.self, forKey: .basis)
        let confidence = try container.decode(AdaptiveRangeConfidence.self, forKey: .confidence)
        let socProvenance = try container.decode(BatterySOCProvenance.self, forKey: .socProvenance)
        let lowSOCConservatismApplied = try container.decode(Bool.self, forKey: .lowSOCConservatismApplied)

        let fullChargeRange = metersPerPercentagePoint * 100
        let tolerance = max(1, abs(fullChargeRange)) * 1e-12
        guard rawRemainingMeters.isFinite,
              rawRemainingMeters >= 0,
              presentedRemainingMeters.isFinite,
              presentedRemainingMeters >= 0,
              metersPerPercentagePoint.isFinite,
              metersPerPercentagePoint > 0,
              fullChargeRange.isFinite,
              rawRemainingMeters <= fullChargeRange + tolerance,
              basis != .provisionalSeed || confidence == .learning else {
            throw DecodingError.dataCorruptedError(
                forKey: .rawRemainingMeters,
                in: container,
                debugDescription: "Decoded adaptive battery-range estimate violates derived-range invariants."
            )
        }

        self.init(
            rawRemainingMeters: rawRemainingMeters,
            presentedRemainingMeters: presentedRemainingMeters,
            metersPerPercentagePoint: metersPerPercentagePoint,
            basis: basis,
            confidence: confidence,
            socProvenance: socProvenance,
            lowSOCConservatismApplied: lowSOCConservatismApplied
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodableValidationKeys.self)
        try container.encode(rawRemainingMeters, forKey: .rawRemainingMeters)
        try container.encode(presentedRemainingMeters, forKey: .presentedRemainingMeters)
        try container.encode(metersPerPercentagePoint, forKey: .metersPerPercentagePoint)
        try container.encode(basis, forKey: .basis)
        try container.encode(confidence, forKey: .confidence)
        try container.encode(socProvenance, forKey: .socProvenance)
        try container.encode(lowSOCConservatismApplied, forKey: .lowSOCConservatismApplied)
    }
}
