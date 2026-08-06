import Foundation
import Testing
@testable import NembraCore

@Suite("Battery adaptive range model boundary")
struct BatteryAdaptiveRangeModelBoundaryTests {
    private func observation(
        _ percentage: Double,
        uptime: UInt64
    ) throws -> BatteryEvidenceObservation {
        try BatteryEvidenceObservation(
            value: BatterySemanticValue.stateOfChargePercent(percentage),
            role: .verifiedVehicleMeasurement,
            receivedAtUptimeNanoseconds: uptime,
            receivedAtDate: Date(timeIntervalSince1970: 1_000),
            continuity: .continuous
        )
    }

    private func policy() throws -> AdaptiveBatteryRangePolicy {
        try AdaptiveBatteryRangePolicy(
            minimumConsumedPercentagePoints: 3,
            minimumDistanceMeters: 300,
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

    private func candidate(
        coverage: BatteryRangeDistanceCoverage = .complete,
        transportGap: Bool = false
    ) throws -> (BatteryRangeLearningWindow, AdaptiveBatteryRangePolicy) {
        var pipeline = BatteryAdaptiveRangeLearningPipeline()
        let p = try policy()

        _ = try pipeline.acceptBatteryObservation(
            observation(80, uptime: 1),
            policy: p
        )
        try pipeline.recordDistance(
            deltaMeters: 300,
            coverage: coverage
        )
        if transportGap {
            pipeline.recordTransportGap()
        }

        let result = try pipeline.acceptBatteryObservation(
            observation(77, uptime: 2),
            policy: p
        )
        return (try #require(result.learningWindow), p)
    }

    @Test("clean pipeline candidate is accepted by the adaptive model")
    func cleanCandidateIsAccepted() throws {
        let (window, p) = try candidate()
        var model = AdaptiveBatteryRangeModel()

        let result = model.ingest(window, policy: p)

        #expect(result.disposition == .accepted)
        #expect(result.sample?.distanceMeters == 300)
        #expect(result.sample?.consumedPercentagePoints == 3)
        #expect(result.sample?.metersPerPercentagePoint == 100)
        #expect(model.acceptedWindowCount == 1)
        #expect(model.historicalConsumedPercentagePoints == 3)
        #expect(model.historicalEfficiencyMetersPerPercentagePoint == 100)
    }

    @Test("omitted distance coverage defaults unknown and cannot train learned history")
    func omittedCoverageFailsClosed() throws {
        var pipeline = BatteryAdaptiveRangeLearningPipeline()
        var model = AdaptiveBatteryRangeModel()
        let p = try policy()

        _ = try pipeline.acceptBatteryObservation(
            observation(80, uptime: 1),
            policy: p
        )
        try pipeline.recordDistance(deltaMeters: 300)
        let result = try pipeline.acceptBatteryObservation(
            observation(77, uptime: 2),
            policy: p
        )
        let window = try #require(result.learningWindow)
        let before = model
        let ingest = model.ingest(window, policy: p)

        #expect(window.distanceCoverage == .unknown)
        #expect(ingest.disposition == .rejected(.incompleteDistanceEvidence))
        #expect(ingest.sample == nil)
        #expect(model == before)
    }

    @Test("partial pipeline candidate remains explicit and cannot mutate learned history")
    func partialCandidateIsRejectedWithoutMutation() throws {
        let (window, p) = try candidate(coverage: .partial)
        var model = AdaptiveBatteryRangeModel()
        let before = model

        let result = model.ingest(window, policy: p)

        #expect(result.disposition == .rejected(.incompleteDistanceEvidence))
        #expect(result.sample == nil)
        #expect(model == before)
    }

    @Test("unknown pipeline candidate remains explicit and cannot mutate learned history")
    func unknownCandidateIsRejectedWithoutMutation() throws {
        let (window, p) = try candidate(coverage: .unknown)
        var model = AdaptiveBatteryRangeModel()
        let before = model

        let result = model.ingest(window, policy: p)

        #expect(result.disposition == .rejected(.incompleteDistanceEvidence))
        #expect(result.sample == nil)
        #expect(model == before)
    }

    @Test("observed transport-gap candidate is preserved for model rejection without mutation")
    func transportGapCandidateIsRejectedWithoutMutation() throws {
        let (window, p) = try candidate(transportGap: true)
        var model = AdaptiveBatteryRangeModel()
        let before = model

        let result = model.ingest(window, policy: p)

        #expect(window.transportGapOccurred)
        #expect(result.disposition == .rejected(.transportGap))
        #expect(result.sample == nil)
        #expect(model == before)
    }

    @Test("model outlier rejection never replays the emitted assembler span")
    func rejectedOutlierSpanIsNotReplayed() throws {
        var pipeline = BatteryAdaptiveRangeLearningPipeline()
        var model = AdaptiveBatteryRangeModel()
        let p = try policy()

        _ = try pipeline.acceptBatteryObservation(
            observation(80, uptime: 1),
            policy: p
        )
        try pipeline.recordDistance(deltaMeters: 300, coverage: .complete)
        let baselineResult = try pipeline.acceptBatteryObservation(
            observation(77, uptime: 2),
            policy: p
        )
        let baselineWindow = try #require(baselineResult.learningWindow)
        let baselineIngest = model.ingest(baselineWindow, policy: p)

        #expect(baselineIngest.disposition == .accepted)
        #expect(model.acceptedWindowCount == 1)
        #expect(model.historicalEfficiencyMetersPerPercentagePoint == 100)
        #expect(pipeline.windowAssembler.anchorSOC?.percentage == 77)
        #expect(pipeline.windowAssembler.accumulatedDistanceMeters == 0)

        // 900 m / 3 percentage points = 300 m/%: 3x the learned 100 m/%
        // baseline, above the policy's 2.5x outlier ceiling.
        try pipeline.recordDistance(deltaMeters: 900, coverage: .complete)
        let outlierResult = try pipeline.acceptBatteryObservation(
            observation(74, uptime: 3),
            policy: p
        )
        let outlierWindow = try #require(outlierResult.learningWindow)
        let beforeOutlier = model
        let rejected = model.ingest(outlierWindow, policy: p)

        #expect(outlierWindow.startSOC.percentage == 77)
        #expect(outlierWindow.endSOC.percentage == 74)
        #expect(outlierWindow.distanceMeters == 900)
        #expect(outlierWindow.distanceCoverage == .complete)
        #expect(rejected.disposition == .rejected(.efficiencyOutlier))
        #expect(rejected.sample == nil)
        #expect(model == beforeOutlier)

        // The assembler closed the rejected span at 74% before model acceptance.
        // Its 900 m must never be replayed into the next clean window.
        #expect(pipeline.windowAssembler.anchorSOC?.percentage == 74)
        #expect(pipeline.windowAssembler.latestAuthoritativeSOC?.percentage == 74)
        #expect(pipeline.windowAssembler.accumulatedDistanceMeters == 0)

        try pipeline.recordDistance(deltaMeters: 300, coverage: .complete)
        let cleanResult = try pipeline.acceptBatteryObservation(
            observation(71, uptime: 4),
            policy: p
        )
        let cleanWindow = try #require(cleanResult.learningWindow)
        let accepted = model.ingest(cleanWindow, policy: p)

        #expect(cleanWindow.startSOC.percentage == 74)
        #expect(cleanWindow.endSOC.percentage == 71)
        #expect(cleanWindow.distanceMeters == 300)
        #expect(cleanWindow.distanceCoverage == .complete)
        #expect(accepted.disposition == .accepted)
        #expect(accepted.sample?.metersPerPercentagePoint == 100)
        #expect(model.acceptedWindowCount == 2)
        #expect(model.historicalConsumedPercentagePoints == 6)
        #expect(model.historicalEfficiencyMetersPerPercentagePoint == 100)
    }
}
