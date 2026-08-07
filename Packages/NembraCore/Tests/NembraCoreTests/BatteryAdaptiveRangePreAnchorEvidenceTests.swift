import Foundation
import Testing
@testable import NembraCore

@Suite("Battery adaptive range pre-anchor evidence")
struct BatteryAdaptiveRangePreAnchorEvidenceTests {
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

    private func verifiedSOC(
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

    @Test("distance and transport-gap evidence before the first verified SoC anchor are discarded")
    func firstVerifiedAnchorStartsCleanSpan() throws {
        var pipeline = BatteryAdaptiveRangeLearningPipeline()
        let p = try policy()

        try pipeline.recordDistance(deltaMeters: 250, coverage: .partial)
        pipeline.recordTransportGap()

        #expect(pipeline.windowAssembler.anchorSOC == nil)
        #expect(pipeline.windowAssembler.accumulatedDistanceMeters == 250)
        #expect(pipeline.windowAssembler.distanceCoverage == .partial)
        #expect(pipeline.windowAssembler.transportGapOccurred)

        let anchorResult = try pipeline.acceptBatteryObservation(
            verifiedSOC(80, uptime: 1),
            policy: p
        )

        #expect(anchorResult.disposition == .authoritativeSOCIngested)
        #expect(anchorResult.candidateLearningWindow == nil)
        #expect(pipeline.windowAssembler.anchorSOC?.percentage == 80)
        #expect(pipeline.windowAssembler.latestAuthoritativeSOC?.percentage == 80)
        #expect(pipeline.windowAssembler.accumulatedDistanceMeters == 0)
        #expect(pipeline.windowAssembler.distanceCoverage == .complete)
        #expect(pipeline.windowAssembler.transportGapOccurred == false)

        try pipeline.recordDistance(deltaMeters: 300, coverage: .complete)
        let endResult = try pipeline.acceptBatteryObservation(
            verifiedSOC(77, uptime: 2),
            policy: p
        )
        let candidate = try #require(endResult.candidateLearningWindow)

        #expect(candidate.startSOC.percentage == 80)
        #expect(candidate.endSOC.percentage == 77)
        #expect(candidate.distanceMeters == 300)
        #expect(candidate.distanceCoverage == .complete)
        #expect(candidate.transportGapOccurred == false)
    }
}
