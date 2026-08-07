import Foundation
import Testing
@testable import NembraCore

@Suite("Adaptive battery range restore evidence consistency")
struct AdaptiveBatteryRangeRestoreEvidenceConsistencyTests {
    private func policy() throws -> AdaptiveBatteryRangePolicy {
        try AdaptiveBatteryRangePolicy(
            minimumConsumedPercentagePoints: 5,
            minimumDistanceMeters: 100,
            recentWindowCapacity: 2,
            recentWeight: 0.5,
            outlierLowerEfficiencyRatio: 0.4,
            outlierUpperEfficiencyRatio: 2.5,
            estimateDeadbandFraction: 0.05,
            estimateSmoothingFactor: 0.25,
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

    private func window(
        startPercentage: Double,
        endPercentage: Double,
        startUptime: UInt64,
        endUptime: UInt64,
        distanceMeters: Double = 1_000
    ) throws -> BatteryRangeLearningWindow {
        try BatteryRangeLearningWindow(
            distanceMeters: distanceMeters,
            distanceCoverage: .complete,
            transportGapOccurred: false,
            startSOC: reading(startPercentage, uptime: startUptime),
            endSOC: reading(endPercentage, uptime: endUptime)
        )
    }

    private func singleWindowModelJSON() throws -> [String: Any] {
        var model = AdaptiveBatteryRangeModel()
        let result = model.ingest(
            try window(startPercentage: 100, endPercentage: 90, startUptime: 1, endUptime: 2),
            policy: try policy()
        )
        #expect(result.disposition == .accepted)
        return try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(model)) as? [String: Any]
        )
    }

    @Test("valid multi-window evidence still round-trips with aggregate validation")
    func validMultiWindowEvidenceRoundTrip() throws {
        var model = AdaptiveBatteryRangeModel()
        let p = try policy()

        let first = model.ingest(
            try window(startPercentage: 100, endPercentage: 90, startUptime: 1, endUptime: 2),
            policy: p
        )
        let second = model.ingest(
            try window(startPercentage: 90, endPercentage: 80, startUptime: 3, endUptime: 4),
            policy: p
        )
        #expect(first.disposition == .accepted)
        #expect(second.disposition == .accepted)
        #expect(model.historicalConsumedPercentagePoints == 20)
        #expect(model.recentSamples.count == 2)

        let data = try JSONEncoder().encode(model)
        let decoded = try JSONDecoder().decode(AdaptiveBatteryRangeModel.self, from: data)
        #expect(decoded == model)
    }

    @Test("restore rejects historical consumption impossible for accepted window count")
    func historicalConsumptionCannotExceedHundredPerWindow() throws {
        var object = try singleWindowModelJSON()
        object["historicalConsumedPercentagePoints"] = 101.0
        let data = try JSONSerialization.data(withJSONObject: object)

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(AdaptiveBatteryRangeModel.self, from: data)
        }
    }

    @Test("live-produced one-window 100-point upper bound round-trips")
    func oneWindowHundredPointUpperBoundIsValid() throws {
        var model = AdaptiveBatteryRangeModel()
        let result = model.ingest(
            try window(
                startPercentage: 100,
                endPercentage: 0,
                startUptime: 1,
                endUptime: 2,
                distanceMeters: 1_000
            ),
            policy: try policy()
        )

        #expect(result.disposition == .accepted)
        #expect(model.historicalConsumedPercentagePoints == 100)
        #expect(model.acceptedWindowCount == 1)
        #expect(model.recentSamples.first?.consumedPercentagePoints == 100)

        let decoded = try JSONDecoder().decode(
            AdaptiveBatteryRangeModel.self,
            from: JSONEncoder().encode(model)
        )
        #expect(decoded == model)
    }
}
