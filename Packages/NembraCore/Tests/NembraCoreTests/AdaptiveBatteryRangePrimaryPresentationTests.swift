import Foundation
import Testing
@testable import NembraCore

@Suite("Adaptive range primary presentation")
struct AdaptiveBatteryRangePrimaryPresentationTests {
    @Test("no owner-bound estimate stays unavailable")
    func noEstimateStaysUnavailable() throws {
        let presentation = AdaptiveBatteryRangePrimaryPresentationPolicy()
        #expect(presentation.resolve(liveEstimate: nil) == .unavailable(.noEstimate))
    }

    @Test("current provisional seed is learning, never an unqualified number")
    func provisionalSeedStaysLearning() throws {
        let policy = try makePolicy(provisionalEfficiency: 100)
        var stream = AcceptedBatterySOCStream()
        let anchor = try acceptSOC(
            into: &stream,
            epoch: UUID(),
            sequence: 1,
            uptime: 100,
            percentage: 50
        )
        let model = AcceptedAdaptiveBatteryRangeModel()
        let liveEstimate = try #require(
            model.estimateRemainingRange(
                atAcceptedSOC: anchor,
                acceptedBy: stream.validator,
                policy: policy
            )
        )

        #expect(liveEstimate.isCurrent)
        #expect(
            AdaptiveBatteryRangePrimaryPresentationPolicy().resolve(liveEstimate: liveEstimate)
                == .learning(.provisionalSeed)
        )
    }

    @Test("current normal-confidence learned estimate may become primary numeric range")
    func learnedCurrentEstimateMayBecomePrimary() throws {
        let policy = try makePolicy(provisionalEfficiency: nil)
        let acceptedModel = try makeLearnedModel(policy: policy, consumedPercentagePoints: 2)
        var stream = AcceptedBatterySOCStream()
        let anchor = try acceptSOC(
            into: &stream,
            epoch: UUID(),
            sequence: 1,
            uptime: 100,
            percentage: 50
        )
        let liveEstimate = try #require(
            acceptedModel.estimateRemainingRange(
                atAcceptedSOC: anchor,
                acceptedBy: stream.validator,
                policy: policy
            )
        )

        #expect(liveEstimate.isCurrent)
        #expect(
            AdaptiveBatteryRangePrimaryPresentationPolicy().resolve(liveEstimate: liveEstimate)
                == .valueMeters(5_000)
        )
    }

    @Test("marked gap revokes a previously live estimate without presentation-side validator input")
    func markedGapDemotesLiveRange() throws {
        let policy = try makePolicy(provisionalEfficiency: nil)
        let acceptedModel = try makeLearnedModel(policy: policy, consumedPercentagePoints: 2)
        var stream = AcceptedBatterySOCStream()
        let epoch = UUID()
        let anchor = try acceptSOC(
            into: &stream,
            epoch: epoch,
            sequence: 1,
            uptime: 100,
            percentage: 50
        )
        let cachedValidator = stream.validator
        let liveEstimate = try #require(
            acceptedModel.estimateRemainingRange(
                atAcceptedSOC: anchor,
                acceptedBy: cachedValidator,
                policy: policy
            )
        )
        #expect(liveEstimate.isCurrent)

        stream.markUnobservedInterval()

        #expect(liveEstimate.isCurrent == false)
        #expect(
            AdaptiveBatteryRangePrimaryPresentationPolicy().resolve(liveEstimate: liveEstimate)
                == .unavailable(.retainedEstimateRequiresQualifier)
        )
    }

    @Test("newer same-uptime receipt revokes old range by owner chronology, not a clock guess")
    func newerSameUptimeReceiptDemotesOldRange() throws {
        let policy = try makePolicy(provisionalEfficiency: nil)
        let acceptedModel = try makeLearnedModel(policy: policy, consumedPercentagePoints: 2)
        var stream = AcceptedBatterySOCStream()
        let epoch = UUID()
        let anchor = try acceptSOC(
            into: &stream,
            epoch: epoch,
            sequence: 1,
            uptime: 100,
            percentage: 50
        )
        let liveEstimate = try #require(
            acceptedModel.estimateRemainingRange(
                atAcceptedSOC: anchor,
                acceptedBy: stream.validator,
                policy: policy
            )
        )

        let newerReceipt = BatteryEvidenceReceiptIdentity(
            acquisitionEpoch: epoch,
            sequenceNumber: 2
        )
        let newerObservation = try BatteryEvidenceObservation(
            value: .powerWatts(250),
            role: .verifiedVehicleMeasurement,
            receiptIdentity: newerReceipt,
            receivedAtUptimeNanoseconds: 100,
            receivedAtDate: Date(timeIntervalSinceReferenceDate: 2),
            continuity: .continuous
        )
        _ = try stream.accept(newerObservation)

        #expect(liveEstimate.isCurrent == false)
        #expect(
            AdaptiveBatteryRangePrimaryPresentationPolicy().resolve(liveEstimate: liveEstimate)
                == .unavailable(.retainedEstimateRequiresQualifier)
        )
    }

    @Test("cached pre-gap validator cannot make an old live estimate primary again")
    func cachedValidatorCannotReplayPrimaryRange() throws {
        let policy = try makePolicy(provisionalEfficiency: nil)
        let acceptedModel = try makeLearnedModel(policy: policy, consumedPercentagePoints: 2)
        var stream = AcceptedBatterySOCStream()
        let epoch = UUID()
        let anchor = try acceptSOC(
            into: &stream,
            epoch: epoch,
            sequence: 1,
            uptime: 100,
            percentage: 50
        )
        let cachedValidator = stream.validator
        let liveEstimate = try #require(
            acceptedModel.estimateRemainingRange(
                atAcceptedSOC: anchor,
                acceptedBy: cachedValidator,
                policy: policy
            )
        )

        stream.markUnobservedInterval()
        _ = try acceptSOC(
            into: &stream,
            epoch: epoch,
            sequence: 2,
            uptime: 101,
            percentage: 49
        )

        #expect(liveEstimate.isCurrent == false)
        #expect(cachedValidator.isCurrent(anchor) == false)
        #expect(
            AdaptiveBatteryRangePrimaryPresentationPolicy().resolve(liveEstimate: liveEstimate)
                == .unavailable(.retainedEstimateRequiresQualifier)
        )
    }

    @Test("learned estimate below normal confidence remains qualified learning")
    func lowConfidenceRemainsQualified() throws {
        let policy = try AdaptiveBatteryRangePolicy(
            minimumConsumedPercentagePoints: 1,
            minimumDistanceMeters: 1,
            recentWindowCapacity: 5,
            recentWeight: 0.5,
            outlierLowerEfficiencyRatio: 0.1,
            outlierUpperEfficiencyRatio: 10,
            estimateDeadbandFraction: 0,
            estimateSmoothingFactor: 1,
            provisionalEfficiencyMetersPerPercentagePoint: nil,
            lowConfidenceConsumedPercentagePoints: 1,
            normalConfidenceConsumedPercentagePoints: 5,
            highConfidenceConsumedPercentagePoints: 10
        )
        let acceptedModel = try makeLearnedModel(policy: policy, consumedPercentagePoints: 2)
        var stream = AcceptedBatterySOCStream()
        let anchor = try acceptSOC(
            into: &stream,
            epoch: UUID(),
            sequence: 1,
            uptime: 100,
            percentage: 50
        )
        let liveEstimate = try #require(
            acceptedModel.estimateRemainingRange(
                atAcceptedSOC: anchor,
                acceptedBy: stream.validator,
                policy: policy
            )
        )

        #expect(
            AdaptiveBatteryRangePrimaryPresentationPolicy().resolve(liveEstimate: liveEstimate)
                == .learning(.lowConfidenceRequiresQualifier)
        )
    }

    private func makePolicy(
        provisionalEfficiency: Double?
    ) throws -> AdaptiveBatteryRangePolicy {
        try AdaptiveBatteryRangePolicy(
            minimumConsumedPercentagePoints: 1,
            minimumDistanceMeters: 1,
            recentWindowCapacity: 5,
            recentWeight: 0.5,
            outlierLowerEfficiencyRatio: 0.1,
            outlierUpperEfficiencyRatio: 10,
            estimateDeadbandFraction: 0,
            estimateSmoothingFactor: 1,
            provisionalEfficiencyMetersPerPercentagePoint: provisionalEfficiency,
            lowConfidenceConsumedPercentagePoints: 1,
            normalConfidenceConsumedPercentagePoints: 2,
            highConfidenceConsumedPercentagePoints: 4
        )
    }

    private func makeLearnedModel(
        policy: AdaptiveBatteryRangePolicy,
        consumedPercentagePoints: Double
    ) throws -> AcceptedAdaptiveBatteryRangeModel {
        var rawModel = AdaptiveBatteryRangeModel()
        let start = try BatterySOCReading(
            percentage: 100,
            provenance: .authoritativeMeasurement,
            receivedAtUptimeNanoseconds: 1
        )
        let end = try BatterySOCReading(
            percentage: 100 - consumedPercentagePoints,
            provenance: .authoritativeMeasurement,
            receivedAtUptimeNanoseconds: 2
        )
        let window = try BatteryRangeLearningWindow(
            distanceMeters: consumedPercentagePoints * 100,
            distanceCoverage: .complete,
            transportGapOccurred: false,
            startSOC: start,
            endSOC: end
        )
        let result = rawModel.ingest(window, policy: policy)
        #expect(result.disposition == .accepted)
        return AcceptedAdaptiveBatteryRangeModel(trustedRestoredModel: rawModel)
    }

    private func acceptSOC(
        into stream: inout AcceptedBatterySOCStream,
        epoch: UUID,
        sequence: UInt64,
        uptime: UInt64,
        percentage: Double
    ) throws -> AcceptedBatterySOCAnchor {
        let receipt = BatteryEvidenceReceiptIdentity(
            acquisitionEpoch: epoch,
            sequenceNumber: sequence
        )
        let observation = try BatteryEvidenceObservation(
            value: .stateOfChargePercent(percentage),
            role: .verifiedVehicleMeasurement,
            receiptIdentity: receipt,
            receivedAtUptimeNanoseconds: uptime,
            receivedAtDate: Date(timeIntervalSinceReferenceDate: Double(sequence)),
            continuity: .continuous
        )
        return try #require(try stream.accept(observation))
    }
}
