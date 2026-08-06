import Foundation
import Testing
@testable import NembraCore

@Suite("Adaptive battery range estimate Codable validation")
struct AdaptiveBatteryRangeEstimateCodableTests {
    private func policy(
        provisionalEfficiencyMetersPerPercentagePoint: Double? = nil
    ) throws -> AdaptiveBatteryRangePolicy {
        try AdaptiveBatteryRangePolicy(
            minimumConsumedPercentagePoints: 5,
            minimumDistanceMeters: 100,
            recentWindowCapacity: 2,
            recentWeight: 0.5,
            outlierLowerEfficiencyRatio: 0.4,
            outlierUpperEfficiencyRatio: 2.5,
            estimateDeadbandFraction: 0.05,
            estimateSmoothingFactor: 0.25,
            provisionalEfficiencyMetersPerPercentagePoint: provisionalEfficiencyMetersPerPercentagePoint,
            lowConfidenceConsumedPercentagePoints: 10,
            normalConfidenceConsumedPercentagePoints: 30,
            highConfidenceConsumedPercentagePoints: 60
        )
    }

    private func reading(_ percentage: Double, uptime: UInt64) throws -> BatterySOCReading {
        try BatterySOCReading(
            percentage: percentage,
            provenance: .authoritativeMeasurement,
            receivedAtUptimeNanoseconds: uptime
        )
    }

    private func learnedEstimate() throws -> AdaptiveBatteryRangeEstimate {
        var model = AdaptiveBatteryRangeModel()
        let window = try BatteryRangeLearningWindow(
            distanceMeters: 2_000,
            distanceCoverage: .complete,
            transportGapOccurred: false,
            startSOC: reading(80, uptime: 1),
            endSOC: reading(60, uptime: 2)
        )
        let p = try policy()
        let result = model.ingest(window, policy: p)
        #expect(result.disposition == .accepted)
        return try #require(
            model.estimateRemainingRange(
                at: reading(50, uptime: 3),
                policy: p
            )
        )
    }

    private func mutatedJSON(
        for estimate: AdaptiveBatteryRangeEstimate,
        mutate: (inout [String: Any]) -> Void
    ) throws -> Data {
        let data = try JSONEncoder().encode(estimate)
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        mutate(&object)
        return try JSONSerialization.data(withJSONObject: object)
    }

    @Test("valid learned estimate round-trips")
    func validRoundTrip() throws {
        let estimate = try learnedEstimate()
        let data = try JSONEncoder().encode(estimate)
        let decoded = try JSONDecoder().decode(AdaptiveBatteryRangeEstimate.self, from: data)
        #expect(decoded == estimate)
    }

    @Test("negative decoded range fails closed")
    func negativeRangeRejected() throws {
        let data = try mutatedJSON(for: learnedEstimate()) { object in
            object["rawRemainingMeters"] = -1.0
        }

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(AdaptiveBatteryRangeEstimate.self, from: data)
        }
    }

    @Test("raw range cannot exceed selected full-charge efficiency")
    func impossibleFullChargeRangeRejected() throws {
        let estimate = try learnedEstimate()
        let data = try mutatedJSON(for: estimate) { object in
            object["rawRemainingMeters"] = estimate.metersPerPercentagePoint * 101
        }

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(AdaptiveBatteryRangeEstimate.self, from: data)
        }
    }

    @Test("provisional estimate cannot claim learned confidence")
    func provisionalConfidenceRejected() throws {
        let model = AdaptiveBatteryRangeModel()
        let p = try policy(provisionalEfficiencyMetersPerPercentagePoint: 80)
        let estimate = try #require(
            model.estimateRemainingRange(
                at: reading(50, uptime: 1),
                policy: p
            )
        )
        #expect(estimate.basis == .provisionalSeed)
        #expect(estimate.confidence == .learning)

        let data = try mutatedJSON(for: estimate) { object in
            object["confidence"] = AdaptiveRangeConfidence.high.rawValue
        }

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(AdaptiveBatteryRangeEstimate.self, from: data)
        }
    }
}
