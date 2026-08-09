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
}
