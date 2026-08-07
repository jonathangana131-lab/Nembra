import Foundation
import Testing
@testable import NembraCore

@Suite("Adaptive battery range live truth")
struct AdaptiveBatteryRangeLiveTruthTests {
    @Test("accepted verified SoC projects to a current receipt-bound anchor")
    func acceptedVerifiedSOCProjectsCurrentAnchor() throws {
        let epoch = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let observation = try verifiedSOC(
            percent: 73,
            epoch: epoch,
            sequence: 1,
            uptime: 1_000
        )
        var validator = BatteryEvidenceStreamValidator()
        try validator.accept(observation)

        let anchor = try AcceptedBatterySOCAnchor.current(
            observation: observation,
            acceptedBy: validator
        )

        #expect(anchor.percentage == 73)
        #expect(anchor.sourceReceiptIdentity == observation.receiptIdentity)
        #expect(anchor.receivedAtUptimeNanoseconds == 1_000)
        #expect(anchor.isCurrent(in: validator))
    }

    @Test("stock-app correlation anchor cannot become live range SoC")
    func correlationAnchorRejected() throws {
        let observation = try BatteryEvidenceObservation.nonAuthoritative(
            value: .stateOfChargePercent(73),
            role: .stockAppCorrelationAnchor,
            receivedAtUptimeNanoseconds: 1_000,
            receivedAtDate: Date(timeIntervalSinceReferenceDate: 1)
        )
        let validator = BatteryEvidenceStreamValidator()

        #expect(throws: AdaptiveBatteryRangeLiveTruthError.notVerifiedStateOfCharge) {
            _ = try AcceptedBatterySOCAnchor.current(
                observation: observation,
                acceptedBy: validator
            )
        }
    }

    @Test("verified SoC is rejected until its receipt has passed stream admission")
    func unacceptedVerifiedSOCRejected() throws {
        let observation = try verifiedSOC(
            percent: 73,
            epoch: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            sequence: 1,
            uptime: 1_000
        )
        let validator = BatteryEvidenceStreamValidator()

        #expect(throws: AdaptiveBatteryRangeLiveTruthError.observationNotCurrentlyAccepted) {
            _ = try AcceptedBatterySOCAnchor.current(
                observation: observation,
                acceptedBy: validator
            )
        }
    }

    @Test("marking an unobserved interval immediately blocks retained SoC recomputation")
    func continuityGapInvalidatesRetainedAnchor() throws {
        let epoch = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let observation = try verifiedSOC(
            percent: 68,
            epoch: epoch,
            sequence: 1,
            uptime: 5_000
        )
        var validator = BatteryEvidenceStreamValidator()
        try validator.accept(observation)
        let anchor = try AcceptedBatterySOCAnchor.current(
            observation: observation,
            acceptedBy: validator
        )
        let model = AdaptiveBatteryRangeModel()
        let policy = try provisionalPolicy()
        #expect(model.estimateRemainingRange(
            atAcceptedSOC: anchor,
            acceptedBy: validator,
            policy: policy
        ) != nil)

        validator.markUnobservedInterval()

        #expect(anchor.isCurrent(in: validator) == false)
        #expect(model.estimateRemainingRange(
            atAcceptedSOC: anchor,
            acceptedBy: validator,
            policy: policy
        ) == nil)
        #expect(throws: AdaptiveBatteryRangeLiveTruthError.observationNotCurrentlyAccepted) {
            _ = try AcceptedBatterySOCAnchor.current(
                observation: observation,
                acceptedBy: validator
            )
        }
    }

    @Test("new post-gap receipt supersedes retained pre-gap anchor")
    func postGapReceiptSupersedesOldAnchor() throws {
        let epoch = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let oldObservation = try verifiedSOC(
            percent: 64,
            epoch: epoch,
            sequence: 1,
            uptime: 10_000
        )
        var validator = BatteryEvidenceStreamValidator()
        try validator.accept(oldObservation)
        let oldAnchor = try AcceptedBatterySOCAnchor.current(
            observation: oldObservation,
            acceptedBy: validator
        )

        validator.markUnobservedInterval()
        let newObservation = try verifiedSOC(
            percent: 63,
            epoch: epoch,
            sequence: 2,
            uptime: 12_000,
            continuity: .afterUnobservedInterval
        )
        try validator.accept(newObservation)
        let newAnchor = try AcceptedBatterySOCAnchor.current(
            observation: newObservation,
            acceptedBy: validator
        )

        #expect(oldAnchor.isCurrent(in: validator) == false)
        #expect(newAnchor.isCurrent(in: validator))

        let model = AdaptiveBatteryRangeModel()
        let policy = try provisionalPolicy()
        #expect(model.estimateRemainingRange(
            atAcceptedSOC: oldAnchor,
            acceptedBy: validator,
            policy: policy
        ) == nil)
        #expect(model.estimateRemainingRange(
            atAcceptedSOC: newAnchor,
            acceptedBy: validator,
            policy: policy
        ) != nil)
    }

    @Test("live derived range carries source receipt and cannot be refreshed from superseded SoC")
    func liveEstimateCarriesReceiptFreshness() throws {
        let epoch = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
        let firstObservation = try verifiedSOC(
            percent: 50,
            epoch: epoch,
            sequence: 1,
            uptime: 20_000
        )
        var validator = BatteryEvidenceStreamValidator()
        try validator.accept(firstObservation)
        let anchor = try AcceptedBatterySOCAnchor.current(
            observation: firstObservation,
            acceptedBy: validator
        )

        let policy = try provisionalPolicy(efficiency: 120)
        let model = AdaptiveBatteryRangeModel()
        let liveEstimate = try #require(
            model.estimateRemainingRange(
                atAcceptedSOC: anchor,
                acceptedBy: validator,
                policy: policy
            )
        )

        #expect(liveEstimate.estimate.rawRemainingMeters == 6_000)
        #expect(liveEstimate.estimate.socProvenance == .authoritativeMeasurement)
        #expect(liveEstimate.sourceReceiptIdentity == anchor.sourceReceiptIdentity)
        #expect(liveEstimate.isCurrent(in: validator))

        let secondObservation = try verifiedSOC(
            percent: 49,
            epoch: epoch,
            sequence: 2,
            uptime: 21_000
        )
        try validator.accept(secondObservation)

        #expect(liveEstimate.isCurrent(in: validator) == false)
        #expect(model.estimateRemainingRange(
            atAcceptedSOC: anchor,
            acceptedBy: validator,
            policy: policy
        ) == nil)
    }

    @Test("generic estimated path refuses an authoritative package fixture")
    func genericEstimatedPathRejectsAuthoritativeReading() throws {
        let authoritative = try BatterySOCReading(
            percentage: 50,
            provenance: .authoritativeMeasurement,
            receivedAtUptimeNanoseconds: 1
        )
        let model = AdaptiveBatteryRangeModel()

        #expect(model.estimateRemainingRange(
            atEstimatedSOC: authoritative,
            policy: try provisionalPolicy()
        ) == nil)
    }

    @Test("verified non-SoC telemetry cannot project to range SoC")
    func verifiedNonSOCRejected() throws {
        let epoch = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!
        let receipt = BatteryEvidenceReceiptIdentity(
            acquisitionEpoch: epoch,
            sequenceNumber: 1
        )
        let observation = try BatteryEvidenceObservation(
            value: .powerWatts(420),
            role: .verifiedVehicleMeasurement,
            receiptIdentity: receipt,
            receivedAtUptimeNanoseconds: 30_000,
            receivedAtDate: Date(timeIntervalSinceReferenceDate: 30)
        )
        var validator = BatteryEvidenceStreamValidator()
        try validator.accept(observation)

        #expect(throws: AdaptiveBatteryRangeLiveTruthError.notVerifiedStateOfCharge) {
            _ = try AcceptedBatterySOCAnchor.current(
                observation: observation,
                acceptedBy: validator
            )
        }
    }

    private func provisionalPolicy(efficiency: Double = 100) throws -> AdaptiveBatteryRangePolicy {
        try AdaptiveBatteryRangePolicy(
            minimumConsumedPercentagePoints: 5,
            minimumDistanceMeters: 100,
            recentWindowCapacity: 4,
            recentWeight: 0.5,
            outlierLowerEfficiencyRatio: 0.5,
            outlierUpperEfficiencyRatio: 2,
            estimateDeadbandFraction: 0,
            estimateSmoothingFactor: 1,
            provisionalEfficiencyMetersPerPercentagePoint: efficiency,
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
