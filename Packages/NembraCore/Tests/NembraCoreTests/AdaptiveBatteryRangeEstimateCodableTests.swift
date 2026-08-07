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

    private func authoritativeReading(_ percentage: Double, uptime: UInt64) throws -> BatterySOCReading {
        try BatterySOCReading(
            percentage: percentage,
            provenance: .authoritativeMeasurement,
            receivedAtUptimeNanoseconds: uptime
        )
    }

    private func estimatedReading(_ percentage: Double, uptime: UInt64) throws -> BatterySOCReading {
        try BatterySOCReading(
            percentage: percentage,
            provenance: .estimate,
            receivedAtUptimeNanoseconds: uptime
        )
    }

    private func learnedModel() throws -> AdaptiveBatteryRangeModel {
        var model = AdaptiveBatteryRangeModel()
        let window = try BatteryRangeLearningWindow(
            distanceMeters: 2_000,
            distanceCoverage: .complete,
            transportGapOccurred: false,
            startSOC: authoritativeReading(80, uptime: 1),
            endSOC: authoritativeReading(60, uptime: 2)
        )
        let result = model.ingest(window, policy: try policy())
        #expect(result.disposition == .accepted)
        return model
    }

    private func learnedEstimatedOutput() throws -> AdaptiveBatteryRangeEstimate {
        let model = try learnedModel()
        return try #require(
            model.estimateRemainingRange(
                at: estimatedReading(50, uptime: 3),
                policy: try policy()
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

    @Test("valid non-authoritative learned estimate round-trips")
    func validRoundTrip() throws {
        let estimate = try learnedEstimatedOutput()
        #expect(estimate.socProvenance == .estimate)
        let data = try JSONEncoder().encode(estimate)
        let decoded = try JSONDecoder().decode(AdaptiveBatteryRangeEstimate.self, from: data)
        #expect(decoded == estimate)
    }

    @Test("authoritative derived estimate cannot serialize without its live receipt binding")
    func authoritativeEstimateEncodeRejected() throws {
        let model = try learnedModel()
        let estimate = try #require(
            model.estimateRemainingRange(
                at: authoritativeReading(50, uptime: 3),
                policy: try policy()
            )
        )
        #expect(estimate.socProvenance == .authoritativeMeasurement)

        #expect(throws: EncodingError.self) {
            _ = try JSONEncoder().encode(estimate)
        }
    }

    @Test("generic estimate import cannot self-assert authoritative SoC provenance")
    func authoritativeEstimateDecodeRejected() throws {
        var object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(try learnedEstimatedOutput()))
                as? [String: Any]
        )
        object["socProvenance"] = BatterySOCProvenance.authoritativeMeasurement.rawValue
        let data = try JSONSerialization.data(withJSONObject: object)

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(AdaptiveBatteryRangeEstimate.self, from: data)
        }
    }

    @Test("negative decoded range fails closed")
    func negativeRangeRejected() throws {
        let data = try mutatedJSON(for: learnedEstimatedOutput()) { object in
            object["rawRemainingMeters"] = -1.0
        }

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(AdaptiveBatteryRangeEstimate.self, from: data)
        }
    }

    @Test("raw range cannot exceed selected full-charge efficiency")
    func impossibleFullChargeRangeRejected() throws {
        let estimate = try learnedEstimatedOutput()
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
                at: estimatedReading(50, uptime: 1),
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
