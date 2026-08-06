import Testing
@testable import NembraCore

@Suite("Adaptive range window policy transitions")
struct AdaptiveBatteryRangeWindowAssemblerPolicyTransitionTests {
    private func reading(_ percentage: Double, uptime: UInt64) throws -> BatterySOCReading {
        try BatterySOCReading(
            percentage: percentage,
            provenance: .authoritativeMeasurement,
            receivedAtUptimeNanoseconds: uptime
        )
    }

    private func policy(
        minimumConsumedPercentagePoints: Double,
        minimumDistanceMeters: Double = 100
    ) throws -> AdaptiveBatteryRangePolicy {
        try AdaptiveBatteryRangePolicy(
            minimumConsumedPercentagePoints: minimumConsumedPercentagePoints,
            minimumDistanceMeters: minimumDistanceMeters,
            recentWindowCapacity: 2,
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

    @Test("loosening the live consumption threshold can close a retained flat-SoC span")
    func loosenedConsumptionPolicyClosesRetainedSpan() throws {
        var assembler = BatteryRangeLearningWindowAssembler()
        let strict = try policy(minimumConsumedPercentagePoints: 4)
        let loose = try policy(minimumConsumedPercentagePoints: 3)

        _ = try assembler.ingestSOC(reading(80, uptime: 1), policy: strict)
        try assembler.recordDistance(deltaMeters: 200)

        #expect(try assembler.ingestSOC(reading(77, uptime: 2), policy: strict) == nil)
        #expect(assembler.anchorSOC?.percentage == 80)
        #expect(assembler.accumulatedDistanceMeters == 200)

        let assembled = try assembler.ingestSOC(reading(77, uptime: 3), policy: loose)
        let window = try #require(assembled)

        #expect(window.startSOC.percentage == 80)
        #expect(window.endSOC.percentage == 77)
        #expect(window.distanceMeters == 200)

        var model = AdaptiveBatteryRangeModel()
        #expect(model.ingest(window, policy: loose).disposition == .accepted)
        #expect(model.acceptedWindowCount == 1)
    }

    @Test("loosening the live distance threshold can close a retained flat-SoC span")
    func loosenedDistancePolicyClosesRetainedSpan() throws {
        var assembler = BatteryRangeLearningWindowAssembler()
        let strict = try policy(
            minimumConsumedPercentagePoints: 3,
            minimumDistanceMeters: 300
        )
        let loose = try policy(
            minimumConsumedPercentagePoints: 3,
            minimumDistanceMeters: 100
        )

        _ = try assembler.ingestSOC(reading(80, uptime: 1), policy: strict)
        try assembler.recordDistance(deltaMeters: 200)

        #expect(try assembler.ingestSOC(reading(77, uptime: 2), policy: strict) == nil)
        #expect(assembler.anchorSOC?.percentage == 80)
        #expect(assembler.latestAuthoritativeSOC?.percentage == 77)
        #expect(assembler.accumulatedDistanceMeters == 200)

        let assembled = try assembler.ingestSOC(reading(77, uptime: 3), policy: loose)
        let window = try #require(assembled)

        #expect(window.startSOC.percentage == 80)
        #expect(window.endSOC.percentage == 77)
        #expect(window.consumedPercentagePoints == 3)
        #expect(window.distanceMeters == 200)

        var model = AdaptiveBatteryRangeModel()
        #expect(model.ingest(window, policy: loose).disposition == .accepted)
        #expect(model.acceptedWindowCount == 1)
    }
}
