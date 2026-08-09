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

        try assembler.recordDistance(deltaMeters: 50, coverage: .complete)
        let laterCandidate = try assembler.ingestSOC(reading(76, uptime: 21), policy: p)
        let later = try #require(laterCandidate)
        #expect(later.startSOC.percentage == 80)
        #expect(later.endSOC.percentage == 76)
        #expect(later.distanceMeters == 100)
        #expect(later.distanceCoverage == .partial)
        #expect(later.transportGapOccurred)
    }

    @Test("estimated rebound never rebases or advances measured learning state")
    func estimatedReboundIsIgnored() throws {
        var assembler = BatteryRangeLearningWindowAssembler()
        let p = try policy()

        _ = try assembler.ingestSOC(reading(80, uptime: 10), policy: p)
        try assembler.recordDistance(deltaMeters: 150, coverage: .partial)
        assembler.recordTransportGap()

        let estimate = try BatterySOCReading(
            percentage: 99,
            provenance: .estimate,
            receivedAtUptimeNanoseconds: 999
        )
        #expect(try assembler.ingestSOC(estimate, policy: p) == nil)

        #expect(assembler.anchorSOC?.percentage == 80)
        #expect(assembler.latestAuthoritativeSOC?.percentage == 80)
        #expect(assembler.latestAuthoritativeSOC?.receivedAtUptimeNanoseconds == 10)
        #expect(assembler.accumulatedDistanceMeters == 150)
        #expect(assembler.distanceCoverage == .partial)
        #expect(assembler.transportGapOccurred)

        let candidate = try assembler.ingestSOC(reading(77, uptime: 20), policy: p)
        let tainted = try #require(candidate)
        #expect(tainted.startSOC.percentage == 80)
        #expect(tainted.endSOC.percentage == 77)
        #expect(tainted.distanceMeters == 150)
        #expect(tainted.distanceCoverage == .partial)
        #expect(tainted.transportGapOccurred)
    }

    @Test("partial coverage cannot be repaired and rejected evidence does not poison the next span")
    func partialCoverageIsSticky() throws {
        var assembler = BatteryRangeLearningWindowAssembler()
        var model = AdaptiveBatteryRangeModel()
        let p = try policy()

        _ = try assembler.ingestSOC(reading(80, uptime: 1), policy: p)
        try assembler.recordDistance(deltaMeters: 50, coverage: .partial)
        try assembler.recordDistance(deltaMeters: 100, coverage: .complete)

        let assembled = try assembler.ingestSOC(reading(77, uptime: 2), policy: p)
        let window = try #require(assembled)

        #expect(window.distanceMeters == 150)
        #expect(window.distanceCoverage == .partial)
        #expect(model.ingest(window, policy: p).disposition == .rejected(.incompleteDistanceEvidence))
        #expect(model.acceptedWindowCount == 0)
        #expect(assembler.anchorSOC?.percentage == 77)
        #expect(assembler.accumulatedDistanceMeters == 0)
        #expect(assembler.distanceCoverage == .complete)

        try assembler.recordDistance(deltaMeters: 150, coverage: .complete)
        let cleanCandidate = try assembler.ingestSOC(reading(74, uptime: 3), policy: p)
        let clean = try #require(cleanCandidate)
        #expect(clean.startSOC.percentage == 77)
        #expect(clean.endSOC.percentage == 74)
        #expect(clean.distanceCoverage == .complete)
        #expect(model.ingest(clean, policy: p).disposition == .accepted)
        #expect(model.acceptedWindowCount == 1)
    }

    @Test("unknown coverage rejection closes its span so later complete evidence can train")
    func unknownCoverageRejectionDoesNotPoisonNextSpan() throws {
        var assembler = BatteryRangeLearningWindowAssembler()
        var model = AdaptiveBatteryRangeModel()
        let p = try policy()

        _ = try assembler.ingestSOC(reading(80, uptime: 1), policy: p)
        try assembler.recordDistance(deltaMeters: 150, coverage: .complete)
        try assembler.recordDistance(deltaMeters: 0, coverage: .unknown)

        let unknownCandidate = try assembler.ingestSOC(reading(77, uptime: 2), policy: p)
        let unknown = try #require(unknownCandidate)
        #expect(unknown.distanceMeters == 150)
        #expect(unknown.distanceCoverage == .unknown)
        #expect(model.ingest(unknown, policy: p).disposition == .rejected(.incompleteDistanceEvidence))
        #expect(model.acceptedWindowCount == 0)
        #expect(assembler.anchorSOC?.percentage == 77)
        #expect(assembler.accumulatedDistanceMeters == 0)
        #expect(assembler.distanceCoverage == .complete)
        #expect(assembler.transportGapOccurred == false)

        try assembler.recordDistance(deltaMeters: 150, coverage: .complete)
        let cleanCandidate = try assembler.ingestSOC(reading(74, uptime: 3), policy: p)
        let clean = try #require(cleanCandidate)
        #expect(clean.startSOC.percentage == 77)
        #expect(clean.endSOC.percentage == 74)
        #expect(clean.distanceMeters == 150)
        #expect(clean.distanceCoverage == .complete)
        #expect(clean.transportGapOccurred == false)
        #expect(model.ingest(clean, policy: p).disposition == .accepted)
        #expect(model.acceptedWindowCount == 1)
    }

    @Test("a rejected gap window closes its span so later clean evidence can train")
    func rejectedGapWindowDoesNotPoisonNextSpan() throws {
        var assembler = BatteryRangeLearningWindowAssembler()
        var model = AdaptiveBatteryRangeModel()
        let p = try policy()

        _ = try assembler.ingestSOC(reading(80, uptime: 1), policy: p)
        try assembler.recordDistance(deltaMeters: 150, coverage: .complete)
        assembler.recordTransportGap()

        let taintedCandidate = try assembler.ingestSOC(reading(77, uptime: 2), policy: p)
        let tainted = try #require(taintedCandidate)
        #expect(model.ingest(tainted, policy: p).disposition == .rejected(.transportGap))
        #expect(assembler.anchorSOC?.percentage == 77)
        #expect(assembler.transportGapOccurred == false)
        #expect(assembler.distanceCoverage == .complete)

        try assembler.recordDistance(deltaMeters: 150, coverage: .complete)
        let cleanCandidate = try assembler.ingestSOC(reading(74, uptime: 3), policy: p)
        let clean = try #require(cleanCandidate)

        #expect(clean.startSOC.percentage == 77)
        #expect(clean.endSOC.percentage == 74)
        #expect(clean.transportGapOccurred == false)
        #expect(clean.distanceCoverage == .complete)
        #expect(model.ingest(clean, policy: p).disposition == .accepted)
        #expect(model.acceptedWindowCount == 1)
    }

    @Test("a numerical-overflow rejection closes its span so later clean evidence can train")
    func numericalOverflowRejectionDoesNotPoisonNextSpan() throws {
        var assembler = BatteryRangeLearningWindowAssembler()
        var model = AdaptiveBatteryRangeModel()
        let p = try policy()

        _ = try assembler.ingestSOC(reading(80, uptime: 1), policy: p)
        try assembler.recordDistance(deltaMeters: .greatestFiniteMagnitude, coverage: .complete)

        let overflowCandidate = try assembler.ingestSOC(reading(77, uptime: 2), policy: p)
        let overflow = try #require(overflowCandidate)
        #expect(overflow.distanceMeters == .greatestFiniteMagnitude)
        #expect(overflow.distanceCoverage == .complete)
        #expect(model.ingest(overflow, policy: p).disposition == .rejected(.numericalOverflow))
        #expect(model.acceptedWindowCount == 0)
        #expect(assembler.anchorSOC?.percentage == 77)
        #expect(assembler.accumulatedDistanceMeters == 0)
        #expect(assembler.distanceCoverage == .complete)
        #expect(assembler.transportGapOccurred == false)

        try assembler.recordDistance(deltaMeters: 300, coverage: .complete)
        let cleanCandidate = try assembler.ingestSOC(reading(74, uptime: 3), policy: p)
        let clean = try #require(cleanCandidate)
        #expect(clean.startSOC.percentage == 77)
        #expect(clean.endSOC.percentage == 74)
        #expect(clean.distanceMeters == 300)
        #expect(clean.distanceCoverage == .complete)
        #expect(clean.transportGapOccurred == false)
        #expect(model.ingest(clean, policy: p).disposition == .accepted)
        #expect(model.acceptedWindowCount == 1)
    }

    @Test("an efficiency outlier closes its span without poisoning later clean evidence")
    func rejectedEfficiencyOutlierDoesNotPoisonNextSpan() throws {
        var assembler = BatteryRangeLearningWindowAssembler()
        var model = AdaptiveBatteryRangeModel()
        let p = try policy()

        _ = try assembler.ingestSOC(reading(80, uptime: 1), policy: p)
        try assembler.recordDistance(deltaMeters: 300, coverage: .complete)
        let baselineCandidate = try assembler.ingestSOC(reading(77, uptime: 2), policy: p)
        let baseline = try #require(baselineCandidate)
        #expect(model.ingest(baseline, policy: p).disposition == .accepted)
        #expect(model.acceptedWindowCount == 1)

        try assembler.recordDistance(deltaMeters: 1_000, coverage: .complete)
        let outlierCandidate = try assembler.ingestSOC(reading(74, uptime: 3), policy: p)
        let outlier = try #require(outlierCandidate)
        #expect(model.ingest(outlier, policy: p).disposition == .rejected(.efficiencyOutlier))
        #expect(model.acceptedWindowCount == 1)
        #expect(assembler.anchorSOC?.percentage == 74)
        #expect(assembler.accumulatedDistanceMeters == 0)

        try assembler.recordDistance(deltaMeters: 300, coverage: .complete)
        let cleanCandidate = try assembler.ingestSOC(reading(71, uptime: 4), policy: p)
        let clean = try #require(cleanCandidate)

        #expect(clean.startSOC.percentage == 74)
        #expect(clean.endSOC.percentage == 71)
        #expect(clean.distanceMeters == 300)
        #expect(model.ingest(clean, policy: p).disposition == .accepted)
        #expect(model.acceptedWindowCount == 2)
    }

    @Test("known post-gap anchor discards pre-gap evidence before clean learning resumes")
    func explicitContinuityResetStartsCleanSpan() throws {
        var assembler = BatteryRangeLearningWindowAssembler()
        var model = AdaptiveBatteryRangeModel()
        let p = try policy()

        _ = try assembler.ingestSOC(reading(80, uptime: 100), policy: p)
        try assembler.recordDistance(deltaMeters: 500, coverage: .partial)
        assembler.recordTransportGap()

        #expect(throws: BatteryRangeWindowAssemblyError.nonMonotonicAuthoritativeSOC) {
            _ = try assembler.ingestSOC(reading(75, uptime: 99), policy: p)
        }

        // A higher integration layer has identified a fresh post-gap epoch.
        // Reset deliberately abandons the old ordering baseline and evidence.
        assembler.reset()
        _ = try assembler.ingestSOC(reading(75, uptime: 10), policy: p)
        try assembler.recordDistance(deltaMeters: 180, coverage: .complete)

        let candidate = try assembler.ingestSOC(reading(72, uptime: 11), policy: p)
        let clean = try #require(candidate)

        #expect(clean.startSOC.percentage == 75)
        #expect(clean.startSOC.receivedAtUptimeNanoseconds == 10)
        #expect(clean.endSOC.percentage == 72)
        #expect(clean.distanceMeters == 180)
        #expect(clean.distanceCoverage == .complete)
        #expect(clean.transportGapOccurred == false)
        #expect(model.ingest(clean, policy: p).disposition == .accepted)
        #expect(model.acceptedWindowCount == 1)
    }
}
