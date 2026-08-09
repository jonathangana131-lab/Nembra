import Foundation
import Testing
@testable import NembraCore

@Suite("Battery range currentness owner replay")
struct BatteryRangeCurrentnessOwnerReplayTests {
    @Test("fresh owner with matching old receipt cannot revive prior live estimate")
    func freshOwnerCannotRevivePriorEstimate() throws {
        let epoch = UUID(uuidString: "91919191-9191-9191-9191-919191919191")!
        let originalObservation = try verifiedSOC(
            percent: 50,
            epoch: epoch,
            sequence: 1,
            uptime: 1_000
        )
        let replacementObservation = try verifiedSOC(
            percent: 49,
            epoch: epoch,
            sequence: 2,
            uptime: 2_000,
            continuity: .afterUnobservedInterval
        )
        let policy = try provisionalPolicy()
        let model = AdaptiveBatteryRangeModel()

        var originalStream = AcceptedBatterySOCStream()
        let originalAnchor = try #require(originalStream.accept(originalObservation))
        let originalEstimate = try #require(model.estimateRemainingRange(
            atAcceptedSOC: originalAnchor,
            acceptedBy: originalStream.validator,
            policy: policy
        ))

        #expect(originalAnchor.isCurrent)
        #expect(originalEstimate.isCurrent)

        originalStream.markUnobservedInterval()
        _ = try #require(originalStream.accept(replacementObservation))

        #expect(originalAnchor.isCurrent == false)
        #expect(originalEstimate.isCurrent == false)

        // A brand-new chronology owner can independently admit the retained R1 fixture for
        // offline/testing purposes. Matching receipt+uptime under that unrelated owner must not
        // revive the old anchor or estimate that belonged to the superseded original owner.
        var replayStream = AcceptedBatterySOCStream()
        let replayAnchor = try #require(replayStream.accept(originalObservation))

        #expect(replayAnchor.isCurrent)
        #expect(replayAnchor.sourceReceiptIdentity == originalAnchor.sourceReceiptIdentity)
        #expect(replayAnchor.receivedAtUptimeNanoseconds == originalAnchor.receivedAtUptimeNanoseconds)
        #expect(originalAnchor.isCurrent(in: replayStream.validator) == false)
        #expect(originalEstimate.isCurrent(in: replayStream.validator) == false)
        #expect(model.estimateRemainingRange(
            atAcceptedSOC: originalAnchor,
            acceptedBy: replayStream.validator,
            policy: policy
        ) == nil)
    }

    private func provisionalPolicy() throws -> AdaptiveBatteryRangePolicy {
        try AdaptiveBatteryRangePolicy(
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
    }

    private func verifiedSOC(
        percent: Double,
        epoch: UUID,
        sequence: UInt64,
        uptime: UInt64,
        continuity: BatteryEvidenceContinuity = .continuous
    ) throws -> BatteryEvidenceObservation {
        let receipt = BatteryEvidenceReceiptIdentity(
            acquisitionEpoch: epoch,
            sequenceNumber: sequence
        )
        return try BatteryEvidenceObservation(
            value: .stateOfChargePercent(percent),
            role: .verifiedVehicleMeasurement,
            receiptIdentity: receipt,
            receivedAtUptimeNanoseconds: uptime,
            receivedAtDate: Date(timeIntervalSinceReferenceDate: Double(uptime) / 1_000),
            continuity: continuity
        )
    }
}
