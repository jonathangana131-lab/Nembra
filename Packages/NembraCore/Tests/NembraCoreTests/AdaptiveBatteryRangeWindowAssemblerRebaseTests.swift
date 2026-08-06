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

        let assembled = try assembler.ingestSOC(reading(79, uptime: 3), policy: p)
        let clean = try #require(assembled)

        #expect(clean.startSOC.percentage == 82)
        #expect(clean.endSOC.percentage == 79)
        #expect(clean.distanceMeters == 300)
        #expect(clean.distanceCoverage == .complete)
        #expect(clean.transportGapOccurred == false)
    }

    @Test("same-timestamp measured rebound fails before it can rebase")
    func sameTimestampReboundFailsAtomically() throws {
        var assembler = BatteryRangeLearningWindowAssembler()
        let p = try policy()

        _ = try assembler.ingestSOC(reading(80, uptime: 10), policy: p)
        try assembler.recordDistance(deltaMeters: 50, coverage: .partial)
        #expect(try assembler.ingestSOC(reading(77, uptime: 20), policy: p) == nil)
        assembler.recordTransportGap()
        let before = assembler

        #expect(throws: BatteryRangeWindowAssemblyError.nonMonotonicAuthoritativeSOC) {
            _ = try assembler.ingestSOC(reading(79, uptime: 20), policy: p)
        }

        #expect(assembler == before)
        #expect(assembler.anchorSOC?.percentage == 80)
        #expect(assembler.latestAuthoritativeSOC?.percentage == 77)
        #expect(assembler.accumulatedDistanceMeters == 50)
        #expect(assembler.distanceCoverage == .partial)
        #expect(assembler.transportGapOccurred)
    }

    @Test("partial coverage cannot be repaired by later complete deltas in one span")
    func partialCoverageIsSticky() throws {
        var assembler = BatteryRangeLearningWindowAssembler()
        let p = try policy()

        _ = try assembler.ingestSOC(reading(80, uptime: 1), policy: p)
        try assembler.recordDistance(deltaMeters: 50, coverage: .partial)
        try assembler.recordDistance(deltaMeters: 100, coverage: .complete)

        let assembled = try assembler.ingestSOC(reading(77, uptime: 2), policy: p)
        let window = try #require(assembled)

        #expect(window.distanceMeters == 150)
        #expect(window.distanceCoverage == .partial)
    }

    @Test("a rejected gap window closes its span so later clean evidence can train")
    func rejectedGapWindowDoesNotPoisonNextSpan() throws {
        var assembler = BatteryRangeLearningWindowAssembler()
        var model = AdaptiveBatteryRangeModel()
        let p = try policy()

        _ = try assembler.ingestSOC(reading(80, uptime: 1), policy: p)
        try assembler.recordDistance(deltaMeters: 150)
        assembler.recordTransportGap()

        let taintedCandidate = try assembler.ingestSOC(reading(77, uptime: 2), policy: p)
        let tainted = try #require(taintedCandidate)
        #expect(model.ingest(tainted, policy: p).disposition == .rejected(.transportGap))
        #expect(assembler.anchorSOC?.percentage == 77)
        #expect(assembler.transportGapOccurred == false)
        #expect(assembler.distanceCoverage == .complete)

        try assembler.recordDistance(deltaMeters: 150)
        let cleanCandidate = try assembler.ingestSOC(reading(74, uptime: 3), policy: p)
        let clean = try #require(cleanCandidate)

        #expect(clean.startSOC.percentage == 77)
        #expect(clean.endSOC.percentage == 74)
        #expect(clean.transportGapOccurred == false)
        #expect(clean.distanceCoverage == .complete)
        #expect(model.ingest(clean, policy: p).disposition == .accepted)
        #expect(model.acceptedWindowCount == 1)
    }

    @Test("known post-gap anchor discards pre-gap evidence before clean learning resumes")
    func explicitContinuityResetStartsCleanSpan() throws {
        var assembler = BatteryRangeLearningWindowAssembler()
        var model = AdaptiveBatteryRangeModel()
        let p = try policy()

        _ = try assembler.ingestSOC(reading(80, uptime: 1), policy: p)
        try assembler.recordDistance(deltaMeters: 500, coverage: .partial)
        assembler.recordTransportGap()

        // A higher integration layer has identified the first trustworthy
        // post-gap authoritative reading. Continuity cannot be proven, so the
        // pre-gap candidate is intentionally abandoned rather than bridged.
        assembler.reset()
        _ = try assembler.ingestSOC(reading(75, uptime: 10), policy: p)
        try assembler.recordDistance(deltaMeters: 180, coverage: .complete)

        let candidate = try assembler.ingestSOC(reading(72, uptime: 11), policy: p)
        let clean = try #require(candidate)

        #expect(clean.startSOC.percentage == 75)
        #expect(clean.endSOC.percentage == 72)
        #expect(clean.distanceMeters == 180)
        #expect(clean.distanceCoverage == .complete)
        #expect(clean.transportGapOccurred == false)
        #expect(model.ingest(clean, policy: p).disposition == .accepted)
        #expect(model.acceptedWindowCount == 1)
    }
}
