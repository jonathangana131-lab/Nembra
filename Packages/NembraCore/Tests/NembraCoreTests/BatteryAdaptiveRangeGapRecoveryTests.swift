import Foundation
import Testing
@testable import NembraCore

@Suite("Battery adaptive range gap recovery")
struct BatteryAdaptiveRangeGapRecoveryTests {
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
            lowConfidenceConsumedPercentagePoints: 10,
            normalConfidenceConsumedPercentagePoints: 30,
            highConfidenceConsumedPercentagePoints: 60
        )
    }

    private func verifiedSOC(
        _ percentage: Double,
        uptime: UInt64,
        continuity: BatteryEvidenceContinuity = .continuous
    ) throws -> BatteryEvidenceObservation {
        try BatteryEvidenceObservation(
            value: BatterySemanticValue.stateOfChargePercent(percentage),
            role: .verifiedVehicleMeasurement,
            receivedAtUptimeNanoseconds: uptime,
            receivedAtDate: Date(timeIntervalSince1970: 1_000),
            continuity: continuity
        )
    }

    @Test("missing required boundary failure cannot poison later valid boundary or fresh learning")
    func missingBoundaryFailureRecoversCleanly() throws {
        var pipeline = BatteryAdaptiveRangeLearningPipeline()
        let p = try policy()

        _ = try pipeline.acceptBatteryObservation(
            verifiedSOC(80, uptime: 100),
            policy: p
        )
        try pipeline.recordDistance(deltaMeters: 500, coverage: .complete)

        pipeline.markUnobservedInterval()
        try pipeline.recordDistance(deltaMeters: 400, coverage: .partial)
        pipeline.recordTransportGap()
        let beforeFailure = pipeline

        #expect(throws: BatteryEvidenceStreamValidationError.missingContinuityBoundary) {
            _ = try pipeline.acceptBatteryObservation(
                verifiedSOC(59, uptime: 1),
                policy: p
            )
        }

        #expect(pipeline == beforeFailure)
        #expect(pipeline.evidenceBridge.streamValidator.requiresContinuityBoundary)
        #expect(pipeline.windowAssembler.anchorSOC == nil)
        #expect(pipeline.windowAssembler.accumulatedDistanceMeters == 400)
        #expect(pipeline.windowAssembler.distanceCoverage == .partial)
        #expect(pipeline.windowAssembler.transportGapOccurred)

        let boundary = try pipeline.acceptBatteryObservation(
            verifiedSOC(
                59,
                uptime: 1,
                continuity: .afterUnobservedInterval
            ),
            policy: p
        )

        #expect(boundary.disposition == .continuityResetAndAuthoritativeSOCIngested)
        #expect(boundary.candidateLearningWindow == nil)
        #expect(pipeline.windowAssembler.anchorSOC?.percentage == 59)
        #expect(pipeline.windowAssembler.latestAuthoritativeSOC?.percentage == 59)
        #expect(pipeline.windowAssembler.accumulatedDistanceMeters == 0)
        #expect(pipeline.windowAssembler.distanceCoverage == .complete)
        #expect(pipeline.windowAssembler.transportGapOccurred == false)

        try pipeline.recordDistance(deltaMeters: 300, coverage: .complete)
        let end = try pipeline.acceptBatteryObservation(
            verifiedSOC(56, uptime: 2),
            policy: p
        )
        let candidate = try #require(end.candidateLearningWindow)

        #expect(candidate.startSOC.percentage == 59)
        #expect(candidate.endSOC.percentage == 56)
        #expect(candidate.distanceMeters == 300)
        #expect(candidate.distanceCoverage == .complete)
        #expect(candidate.transportGapOccurred == false)
    }
}
