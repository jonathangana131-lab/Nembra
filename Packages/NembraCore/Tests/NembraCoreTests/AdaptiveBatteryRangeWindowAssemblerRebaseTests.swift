import Testing
@testable import NembraCore

@Suite("Adaptive range window rebasing")
struct AdaptiveBatteryRangeWindowAssemblerRebaseTests {
    private func reading(_ percentage: Double, uptime: UInt64) throws -> BatterySOCReading {
        try BatterySOCReading(
            percentage: percentage,
            provenance: .authoritativeMeasurement,
            receivedAtUptimeNanoseconds: uptime
        )
    }

    private func policy() throws -> AdaptiveBatteryRangePolicy {
        try AdaptiveBatteryRangePolicy(
            minimumConsumedPercentagePoints: 3,
            minimumDistanceMeters: 100,
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

    @Test("a higher measured anchor discards old distance before the next clean window")
    func higherAnchorStartsCleanSpan() throws {
        var assembler = BatteryRangeLearningWindowAssembler()
        let p = try policy()

        _ = try assembler.ingestSOC(reading(80, uptime: 1), policy: p)
        try assembler.recordDistance(deltaMeters: 500, coverage: .partial)
        assembler.recordTransportGap()

        _ = try assembler.ingestSOC(reading(82, uptime: 2), policy: p)
        try assembler.recordDistance(deltaMeters: 300, coverage: .complete)

        let clean = try #require(
            assembler.ingestSOC(reading(79, uptime: 3), policy: p)
        )

        #expect(clean.startSOC.percentage == 82)
        #expect(clean.endSOC.percentage == 79)
        #expect(clean.distanceMeters == 300)
        #expect(clean.distanceCoverage == .complete)
        #expect(clean.transportGapOccurred == false)
    }

    @Test("partial coverage cannot be repaired by later complete deltas in one span")
    func partialCoverageIsSticky() throws {
        var assembler = BatteryRangeLearningWindowAssembler()
        let p = try policy()

        _ = try assembler.ingestSOC(reading(80, uptime: 1), policy: p)
        try assembler.recordDistance(deltaMeters: 50, coverage: .partial)
        try assembler.recordDistance(deltaMeters: 100, coverage: .complete)

        let window = try #require(
            assembler.ingestSOC(reading(77, uptime: 2), policy: p)
        )

        #expect(window.distanceMeters == 150)
        #expect(window.distanceCoverage == .partial)
    }
}
