import Foundation
import Testing
@testable import NembraCore

@Suite("Battery adaptive range public disposition")
struct BatteryAdaptiveRangePublicDispositionTests {
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

    private func observation(
        _ percentage: Double,
        role: BatteryEvidenceRole,
        continuity: BatteryEvidenceContinuity = .continuous
    ) throws -> BatteryEvidenceObservation {
        try BatteryEvidenceObservation(
            value: BatterySemanticValue.stateOfChargePercent(percentage),
            role: role,
            receivedAtUptimeNanoseconds: 1,
            receivedAtDate: Date(timeIntervalSince1970: 1_000),
            continuity: continuity
        )
    }

    @Test("public disposition classifies validated transitions without exposing authoritative payloads")
    func dispositionsMirrorValidatedActions() throws {
        let p = try policy()

        var ignoredPipeline = BatteryAdaptiveRangeLearningPipeline()
        let ignored = try ignoredPipeline.acceptBatteryObservation(
            observation(80, role: .stockAppCorrelationAnchor),
            policy: p
        )
        #expect(ignored.disposition == .ignored)
        #expect(ignored.candidateLearningWindow == nil)

        var acceptedPipeline = BatteryAdaptiveRangeLearningPipeline()
        let accepted = try acceptedPipeline.acceptBatteryObservation(
            observation(80, role: .verifiedVehicleMeasurement),
            policy: p
        )
        #expect(accepted.disposition == .authoritativeSOCAccepted)
        #expect(accepted.candidateLearningWindow == nil)

        var resetPipeline = BatteryAdaptiveRangeLearningPipeline()
        let reset = try resetPipeline.acceptBatteryObservation(
            observation(
                80,
                role: .stockAppCorrelationAnchor,
                continuity: .afterUnobservedInterval
            ),
            policy: p
        )
        #expect(reset.disposition == .continuityReset)
        #expect(reset.candidateLearningWindow == nil)

        var resetAndAcceptedPipeline = BatteryAdaptiveRangeLearningPipeline()
        let resetAndAccepted = try resetAndAcceptedPipeline.acceptBatteryObservation(
            observation(
                80,
                role: .verifiedVehicleMeasurement,
                continuity: .afterUnobservedInterval
            ),
            policy: p
        )
        #expect(resetAndAccepted.disposition == .continuityResetAndAuthoritativeSOCAccepted)
        #expect(resetAndAccepted.candidateLearningWindow == nil)
    }
}
