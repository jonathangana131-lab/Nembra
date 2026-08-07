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
        try assembler.recordDistance(deltaMeters: 200, coverage: .complete)

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
        try assembler.recordDistance(deltaMeters: 200, coverage: .complete)

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

    @Test("tightening the live distance threshold retains the span until new distance satisfies it")
    func tightenedDistancePolicyRetainsSpan() throws {
        var assembler = BatteryRangeLearningWindowAssembler()
        let loose = try policy(
            minimumConsumedPercentagePoints: 3,
            minimumDistanceMeters: 100
        )
        let strict = try policy(
            minimumConsumedPercentagePoints: 3,
            minimumDistanceMeters: 300
        )

        _ = try assembler.ingestSOC(reading(80, uptime: 1), policy: loose)
        try assembler.recordDistance(deltaMeters: 200, coverage: .complete)

        #expect(try assembler.ingestSOC(reading(77, uptime: 2), policy: strict) == nil)
        #expect(assembler.anchorSOC?.percentage == 80)
        #expect(assembler.latestAuthoritativeSOC?.percentage == 77)
        #expect(assembler.accumulatedDistanceMeters == 200)

        try assembler.recordDistance(deltaMeters: 100, coverage: .complete)
        let assembled = try assembler.ingestSOC(reading(77, uptime: 3), policy: strict)
        let window = try #require(assembled)

        #expect(window.startSOC.percentage == 80)
        #expect(window.endSOC.percentage == 77)
        #expect(window.consumedPercentagePoints == 3)
        #expect(window.distanceMeters == 300)

        var model = AdaptiveBatteryRangeModel()
        #expect(model.ingest(window, policy: strict).disposition == .accepted)
        #expect(model.acceptedWindowCount == 1)
    }

    @Test("stricter model consumption policy cannot roll back an already-closed assembler span")
    func stricterModelConsumptionPolicyDoesNotReplayClosedSpan() throws {
        var assembler = BatteryRangeLearningWindowAssembler()
        var model = AdaptiveBatteryRangeModel()
        let loose = try policy(
            minimumConsumedPercentagePoints: 3,
            minimumDistanceMeters: 100
        )
        let strict = try policy(
            minimumConsumedPercentagePoints: 4,
            minimumDistanceMeters: 100
        )

        _ = try assembler.ingestSOC(reading(80, uptime: 1), policy: loose)
        try assembler.recordDistance(deltaMeters: 200, coverage: .complete)
        let looseCandidate = try assembler.ingestSOC(reading(77, uptime: 2), policy: loose)
        let looseWindow = try #require(looseCandidate)

        #expect(model.ingest(looseWindow, policy: strict).disposition == .rejected(.insufficientSOCConsumption))
        #expect(model.acceptedWindowCount == 0)
        #expect(assembler.anchorSOC?.percentage == 77)
        #expect(assembler.latestAuthoritativeSOC?.percentage == 77)
        #expect(assembler.accumulatedDistanceMeters == 0)

        try assembler.recordDistance(deltaMeters: 200, coverage: .complete)
        let strictCandidate = try assembler.ingestSOC(reading(73, uptime: 3), policy: strict)
        let strictWindow = try #require(strictCandidate)
        #expect(strictWindow.startSOC.percentage == 77)
        #expect(strictWindow.endSOC.percentage == 73)
        #expect(strictWindow.consumedPercentagePoints == 4)
        #expect(strictWindow.distanceMeters == 200)
        #expect(model.ingest(strictWindow, policy: strict).disposition == .accepted)
        #expect(model.acceptedWindowCount == 1)
    }

    @Test("stricter model distance policy cannot roll back an already-closed assembler span")
    func stricterModelDistancePolicyDoesNotReplayClosedSpan() throws {
        var assembler = BatteryRangeLearningWindowAssembler()
        var model = AdaptiveBatteryRangeModel()
        let loose = try policy(
            minimumConsumedPercentagePoints: 3,
            minimumDistanceMeters: 100
        )
        let strict = try policy(
            minimumConsumedPercentagePoints: 3,
            minimumDistanceMeters: 300
        )

        _ = try assembler.ingestSOC(reading(80, uptime: 1), policy: loose)
        try assembler.recordDistance(deltaMeters: 150, coverage: .complete)
        let looseCandidate = try assembler.ingestSOC(reading(77, uptime: 2), policy: loose)
        let looseWindow = try #require(looseCandidate)

        #expect(model.ingest(looseWindow, policy: strict).disposition == .rejected(.insufficientDistance))
        #expect(model.acceptedWindowCount == 0)
        #expect(assembler.anchorSOC?.percentage == 77)
        #expect(assembler.latestAuthoritativeSOC?.percentage == 77)
        #expect(assembler.accumulatedDistanceMeters == 0)

        try assembler.recordDistance(deltaMeters: 300, coverage: .complete)
        let strictCandidate = try assembler.ingestSOC(reading(74, uptime: 3), policy: strict)
        let strictWindow = try #require(strictCandidate)
        #expect(strictWindow.startSOC.percentage == 77)
        #expect(strictWindow.endSOC.percentage == 74)
        #expect(strictWindow.consumedPercentagePoints == 3)
        #expect(strictWindow.distanceMeters == 300)
        #expect(model.ingest(strictWindow, policy: strict).disposition == .accepted)
        #expect(model.acceptedWindowCount == 1)
    }
}
