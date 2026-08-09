import Foundation
import Testing
@testable import NembraCore

@Suite("Battery range currentness owner lifetime")
struct BatteryRangeCurrentnessOwnerLifetimeTests {
    @Test("retained anchor and live estimate cannot keep dead owner current")
    func retainedValuesDoNotRetainAuthorityOwner() throws {
        let retained = try makeValuesWhoseOwnerLeavesScope()

        #expect(retained.anchor.isCurrent == false)
        #expect(retained.estimate.isCurrent == false)
    }

    private func makeValuesWhoseOwnerLeavesScope() throws -> (
        anchor: AcceptedBatterySOCAnchor,
        estimate: AdaptiveBatteryRangeLiveEstimate
    ) {
        let epoch = UUID(uuidString: "94949494-9494-9494-9494-949494949494")!
        let observation = try BatteryEvidenceObservation(
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
        let policy = try AdaptiveBatteryRangePolicy(
            minimumConsumedPercentagePoints: 5,
            minimumDistanceMeters: 100,
            recentWindowCapacity: 4,
            recentWeight: 0.5,
            outlierLowerEfficiencyRatio: 0.5,
            outlierUpperEfficiencyRatio: 2,
            estimateDeadbandFraction: 0,
            estimateSmoothingFactor: 1,
            provisionalEfficiencyMetersPerPercentagePoint: 100,
            lowConfidenceConsumedPercentagePoints: 10,
            normalConfidenceConsumedPercentagePoints: 20,
            highConfidenceConsumedPercentagePoints: 40
        )

        var stream = AcceptedBatterySOCStream()
        let anchor = try #require(stream.accept(observation))
        let estimate = try #require(AdaptiveBatteryRangeModel().estimateRemainingRange(
            atAcceptedSOC: anchor,
            acceptedBy: stream.validator,
            policy: policy
        ))

        #expect(anchor.isCurrent)
        #expect(estimate.isCurrent)
        return (anchor, estimate)
    }
}
