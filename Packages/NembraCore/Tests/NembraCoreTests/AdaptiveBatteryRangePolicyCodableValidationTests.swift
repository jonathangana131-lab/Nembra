import Foundation
import Testing
@testable import NembraCore

@Suite("Adaptive battery range policy Codable validation")
struct AdaptiveBatteryRangePolicyCodableValidationTests {
    @Test("valid policy still round-trips through Codable")
    func validPolicyRoundTrips() throws {
        let original = try policy()
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(
            AdaptiveBatteryRangePolicy.self,
            from: encoded
        )

        #expect(decoded == original)
    }

    @Test("decoded policy cannot bypass positive recent-window capacity")
    func negativeRecentWindowCapacityIsRejected() throws {
        let encoded = try corruptedPolicyData {
            $0["recentWindowCapacity"] = -1
        }

        #expect(throws: BatteryRangeValidationError.invalidPolicy) {
            _ = try JSONDecoder().decode(
                AdaptiveBatteryRangePolicy.self,
                from: encoded
            )
        }
    }

    @Test("decoded policy cannot bypass bounded recent weight")
    func outOfRangeRecentWeightIsRejected() throws {
        let encoded = try corruptedPolicyData {
            $0["recentWeight"] = 1.5
        }

        #expect(throws: BatteryRangeValidationError.invalidPolicy) {
            _ = try JSONDecoder().decode(
                AdaptiveBatteryRangePolicy.self,
                from: encoded
            )
        }
    }

    @Test("decoded policy cannot bypass ordered confidence thresholds")
    func unorderedConfidenceThresholdsAreRejected() throws {
        let encoded = try corruptedPolicyData {
            $0["normalConfidenceConsumedPercentagePoints"] = 5.0
        }

        #expect(throws: BatteryRangeValidationError.invalidPolicy) {
            _ = try JSONDecoder().decode(
                AdaptiveBatteryRangePolicy.self,
                from: encoded
            )
        }
    }

    private func corruptedPolicyData(
        _ mutate: (inout [String: Any]) -> Void
    ) throws -> Data {
        let encoded = try JSONEncoder().encode(policy())
        var object = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        mutate(&object)
        return try JSONSerialization.data(withJSONObject: object)
    }

    private func policy() throws -> AdaptiveBatteryRangePolicy {
        try AdaptiveBatteryRangePolicy(
            minimumConsumedPercentagePoints: 3,
            minimumDistanceMeters: 300,
            recentWindowCapacity: 4,
            recentWeight: 0.5,
            outlierLowerEfficiencyRatio: 0.4,
            outlierUpperEfficiencyRatio: 2.5,
            estimateDeadbandFraction: 0.05,
            estimateSmoothingFactor: 0.25,
            provisionalEfficiencyMetersPerPercentagePoint: nil,
            lowSOCCautionThresholdPercent: nil,
            lowSOCEfficiencyMultiplier: nil,
            lowConfidenceConsumedPercentagePoints: 10,
            normalConfidenceConsumedPercentagePoints: 30,
            highConfidenceConsumedPercentagePoints: 60
        )
    }
}
