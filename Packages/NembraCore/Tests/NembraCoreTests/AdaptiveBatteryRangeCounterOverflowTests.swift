import Foundation
import Testing
@testable import NembraCore

@Suite("Adaptive battery range counter exhaustion")
struct AdaptiveBatteryRangeCounterOverflowTests {
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
        endUptime: UInt64
    ) throws -> BatteryRangeLearningWindow {
        try BatteryRangeLearningWindow(
            distanceMeters: 1_000,
            distanceCoverage: .complete,
            transportGapOccurred: false,
            startSOC: reading(startPercentage, uptime: startUptime),
            endSOC: reading(endPercentage, uptime: endUptime)
        )
    }

    private func seededModelData(acceptedWindowCount: Int) throws -> Data {
        var model = AdaptiveBatteryRangeModel()
        let result = model.ingest(
            try window(
                startPercentage: 100,
                endPercentage: 90,
                startUptime: 1,
                endUptime: 2
            ),
            policy: try policy()
        )
        #expect(result.disposition == .accepted)

        let encoded = try JSONEncoder().encode(model)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["acceptedWindowCount"] = acceptedWindowCount
        return try JSONSerialization.data(withJSONObject: object)
    }

    @Test("raw model restore rejects an exhausted accepted-window counter")
    func exhaustedCounterRestoreRejected() throws {
        let data = try seededModelData(acceptedWindowCount: Int.max)

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(AdaptiveBatteryRangeModel.self, from: data)
        }
    }

    @Test("raw model restore rejects recent evidence larger than historical evidence")
    func inconsistentRecentEvidenceRestoreRejected() throws {
        let seeded = try seededModelData(acceptedWindowCount: 1)
        var object = try #require(JSONSerialization.jsonObject(with: seeded) as? [String: Any])
        object["historicalConsumedPercentagePoints"] = 5.0
        let data = try JSONSerialization.data(withJSONObject: object)

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(AdaptiveBatteryRangeModel.self, from: data)
        }
    }

    @Test("live model at terminal count rejects another ingest without mutation")
    func terminalCounterIngestFailsClosed() throws {
        let data = try seededModelData(acceptedWindowCount: Int.max - 1)
        var model = try JSONDecoder().decode(AdaptiveBatteryRangeModel.self, from: data)
        let p = try policy()

        let terminalResult = model.ingest(
            try window(
                startPercentage: 90,
                endPercentage: 80,
                startUptime: 3,
                endUptime: 4
            ),
            policy: p
        )
        #expect(terminalResult.disposition == .accepted)
        #expect(model.acceptedWindowCount == Int.max)

        let terminalState = model
        let rejected = model.ingest(
            try window(
                startPercentage: 80,
                endPercentage: 70,
                startUptime: 5,
                endUptime: 6
            ),
            policy: p
        )

        #expect(rejected.disposition == .rejected(.numericalOverflow))
        #expect(model == terminalState)
    }
}
