import Foundation

public enum AdaptiveBatteryRangePersistedStateError: Error, Equatable, Sendable {
    case unsupportedSchemaVersion(Int)
    case invalidHistoricalState
    case invalidAcceptedWindowCount
    case invalidRecentSample(Int)
    case recentEvidenceExceedsHistory
}

/// Versioned persistence envelope for adaptive range learning.
///
/// `AdaptiveBatteryRangeModel` is intentionally `Codable` so its learned state can
/// survive app launches, but synthesized decoding alone cannot protect its runtime
/// invariants from a truncated, manually edited, or otherwise corrupted payload.
/// This envelope is the fail-closed boundary higher layers should persist/restore.
///
/// It does not reinterpret battery evidence or manufacture missing history. It only
/// verifies that decoded state could have been produced by the public learning path.
public struct AdaptiveBatteryRangePersistedState: Equatable, Codable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let model: AdaptiveBatteryRangeModel

    public init(validating model: AdaptiveBatteryRangeModel) throws {
        try Self.validate(model)
        self.schemaVersion = Self.currentSchemaVersion
        self.model = model
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw AdaptiveBatteryRangePersistedStateError.unsupportedSchemaVersion(schemaVersion)
        }

        let model = try container.decode(AdaptiveBatteryRangeModel.self, forKey: .model)
        try Self.validate(model)

        self.schemaVersion = schemaVersion
        self.model = model
    }

    public func encode(to encoder: Encoder) throws {
        try Self.validate(model)

        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(model, forKey: .model)
    }

    /// Validates invariants visible in the persisted model without inventing
    /// policy-specific assumptions that are not stored in the model itself.
    public static func validate(_ model: AdaptiveBatteryRangeModel) throws {
        let historicalConsumed = model.historicalConsumedPercentagePoints
        let acceptedWindowCount = model.acceptedWindowCount
        let recentSamples = model.recentSamples

        guard historicalConsumed.isFinite, historicalConsumed >= 0 else {
            throw AdaptiveBatteryRangePersistedStateError.invalidHistoricalState
        }
        guard acceptedWindowCount >= 0,
              recentSamples.count <= acceptedWindowCount else {
            throw AdaptiveBatteryRangePersistedStateError.invalidAcceptedWindowCount
        }

        if let historicalEfficiency = model.historicalEfficiencyMetersPerPercentagePoint {
            guard historicalEfficiency.isFinite,
                  historicalEfficiency > 0,
                  historicalConsumed > 0,
                  acceptedWindowCount > 0,
                  recentSamples.isEmpty == false else {
                throw AdaptiveBatteryRangePersistedStateError.invalidHistoricalState
            }

            // Every accepted learning window consumes at most 100 percentage
            // points because both authoritative SoC anchors are normalized 0...100.
            let maximumPossibleConsumed = Double(acceptedWindowCount) * 100
            guard historicalConsumed <= maximumPossibleConsumed else {
                throw AdaptiveBatteryRangePersistedStateError.invalidHistoricalState
            }
        } else {
            // The public ingest path creates history, recent evidence, and the
            // accepted count atomically. A no-history model must therefore be the
            // pristine state rather than a partially populated persistence state.
            guard historicalConsumed == 0,
                  acceptedWindowCount == 0,
                  recentSamples.isEmpty else {
                throw AdaptiveBatteryRangePersistedStateError.invalidHistoricalState
            }
        }

        var recentConsumed = 0.0
        for (index, sample) in recentSamples.enumerated() {
            guard sample.distanceMeters.isFinite,
                  sample.distanceMeters > 0,
                  sample.consumedPercentagePoints.isFinite,
                  sample.consumedPercentagePoints > 0,
                  sample.consumedPercentagePoints <= 100,
                  sample.metersPerPercentagePoint.isFinite,
                  sample.metersPerPercentagePoint > 0 else {
                throw AdaptiveBatteryRangePersistedStateError.invalidRecentSample(index)
            }

            let expectedEfficiency = sample.distanceMeters / sample.consumedPercentagePoints
            let comparisonScale = max(
                1,
                max(abs(expectedEfficiency), abs(sample.metersPerPercentagePoint))
            )
            guard abs(expectedEfficiency - sample.metersPerPercentagePoint) <= comparisonScale * 1e-12 else {
                throw AdaptiveBatteryRangePersistedStateError.invalidRecentSample(index)
            }

            recentConsumed += sample.consumedPercentagePoints
        }

        // `recentSamples` is a retained subset of accepted history, so it can
        // never represent more consumed battery than the historical accumulator.
        let tolerance = max(1, abs(historicalConsumed)) * 1e-12
        guard recentConsumed <= historicalConsumed + tolerance else {
            throw AdaptiveBatteryRangePersistedStateError.recentEvidenceExceedsHistory
        }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case model
    }
}
