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
            lowConfidenceConsumedPercentagePoints: 10,
            normalConfidenceConsumedPercentagePoints: 30,
            highConfidenceConsumedPercentagePoints: 60
        )
    }

    private func observation(
        _ percentage: Double,
        role: BatteryEvidenceRole,
        uptime: UInt64 = 1,
        continuity: BatteryEvidenceContinuity = .continuous
    ) throws -> BatteryEvidenceObservation {
        try BatteryEvidenceObservation(
            value: BatterySemanticValue.stateOfChargePercent(percentage),
            role: role,
            receivedAtUptimeNanoseconds: uptime,
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

        var ingestedPipeline = BatteryAdaptiveRangeLearningPipeline()
        let ingested = try ingestedPipeline.acceptBatteryObservation(
            observation(80, role: .verifiedVehicleMeasurement),
            policy: p
        )
        #expect(ingested.disposition == .authoritativeSOCIngested)
        #expect(ingested.candidateLearningWindow == nil)

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

        var resetAndIngestedPipeline = BatteryAdaptiveRangeLearningPipeline()
        let resetAndIngested = try resetAndIngestedPipeline.acceptBatteryObservation(
            observation(
                80,
                role: .verifiedVehicleMeasurement,
                continuity: .afterUnobservedInterval
            ),
            policy: p
        )
        #expect(resetAndIngested.disposition == .continuityResetAndAuthoritativeSOCIngested)
        #expect(resetAndIngested.candidateLearningWindow == nil)
    }

    @Test("public result equality cannot reveal hidden authoritative payload")
    func equalityUsesOnlyPublicState() throws {
        let p = try policy()
        var firstPipeline = BatteryAdaptiveRangeLearningPipeline()
        var secondPipeline = BatteryAdaptiveRangeLearningPipeline()
        var ignoredPipeline = BatteryAdaptiveRangeLearningPipeline()

        let first = try firstPipeline.acceptBatteryObservation(
            observation(80, role: .verifiedVehicleMeasurement),
            policy: p
        )
        let second = try secondPipeline.acceptBatteryObservation(
            observation(79, role: .verifiedVehicleMeasurement),
            policy: p
        )
        let ignored = try ignoredPipeline.acceptBatteryObservation(
            observation(80, role: .stockAppCorrelationAnchor),
            policy: p
        )

        #expect(first.disposition == .authoritativeSOCIngested)
        #expect(second.disposition == .authoritativeSOCIngested)
        #expect(first.candidateLearningWindow == nil)
        #expect(second.candidateLearningWindow == nil)

        // The hidden internal actions carry different authoritative SoC values,
        // but external equality may observe only the public disposition/window.
        #expect(first.action != second.action)
        #expect(first == second)
        #expect(first != ignored)
    }

    @Test("emitted public window remains a candidate until the adaptive model explicitly accepts it")
    func emittedWindowIsOnlyACandidate() throws {
        let p = try policy()
        var pipeline = BatteryAdaptiveRangeLearningPipeline()
        var model = AdaptiveBatteryRangeModel()

        _ = try pipeline.acceptBatteryObservation(
            observation(80, role: .verifiedVehicleMeasurement, uptime: 1),
            policy: p
        )
        try pipeline.recordDistance(deltaMeters: 300, coverage: .complete)

        let result = try pipeline.acceptBatteryObservation(
            observation(77, role: .verifiedVehicleMeasurement, uptime: 2),
            policy: p
        )
        let candidate = try #require(result.candidateLearningWindow)

        #expect(result.disposition == .authoritativeSOCIngested)
        #expect(candidate.startSOC.percentage == 80)
        #expect(candidate.endSOC.percentage == 77)
        #expect(candidate.distanceMeters == 300)
        #expect(model.acceptedWindowCount == 0)
        #expect(model.hasLearnedEfficiency == false)

        let ingest = model.ingest(candidate, policy: p)
        #expect(ingest.disposition == .accepted)
        #expect(model.acceptedWindowCount == 1)
        #expect(model.hasLearnedEfficiency)
    }
}
