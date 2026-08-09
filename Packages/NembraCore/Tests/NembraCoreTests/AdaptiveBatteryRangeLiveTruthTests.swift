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
        var stream = AcceptedBatterySOCStream()
        let anchor = try #require(stream.accept(observation))

        #expect(anchor.percentage == 73)
        #expect(anchor.sourceReceiptIdentity == observation.receiptIdentity)
        #expect(anchor.receivedAtUptimeNanoseconds == 1_000)
        #expect(anchor.continuitySegmentStartReceiptIdentity == anchor.sourceReceiptIdentity)
        #expect(anchor.isCurrent)
        #expect(anchor.isCurrent(in: stream.validator))
    }

    @Test("standalone chronology validator yields only a detached non-current projection")
    func standaloneValidatorCannotMintCurrentAnchor() throws {
        let epoch = UUID(uuidString: "11111111-1111-1111-1111-111111111112")!
        let observation = try verifiedSOC(
            percent: 73,
            epoch: epoch,
            sequence: 1,
            uptime: 1_000
        )
        var validator = BatteryEvidenceStreamValidator()
        try validator.accept(observation)
        let policy = try provisionalPolicy()

        let anchor = try AcceptedBatterySOCAnchor.current(
            observation: observation,
            acceptedBy: validator
        )
        #expect(anchor.isCurrent == false)
        #expect(anchor.isCurrent(in: validator) == false)
        #expect(AdaptiveBatteryRangeModel().estimateRemainingRange(
            atAcceptedSOC: anchor,
            acceptedBy: validator,
            policy: policy
        ) == nil)
    }

    @Test("current projection rejects same receipt with forged continuous metadata")
    func currentProjectionRejectsForgedContinuousMetadata() throws {
        let epoch = UUID(uuidString: "12121212-1212-1212-1212-121212121212")!
        var stream = AcceptedBatterySOCStream()
        let beforeGap = try verifiedSOC(percent: 74, epoch: epoch, sequence: 1, uptime: 1_000)
        _ = try stream.accept(beforeGap)
        stream.markUnobservedInterval()

        let acceptedBoundary = try verifiedSOC(
            percent: 73,
            epoch: epoch,
            sequence: 2,
            uptime: 2_000,
            continuity: .afterUnobservedInterval
        )
        _ = try stream.accept(acceptedBoundary)

        let forgedSibling = try verifiedSOC(
            percent: 73,
            epoch: epoch,
            sequence: 2,
            uptime: 2_000,
            continuity: .continuous
        )

        #expect(throws: AdaptiveBatteryRangeLiveTruthError.observationNotCurrentlyAccepted) {
            _ = try AcceptedBatterySOCAnchor.current(
                observation: forgedSibling,
                acceptedBy: stream.validator
            )
        }
        #expect(try AcceptedBatterySOCAnchor.current(
            observation: acceptedBoundary,
            acceptedBy: stream.validator
        ).continuity == .afterUnobservedInterval)
    }

    @Test("current projection rejects same receipt with forged post-gap metadata")
    func currentProjectionRejectsForgedPostGapMetadata() throws {
        let epoch = UUID(uuidString: "13131313-1313-1313-1313-131313131313")!
        let accepted = try verifiedSOC(percent: 73, epoch: epoch, sequence: 1, uptime: 1_000)
        var stream = AcceptedBatterySOCStream()
        _ = try stream.accept(accepted)

        let forgedSibling = try verifiedSOC(
            percent: 73,
            epoch: epoch,
            sequence: 1,
            uptime: 1_000,
            continuity: .afterUnobservedInterval
        )

        #expect(throws: AdaptiveBatteryRangeLiveTruthError.observationNotCurrentlyAccepted) {
            _ = try AcceptedBatterySOCAnchor.current(
                observation: forgedSibling,
                acceptedBy: stream.validator
            )
        }
        #expect(try AcceptedBatterySOCAnchor.current(
            observation: accepted,
            acceptedBy: stream.validator
        ).continuity == .continuous)
    }

    @Test("accepted SoC stream rotates segment only after an accepted gap boundary")
    func acceptedSOCStreamTracksContinuitySegments() throws {
        let epoch = UUID(uuidString: "14141414-1414-1414-1414-141414141414")!
        var stream = AcceptedBatterySOCStream()
        let first = try #require(stream.accept(
            try verifiedSOC(percent: 80, epoch: epoch, sequence: 1, uptime: 1_000)
        ))
        #expect(first.continuitySegmentStartReceiptIdentity == first.sourceReceiptIdentity)

        stream.markUnobservedInterval()
        let boundary = try #require(stream.accept(
            try verifiedSOC(
                percent: 79,
                epoch: epoch,
                sequence: 2,
                uptime: 2_000,
                continuity: .afterUnobservedInterval
            )
        ))
        let later = try #require(stream.accept(
            try verifiedSOC(percent: 78, epoch: epoch, sequence: 3, uptime: 3_000)
        ))

        #expect(boundary.continuitySegmentStartReceiptIdentity == boundary.sourceReceiptIdentity)
        #expect(later.continuitySegmentStartReceiptIdentity == boundary.sourceReceiptIdentity)
        #expect(first.continuitySegmentStartReceiptIdentity != later.continuitySegmentStartReceiptIdentity)
    }

    @Test("rejected boundary cannot rotate accepted SoC segment")
    func rejectedBoundaryDoesNotRotateSegment() throws {
        let epoch = UUID(uuidString: "15151515-1515-1515-1515-151515151515")!
        var stream = AcceptedBatterySOCStream()
        let first = try #require(stream.accept(
            try verifiedSOC(percent: 80, epoch: epoch, sequence: 1, uptime: 1_000)
        ))
        stream.markUnobservedInterval()

        let missingBoundary = try verifiedSOC(
            percent: 79,
            epoch: epoch,
            sequence: 2,
            uptime: 2_000,
            continuity: .continuous
        )
        #expect(throws: BatteryEvidenceStreamValidationError.missingContinuityBoundary) {
            _ = try stream.accept(missingBoundary)
        }
        #expect(stream.continuitySegmentStartReceiptIdentity == first.sourceReceiptIdentity)
        #expect(stream.validator.requiresContinuityBoundary)
        #expect(first.isCurrent == false)

        let recovery = try #require(stream.accept(
            try verifiedSOC(
                percent: 78,
                epoch: epoch,
                sequence: 3,
                uptime: 3_000,
                continuity: .afterUnobservedInterval
            )
        ))
        #expect(recovery.continuitySegmentStartReceiptIdentity == recovery.sourceReceiptIdentity)
        #expect(stream.validator.requiresContinuityBoundary == false)
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
        var stream = AcceptedBatterySOCStream()
        let anchor = try #require(stream.accept(observation))
        let model = AdaptiveBatteryRangeModel()
        let policy = try provisionalPolicy()
        #expect(model.estimateRemainingRange(
            atAcceptedSOC: anchor,
            acceptedBy: stream.validator,
            policy: policy
        ) != nil)

        let staleValidator = stream.validator
        stream.markUnobservedInterval()

        #expect(anchor.isCurrent == false)
        #expect(anchor.isCurrent(in: stream.validator) == false)
        #expect(anchor.isCurrent(in: staleValidator) == false)
        #expect(model.estimateRemainingRange(
            atAcceptedSOC: anchor,
            acceptedBy: staleValidator,
            policy: policy
        ) == nil)
        #expect(throws: AdaptiveBatteryRangeLiveTruthError.observationNotCurrentlyAccepted) {
            _ = try AcceptedBatterySOCAnchor.current(
                observation: observation,
                acceptedBy: staleValidator
            )
        }
    }

    @Test("new post-gap receipt supersedes retained pre-gap anchor even through cached R1 validator")
    func postGapReceiptSupersedesOldAnchor() throws {
        let epoch = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let oldObservation = try verifiedSOC(
            percent: 64,
            epoch: epoch,
            sequence: 1,
            uptime: 10_000
        )
        var stream = AcceptedBatterySOCStream()
        let oldAnchor = try #require(stream.accept(oldObservation))
        let staleValidator = stream.validator
        var staleStream = stream

        stream.markUnobservedInterval()
        let newObservation = try verifiedSOC(
            percent: 63,
            epoch: epoch,
            sequence: 2,
            uptime: 12_000,
            continuity: .afterUnobservedInterval
        )
        let newAnchor = try #require(stream.accept(newObservation))

        #expect(oldAnchor.isCurrent == false)
        #expect(oldAnchor.isCurrent(in: staleValidator) == false)
        #expect(newAnchor.isCurrent)
        #expect(newAnchor.isCurrent(in: stream.validator))

        let model = AdaptiveBatteryRangeModel()
        let policy = try provisionalPolicy()
        #expect(model.estimateRemainingRange(
            atAcceptedSOC: oldAnchor,
            acceptedBy: staleValidator,
            policy: policy
        ) == nil)
        #expect(model.estimateRemainingRange(
            atAcceptedSOC: newAnchor,
            acceptedBy: stream.validator,
            policy: policy
        ) != nil)

        #expect(throws: BatteryEvidenceStreamValidationError.staleCurrentnessOwner) {
            _ = try staleStream.accept(oldObservation)
        }
        #expect(throws: AdaptiveBatteryRangeLiveTruthError.observationNotCurrentlyAccepted) {
            _ = try AcceptedBatterySOCAnchor.current(
                observation: oldObservation,
                acceptedBy: staleValidator
            )
        }
    }

    @Test("rejected newer callback still revokes old currentness for every copied validator")
    func rejectedNewerReceiptRevokesCachedCurrentness() throws {
        let epoch = UUID(uuidString: "45454545-4545-4545-4545-454545454545")!
        var stream = AcceptedBatterySOCStream()
        let first = try #require(stream.accept(
            try verifiedSOC(percent: 64, epoch: epoch, sequence: 1, uptime: 10_000)
        ))
        let staleValidator = stream.validator

        let backwardNewer = try verifiedSOC(
            percent: 63,
            epoch: epoch,
            sequence: 2,
            uptime: 9_000
        )
        #expect(throws: BatteryEvidenceStreamValidationError.nonMonotonicUptime) {
            _ = try stream.accept(backwardNewer)
        }

        #expect(first.isCurrent == false)
        #expect(first.isCurrent(in: staleValidator) == false)
        #expect(stream.validator.lastAcceptedReceiptIdentity == first.sourceReceiptIdentity)
        #expect(staleValidator.lastAcceptedReceiptIdentity == first.sourceReceiptIdentity)
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
        var stream = AcceptedBatterySOCStream()
        let anchor = try #require(stream.accept(firstObservation))
        let staleValidator = stream.validator

        let policy = try provisionalPolicy(efficiency: 120)
        let model = AdaptiveBatteryRangeModel()
        let liveEstimate = try #require(
            model.estimateRemainingRange(
                atAcceptedSOC: anchor,
                acceptedBy: stream.validator,
                policy: policy
            )
        )

        #expect(liveEstimate.estimate.rawRemainingMeters == 6_000)
        #expect(liveEstimate.estimate.socProvenance == .authoritativeMeasurement)
        #expect(liveEstimate.sourceReceiptIdentity == anchor.sourceReceiptIdentity)
        #expect(liveEstimate.isCurrent(in: stream.validator))
        #expect(liveEstimate.isCurrent(in: staleValidator))

        let secondObservation = try verifiedSOC(
            percent: 49,
            epoch: epoch,
            sequence: 2,
            uptime: 21_000
        )
        _ = try stream.accept(secondObservation)

        #expect(liveEstimate.isCurrent(in: stream.validator) == false)
        #expect(liveEstimate.isCurrent(in: staleValidator) == false)
        #expect(model.estimateRemainingRange(
            atAcceptedSOC: anchor,
            acceptedBy: staleValidator,
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
