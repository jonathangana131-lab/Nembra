import Foundation
import Testing
@testable import NembraCore

@Suite("Accepted adaptive range presentation carry authority")
struct AcceptedAdaptiveBatteryRangePresentationCarryTests {
    @Test("production wrapper snaps to current raw range instead of inheriting unsealed presentation")
    func productionWrapperDoesNotInheritUnsealedPresentation() throws {
        let rangePolicy = try policy()
        let rawModel = AdaptiveBatteryRangeModel()
        let estimatedSOC = try BatterySOCReading.estimated(
            percentage: 50,
            receivedAtUptimeNanoseconds: 1_000
        )

        let generic = try #require(rawModel.estimateRemainingRange(
            atEstimatedSOC: estimatedSOC,
            previousPresentedRemainingMeters: 9_000,
            policy: rangePolicy
        ))
        #expect(generic.rawRemainingMeters == 5_000)
        #expect(generic.presentedRemainingMeters == 8_000)

        let epoch = UUID(uuidString: "DADADADA-DADA-DADA-DADA-DADADADADADA")!
        var stream = AcceptedBatterySOCStream()
        let acceptedSOC = try #require(stream.accept(
            try BatteryEvidenceObservation(
                value: .stateOfChargePercent(50),
                role: .verifiedVehicleMeasurement,
                receiptIdentity: BatteryEvidenceReceiptIdentity(
                    acquisitionEpoch: epoch,
                    sequenceNumber: 1
                ),
                receivedAtUptimeNanoseconds: 1_000,
                receivedAtDate: Date(timeIntervalSinceReferenceDate: 1),
                continuity: .continuous
            )
        ))

        let production = try #require(AcceptedAdaptiveBatteryRangeModel().estimateRemainingRange(
            atAcceptedSOC: acceptedSOC,
            acceptedBy: stream.validator,
            policy: rangePolicy
        ))

        #expect(production.estimate.rawRemainingMeters == 5_000)
        #expect(production.estimate.presentedRemainingMeters == 5_000)
        #expect(production.isCurrent(in: stream.validator))
    }

    private func policy() throws -> AdaptiveBatteryRangePolicy {
        try AdaptiveBatteryRangePolicy(
            minimumConsumedPercentagePoints: 5,
            minimumDistanceMeters: 100,
            recentWindowCapacity: 4,
            recentWeight: 0.5,
            outlierLowerEfficiencyRatio: 0.5,
            outlierUpperEfficiencyRatio: 2,
            estimateDeadbandFraction: 0,
            estimateSmoothingFactor: 0.25,
            provisionalEfficiencyMetersPerPercentagePoint: 100,
            lowConfidenceConsumedPercentagePoints: 10,
            normalConfidenceConsumedPercentagePoints: 20,
            highConfidenceConsumedPercentagePoints: 40
        )
    }
}
