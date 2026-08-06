import Foundation

public enum AdaptiveBatteryRangePersistedStateError: Error, Equatable, Sendable {
    case unsupportedSchemaVersion(Int)
    case invalidHistoricalBounds
    case recentEvidenceExceedsHistory
    case completeRecentEvidenceDisagreesWithHistory
}

/// Versioned persistence envelope for learned adaptive battery/range state.
///
/// `AdaptiveBatteryRangeModel` already validates its own decoded scalar/sample
/// invariants. This envelope adds persistence-level protections that are not
/// model-policy concerns:
///
/// - explicit schema versioning for future migrations;
/// - cumulative cross-field bounds that must remain true for any state produced
///   by the public ingest path;
/// - exact cross-checks when the retained recent window set still contains every
///   accepted sample and therefore fully reconstructs historical evidence.
///
/// Higher layers should persist/restore this envelope rather than treating any
/// shape-compatible JSON payload as authoritative learned scooter history.
public struct AdaptiveBatteryRangePersistedState: Equatable, Codable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let model: AdaptiveBatteryRangeModel

    public init(validating model: AdaptiveBatteryRangeModel) throws {
        try Self.validatePersistenceInvariants(model)
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
        try Self.validatePersistenceInvariants(model)

        self.schemaVersion = schemaVersion
        self.model = model
    }

    public func encode(to encoder: Encoder) throws {
        try Self.validatePersistenceInvariants(model)

        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(model, forKey: .model)
    }

    /// Checks invariants that can be proven without storing or inventing a
    /// vehicle-specific policy.
    public static func validatePersistenceInvariants(
        _ model: AdaptiveBatteryRangeModel
    ) throws {
        let historicalConsumed = model.historicalConsumedPercentagePoints
        let acceptedWindowCount = model.acceptedWindowCount

        guard historicalConsumed.isFinite,
              historicalConsumed >= 0,
              acceptedWindowCount >= 0,
              // `ingest` increments this counter for every accepted window. A
              // restored Int.max value would therefore make the next legitimate
              // accepted window trap on integer overflow instead of failing closed.
              acceptedWindowCount < Int.max,
              model.recentSamples.count <= acceptedWindowCount else {
            throw AdaptiveBatteryRangePersistedStateError.invalidHistoricalBounds
        }

        if model.hasLearnedEfficiency {
            guard historicalConsumed > 0, acceptedWindowCount > 0 else {
                throw AdaptiveBatteryRangePersistedStateError.invalidHistoricalBounds
            }

            // Each accepted learning window consumes at most 100 percentage
            // points because both normalized SoC anchors are constrained 0...100.
            // This catches shape-valid but impossible cumulative persistence state.
            let maximumPossibleConsumed = Double(acceptedWindowCount) * 100
            guard maximumPossibleConsumed.isFinite,
                  historicalConsumed <= maximumPossibleConsumed else {
                throw AdaptiveBatteryRangePersistedStateError.invalidHistoricalBounds
            }
        } else {
            guard historicalConsumed == 0,
                  acceptedWindowCount == 0,
                  model.recentSamples.isEmpty else {
                throw AdaptiveBatteryRangePersistedStateError.invalidHistoricalBounds
            }
        }

        var recentConsumed = 0.0
        var reconstructedRecentEfficiency = 0.0
        for sample in model.recentSamples {
            let newRecentConsumed = recentConsumed + sample.consumedPercentagePoints
            guard newRecentConsumed.isFinite, newRecentConsumed > 0 else {
                throw AdaptiveBatteryRangePersistedStateError.recentEvidenceExceedsHistory
            }

            // Reconstruct with the same online weighted-mean form used by the
            // model so a fully retained sample set can be compared without
            // overflow-prone weighted-distance multiplication.
            let weight = sample.consumedPercentagePoints / newRecentConsumed
            let candidate = reconstructedRecentEfficiency
                + (sample.metersPerPercentagePoint - reconstructedRecentEfficiency) * weight
            guard candidate.isFinite, candidate > 0 else {
                throw AdaptiveBatteryRangePersistedStateError.completeRecentEvidenceDisagreesWithHistory
            }

            recentConsumed = newRecentConsumed
            reconstructedRecentEfficiency = candidate
        }

        // Recent samples are a retained subset of accepted history. They may be
        // truncated by recentWindowCapacity, but can never represent *more*
        // battery consumption than the cumulative historical accumulator.
        let consumedTolerance = max(1, abs(historicalConsumed)) * 1e-12
        guard recentConsumed <= historicalConsumed + consumedTolerance else {
            throw AdaptiveBatteryRangePersistedStateError.recentEvidenceExceedsHistory
        }

        // If every accepted window is still retained, no historical evidence is
        // missing. The retained samples must therefore reconstruct both the
        // cumulative consumption and historical weighted efficiency. If any
        // sample had previously been truncated, recentSamples.count stays below
        // acceptedWindowCount and this stronger proof is intentionally skipped.
        if acceptedWindowCount > 0, model.recentSamples.count == acceptedWindowCount {
            guard abs(recentConsumed - historicalConsumed) <= consumedTolerance,
                  let historicalEfficiency = model.historicalEfficiencyMetersPerPercentagePoint else {
                throw AdaptiveBatteryRangePersistedStateError.completeRecentEvidenceDisagreesWithHistory
            }

            let efficiencyTolerance = max(
                1,
                max(abs(reconstructedRecentEfficiency), abs(historicalEfficiency))
            ) * 1e-12
            guard abs(reconstructedRecentEfficiency - historicalEfficiency) <= efficiencyTolerance else {
                throw AdaptiveBatteryRangePersistedStateError.completeRecentEvidenceDisagreesWithHistory
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case model
    }
}
