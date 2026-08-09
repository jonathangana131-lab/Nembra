import Foundation
import Testing
@testable import NembraCore

@Suite("Adaptive battery range window assembly")
struct AdaptiveBatteryRangeWindowAssemblerTests {
    private func reading(
        _ percentage: Double,
        provenance: BatterySOCProvenance = .authoritativeMeasurement,
        uptime: UInt64
    ) throws -> BatterySOCReading {
        try BatterySOCReading(
            percentage: percentage,
            provenance: provenance,
            receivedAtUptimeNanoseconds: uptime
        )
    }

    private func policy(
        minimumConsumedPercentagePoints: Double = 3,
        minimumDistanceMeters: Double = 100
    ) throws -> AdaptiveBatteryRangePolicy {
        try AdaptiveBatteryRangePolicy(
            minimumConsumedPercentagePoints: minimumConsumedPercentagePoints,
            minimumDistanceMeters: minimumDistanceMeters,
            recentWindowCapacity: 3,
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

    @Test("estimated SoC never becomes a learning anchor")
    func estimatedSOCNeverAnchors() throws {
        var assembler = BatteryRangeLearningWindowAssembler()
        try assembler.recordDistance(deltaMeters: 250, coverage: .partial)
        assembler.recordTransportGap()

        let result = try assembler.ingestSOC(
            reading(80, provenance: .estimate, uptime: 1),
            policy: policy()
        )

        #expect(result == nil)
        #expect(assembler.hasAuthoritativeAnchor == false)
        #expect(assembler.latestAuthoritativeSOC == nil)
        #expect(assembler.accumulatedDistanceMeters == 250)
        #expect(assembler.distanceCoverage == .partial)
        #expect(assembler.transportGapOccurred)

        _ = try assembler.ingestSOC(reading(80, uptime: 2), policy: policy())
        #expect(assembler.hasAuthoritativeAnchor)
        #expect(assembler.anchorSOC?.percentage == 80)
        #expect(assembler.latestAuthoritativeSOC?.percentage == 80)
        #expect(assembler.accumulatedDistanceMeters == 0)
        #expect(assembler.distanceCoverage == .complete)
        #expect(assembler.transportGapOccurred == false)
    }

    @Test("small percentage drops accumulate into one meaningful window")
    func smallDropsAccumulate() throws {
        var assembler = BatteryRangeLearningWindowAssembler()
        let p = try policy(minimumConsumedPercentagePoints: 3, minimumDistanceMeters: 300)

        #expect(try assembler.ingestSOC(reading(80, uptime: 1), policy: p) == nil)
        try assembler.recordDistance(deltaMeters: 100, coverage: .complete)
        #expect(try assembler.ingestSOC(reading(79, uptime: 2), policy: p) == nil)
        #expect(assembler.latestAuthoritativeSOC?.percentage == 79)
        try assembler.recordDistance(deltaMeters: 120, coverage: .complete)
        #expect(try assembler.ingestSOC(reading(78, uptime: 3), policy: p) == nil)
        #expect(assembler.latestAuthoritativeSOC?.percentage == 78)
        try assembler.recordDistance(deltaMeters: 140, coverage: .complete)

        let assembled = try assembler.ingestSOC(reading(77, uptime: 4), policy: p)
        let window = try #require(assembled)

        #expect(window.startSOC.percentage == 80)
        #expect(window.endSOC.percentage == 77)
        #expect(window.distanceMeters == 360)
        #expect(window.distanceCoverage == .complete)
        #expect(window.transportGapOccurred == false)
        #expect(assembler.anchorSOC?.percentage == 77)
        #expect(assembler.latestAuthoritativeSOC?.percentage == 77)
        #expect(assembler.accumulatedDistanceMeters == 0)
    }

    @Test("current policy threshold is applied when a candidate closes")
    func currentPolicyThresholdControlsClosure() throws {
        var assembler = BatteryRangeLearningWindowAssembler()
        let loose = try policy(minimumConsumedPercentagePoints: 3, minimumDistanceMeters: 100)
        let strict = try policy(minimumConsumedPercentagePoints: 4, minimumDistanceMeters: 100)

        _ = try assembler.ingestSOC(reading(80, uptime: 1), policy: loose)
        try assembler.recordDistance(deltaMeters: 200, coverage: .complete)

        #expect(try assembler.ingestSOC(reading(77, uptime: 2), policy: strict) == nil)
        #expect(assembler.anchorSOC?.percentage == 80)
        #expect(assembler.latestAuthoritativeSOC?.percentage == 77)
        #expect(assembler.accumulatedDistanceMeters == 200)

        let assembled = try assembler.ingestSOC(reading(76, uptime: 3), policy: strict)
        let window = try #require(assembled)
        #expect(window.consumedPercentagePoints == 4)

        var model = AdaptiveBatteryRangeModel()
        let result = model.ingest(window, policy: strict)
        #expect(result.disposition == .accepted)
        #expect(model.acceptedWindowCount == 1)
    }

    @Test("distance threshold can mature while SoC remains flat")
    func flatSOCKeepsAnchor() throws {
        var assembler = BatteryRangeLearningWindowAssembler()
        let p = try policy(minimumConsumedPercentagePoints: 3, minimumDistanceMeters: 300)

        _ = try assembler.ingestSOC(reading(80, uptime: 1), policy: p)
        try assembler.recordDistance(deltaMeters: 200, coverage: .complete)
        #expect(try assembler.ingestSOC(reading(77, uptime: 2), policy: p) == nil)
        #expect(assembler.latestAuthoritativeSOC?.receivedAtUptimeNanoseconds == 2)
        try assembler.recordDistance(deltaMeters: 100, coverage: .complete)

        let assembled = try assembler.ingestSOC(reading(77, uptime: 3), policy: p)
        let window = try #require(assembled)

        #expect(window.startSOC.receivedAtUptimeNanoseconds == 1)
        #expect(window.startSOC.percentage == 80)
        #expect(window.endSOC.percentage == 77)
        #expect(window.distanceMeters == 300)
    }

    @Test("higher authoritative SoC conservatively rebases the evidence span")
    func higherSOCRebases() throws {
        var assembler = BatteryRangeLearningWindowAssembler()
        let p = try policy()

        _ = try assembler.ingestSOC(reading(80, uptime: 1), policy: p)
        try assembler.recordDistance(deltaMeters: 500, coverage: .partial)
        assembler.recordTransportGap()

        let result = try assembler.ingestSOC(reading(81, uptime: 2), policy: p)

        #expect(result == nil)
        #expect(assembler.anchorSOC?.percentage == 81)
        #expect(assembler.latestAuthoritativeSOC?.percentage == 81)
        #expect(assembler.anchorSOC?.receivedAtUptimeNanoseconds == 2)
        #expect(assembler.accumulatedDistanceMeters == 0)
        #expect(assembler.distanceCoverage == .complete)
        #expect(assembler.transportGapOccurred == false)
    }

    @Test("in-span measured recovery rebases and becomes the next clean anchor")
    func inSpanRecoveryRebases() throws {
        var assembler = BatteryRangeLearningWindowAssembler()
        let p = try policy(minimumConsumedPercentagePoints: 3, minimumDistanceMeters: 1_000)

        _ = try assembler.ingestSOC(reading(80, uptime: 1), policy: p)
        try assembler.recordDistance(deltaMeters: 200, coverage: .partial)
        #expect(try assembler.ingestSOC(reading(77, uptime: 2), policy: p) == nil)
        #expect(assembler.anchorSOC?.percentage == 80)
        #expect(assembler.latestAuthoritativeSOC?.percentage == 77)

        let recovery = try assembler.ingestSOC(reading(79, uptime: 3), policy: p)

        #expect(recovery == nil)
        #expect(assembler.anchorSOC?.percentage == 79)
        #expect(assembler.latestAuthoritativeSOC?.percentage == 79)
        #expect(assembler.anchorSOC?.receivedAtUptimeNanoseconds == 3)
        #expect(assembler.accumulatedDistanceMeters == 0)
        #expect(assembler.distanceCoverage == .complete)
        #expect(assembler.transportGapOccurred == false)

        try assembler.recordDistance(deltaMeters: 1_000, coverage: .complete)
        let cleanCandidate = try assembler.ingestSOC(reading(76, uptime: 4), policy: p)
        let clean = try #require(cleanCandidate)

        #expect(clean.startSOC.percentage == 79)
        #expect(clean.startSOC.receivedAtUptimeNanoseconds == 3)
        #expect(clean.endSOC.percentage == 76)
        #expect(clean.distanceMeters == 1_000)
        #expect(clean.distanceCoverage == .complete)
        #expect(clean.transportGapOccurred == false)
    }

    @Test("estimated readings inside a span do not advance or erase measured evidence")
    func estimatedReadingInsideSpanIsIgnored() throws {
        var assembler = BatteryRangeLearningWindowAssembler()
        let p = try policy(minimumConsumedPercentagePoints: 3, minimumDistanceMeters: 100)

        _ = try assembler.ingestSOC(reading(80, uptime: 1), policy: p)
        try assembler.recordDistance(deltaMeters: 150, coverage: .complete)
        #expect(
            try assembler.ingestSOC(
                reading(79, provenance: .estimate, uptime: 2),
                policy: p
            ) == nil
        )
        #expect(assembler.anchorSOC?.percentage == 80)
        #expect(assembler.latestAuthoritativeSOC?.percentage == 80)
        #expect(assembler.latestAuthoritativeSOC?.receivedAtUptimeNanoseconds == 1)
        #expect(assembler.accumulatedDistanceMeters == 150)

        let assembled = try assembler.ingestSOC(reading(77, uptime: 3), policy: p)
        let window = try #require(assembled)
        #expect(window.startSOC.percentage == 80)
        #expect(window.endSOC.percentage == 77)
    }

    @Test("coverage degradation is sticky and reaches the model unchanged")
    func coverageDegradationIsSticky() throws {
        var assembler = BatteryRangeLearningWindowAssembler()
        let p = try policy(minimumConsumedPercentagePoints: 3, minimumDistanceMeters: 100)

        _ = try assembler.ingestSOC(reading(80, uptime: 1), policy: p)
        try assembler.recordDistance(deltaMeters: 100, coverage: .complete)
        try assembler.recordDistance(deltaMeters: 50, coverage: .partial)
        try assembler.recordDistance(deltaMeters: 0, coverage: .unknown)

        let assembled = try assembler.ingestSOC(reading(77, uptime: 2), policy: p)
        let window = try #require(assembled)
        #expect(window.distanceMeters == 150)
        #expect(window.distanceCoverage == .unknown)

        var model = AdaptiveBatteryRangeModel()
        let result = model.ingest(window, policy: p)
        #expect(result.disposition == .rejected(.incompleteDistanceEvidence))
        #expect(model.acceptedWindowCount == 0)
    }

    @Test("omitted distance coverage fails closed as unknown")
    func omittedCoverageFailsClosed() throws {
        var assembler = BatteryRangeLearningWindowAssembler()
        let p = try policy(minimumConsumedPercentagePoints: 3, minimumDistanceMeters: 100)

        _ = try assembler.ingestSOC(reading(80, uptime: 1), policy: p)
        try assembler.recordDistance(deltaMeters: 150)
        #expect(assembler.distanceCoverage == .unknown)

        let assembled = try assembler.ingestSOC(reading(77, uptime: 2), policy: p)
        let window = try #require(assembled)
        #expect(window.distanceMeters == 150)
        #expect(window.distanceCoverage == .unknown)

        var model = AdaptiveBatteryRangeModel()
        #expect(model.ingest(window, policy: p).disposition == .rejected(.incompleteDistanceEvidence))
        #expect(model.acceptedWindowCount == 0)
    }

    @Test("transport gaps remain explicit and cannot train the model")
    func transportGapRemainsExplicit() throws {
        var assembler = BatteryRangeLearningWindowAssembler()
        let p = try policy(minimumConsumedPercentagePoints: 3, minimumDistanceMeters: 100)

        _ = try assembler.ingestSOC(reading(80, uptime: 1), policy: p)
        try assembler.recordDistance(deltaMeters: 150, coverage: .complete)
        assembler.recordTransportGap()

        let assembled = try assembler.ingestSOC(reading(77, uptime: 2), policy: p)
        let window = try #require(assembled)
        #expect(window.transportGapOccurred)

        var model = AdaptiveBatteryRangeModel()
        let result = model.ingest(window, policy: p)
        #expect(result.disposition == .rejected(.transportGap))
        #expect(model.acceptedWindowCount == 0)
    }

    @Test("full normalized 100 to 0 consumption closes at the exact policy boundary")
    func fullNormalizedConsumptionBoundary() throws {
        var assembler = BatteryRangeLearningWindowAssembler()
        let p = try policy(minimumConsumedPercentagePoints: 100, minimumDistanceMeters: 1_000)

        #expect(try assembler.ingestSOC(reading(100, uptime: 1), policy: p) == nil)
        try assembler.recordDistance(deltaMeters: 1_000, coverage: .complete)

        let assembled = try assembler.ingestSOC(reading(0, uptime: 2), policy: p)
        let window = try #require(assembled)
        #expect(window.startSOC.percentage == 100)
        #expect(window.endSOC.percentage == 0)
        #expect(window.consumedPercentagePoints == 100)
        #expect(window.distanceMeters == 1_000)
        #expect(window.distanceCoverage == .complete)
        #expect(window.transportGapOccurred == false)

        var model = AdaptiveBatteryRangeModel()
        #expect(model.ingest(window, policy: p).disposition == .accepted)
        #expect(model.acceptedWindowCount == 1)
        #expect(assembler.anchorSOC?.percentage == 0)
        #expect(assembler.latestAuthoritativeSOC?.percentage == 0)
        #expect(assembler.accumulatedDistanceMeters == 0)
    }

    @Test("invalid distance input and overflow fail without partial mutation")
    func invalidDistanceFailsAtomically() throws {
        var assembler = BatteryRangeLearningWindowAssembler()

        for invalid in [-1.0, Double.nan, Double.infinity, -Double.infinity] {
            let before = assembler
            #expect(throws: BatteryRangeWindowAssemblyError.invalidDistanceDelta) {
                try assembler.recordDistance(deltaMeters: invalid, coverage: .unknown)
            }
            #expect(assembler == before)
        }
        #expect(assembler.accumulatedDistanceMeters == 0)
        #expect(assembler.distanceCoverage == .complete)

        try assembler.recordDistance(deltaMeters: .greatestFiniteMagnitude, coverage: .partial)
        let beforeOverflow = assembler

        #expect(throws: BatteryRangeWindowAssemblyError.distanceOverflow) {
            try assembler.recordDistance(deltaMeters: .greatestFiniteMagnitude, coverage: .unknown)
        }
        #expect(assembler == beforeOverflow)
    }

    @Test("authoritative ordering is enforced against the latest accepted measured sample")
    func nonMonotonicLatestSOCFailsAtomically() throws {
        var assembler = BatteryRangeLearningWindowAssembler()
        let p = try policy(minimumConsumedPercentagePoints: 10, minimumDistanceMeters: 1_000)

        _ = try assembler.ingestSOC(reading(80, uptime: 10), policy: p)
        try assembler.recordDistance(deltaMeters: 150, coverage: .partial)
        #expect(try assembler.ingestSOC(reading(77, uptime: 20), policy: p) == nil)
        assembler.recordTransportGap()
        let before = assembler

        #expect(throws: BatteryRangeWindowAssemblyError.nonMonotonicAuthoritativeSOC) {
            _ = try assembler.ingestSOC(reading(76, uptime: 15), policy: p)
        }
        #expect(assembler == before)
        #expect(assembler.anchorSOC?.receivedAtUptimeNanoseconds == 10)
        #expect(assembler.latestAuthoritativeSOC?.receivedAtUptimeNanoseconds == 20)
    }

    @Test("explicit reset clears only in-flight assembly evidence")
    func resetClearsInFlightEvidence() throws {
        var assembler = BatteryRangeLearningWindowAssembler()
        let p = try policy()

        _ = try assembler.ingestSOC(reading(80, uptime: 1), policy: p)
        try assembler.recordDistance(deltaMeters: 150, coverage: .unknown)
        assembler.recordTransportGap()

        assembler.reset()

        #expect(assembler.anchorSOC == nil)
        #expect(assembler.latestAuthoritativeSOC == nil)
        #expect(assembler.accumulatedDistanceMeters == 0)
        #expect(assembler.distanceCoverage == .complete)
        #expect(assembler.transportGapOccurred == false)
    }
}
