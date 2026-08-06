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
}
