import Testing
@testable import NembraCore

@Suite("Adaptive battery range policy changes")
struct AdaptiveBatteryRangePolicyChangeTests {
    private func policy(recentWindowCapacity: Int) throws -> AdaptiveBatteryRangePolicy {
        try AdaptiveBatteryRangePolicy(
            minimumConsumedPercentagePoints: 5,
            minimumDistanceMeters: 1,
            recentWindowCapacity: recentWindowCapacity,
            recentWeight: 1,
            outlierLowerEfficiencyRatio: 0.1,
            outlierUpperEfficiencyRatio: 4,
            estimateDeadbandFraction: 0,
            estimateSmoothingFactor: 1,
            lowConfidenceConsumedPercentagePoints: 10,
            normalConfidenceConsumedPercentagePoints: 20,
            highConfidenceConsumedPercentagePoints: 40
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
        distanceMeters: Double,
        startPercentage: Double,
        endPercentage: Double,
        startUptime: UInt64,
        endUptime: UInt64
    ) throws -> BatteryRangeLearningWindow {
        try BatteryRangeLearningWindow(
            distanceMeters: distanceMeters,
            distanceCoverage: .complete,
            transportGapOccurred: false,
            startSOC: reading(startPercentage, uptime: startUptime),
            endSOC: reading(endPercentage, uptime: endUptime)
        )
    }

    @Test("reducing recent capacity takes effect before another sample arrives")
    func reducedRecentCapacityAppliesImmediately() throws {
        var model = AdaptiveBatteryRangeModel()
        let originalPolicy = try policy(recentWindowCapacity: 3)

        _ = model.ingest(
            try window(
                distanceMeters: 1_000,
                startPercentage: 100,
                endPercentage: 90,
                startUptime: 1,
                endUptime: 2
            ),
            policy: originalPolicy
        )
        _ = model.ingest(
            try window(
                distanceMeters: 2_000,
                startPercentage: 90,
                endPercentage: 80,
                startUptime: 3,
                endUptime: 4
            ),
            policy: originalPolicy
        )
        _ = model.ingest(
            try window(
                distanceMeters: 3_000,
                startPercentage: 80,
                endPercentage: 70,
                startUptime: 5,
                endUptime: 6
            ),
            policy: originalPolicy
        )

        #expect(model.recentSamples.count == 3)
        let originalEfficiency = model.blendedEfficiencyMetersPerPercentagePoint(using: originalPolicy) ?? 0
        #expect(abs(originalEfficiency - 200) < 0.000_001)

        let reducedPolicy = try policy(recentWindowCapacity: 1)
        #expect(model.recentSamples.count == 3)
        let reducedEfficiency = model.blendedEfficiencyMetersPerPercentagePoint(using: reducedPolicy) ?? 0
        #expect(abs(reducedEfficiency - 300) < 0.000_001)
    }
}
