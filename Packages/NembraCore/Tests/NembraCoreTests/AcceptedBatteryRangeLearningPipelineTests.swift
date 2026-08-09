import Foundation
import Testing
@testable import NembraCore

@Suite("Accepted battery range learning pipeline")
struct AcceptedBatteryRangeLearningPipelineTests {
    @Test("complete in-segment distance closes one learning window")
    func completeWindowCloses() throws {
        let epoch = UUID(uuidString: "10101010-1010-1010-1010-101010101010")!
        let p = try policy()
        var pipeline = AcceptedBatteryRangeLearningPipeline()

        let start = try pipeline.acceptBatteryObservation(
            try verifiedSOC(80, epoch: epoch, sequence: 1, uptime: 1_000),
            policy: p
        )
        #expect(start.acceptedSOC?.percentage == 80)
        #expect(start.candidateLearningWindow == nil)

        try pipeline.recordDistance(deltaMeters: 300, coverage: .complete)
        let end = try pipeline.acceptBatteryObservation(
            try verifiedSOC(77, epoch: epoch, sequence: 2, uptime: 2_000),
            policy: p
        )
        let window = try #require(end.candidateLearningWindow)
        #expect(window.startSOC.percentage == 80)
        #expect(window.endSOC.percentage == 77)
        #expect(window.distanceMeters == 300)
        #expect(window.transportGapOccurred == false)
    }

    @Test("incomplete route coverage prevents learning until a fresh boundary starts")
    func incompleteCoverageRequiresFreshBoundary() throws {
        let epoch = UUID(uuidString: "11111111-2020-2020-2020-202020202020")!
        let p = try policy()
        var pipeline = AcceptedBatteryRangeLearningPipeline()

        _ = try pipeline.acceptBatteryObservation(
            try verifiedSOC(80, epoch: epoch, sequence: 1, uptime: 1_000),
            policy: p
        )
        try pipeline.recordDistance(deltaMeters: 150, coverage: .complete)
        try pipeline.recordDistance(deltaMeters: 50, coverage: .incomplete)
        try pipeline.recordDistance(deltaMeters: 150, coverage: .complete)

        let invalid = try pipeline.acceptBatteryObservation(
            try verifiedSOC(77, epoch: epoch, sequence: 2, uptime: 2_000),
            policy: p
        )
        #expect(invalid.candidateLearningWindow == nil)

        let newStart = try pipeline.acceptBatteryObservation(
            try verifiedSOC(76, epoch: epoch, sequence: 3, uptime: 3_000),
            policy: p
        )
        #expect(newStart.candidateLearningWindow == nil)

        try pipeline.recordDistance(deltaMeters: 300, coverage: .complete)
        let clean = try pipeline.acceptBatteryObservation(
            try verifiedSOC(73, epoch: epoch, sequence: 4, uptime: 4_000),
            policy: p
        )
        let window = try #require(clean.candidateLearningWindow)
        #expect(window.startSOC.percentage == 76)
        #expect(window.endSOC.percentage == 73)
        #expect(window.distanceMeters == 300)
        #expect(window.transportGapOccurred == false)
    }

    @Test("known battery evidence gap prevents pre-gap distance from crossing boundary")
    func batteryGapCutsLearningWindow() throws {
        let epoch = UUID(uuidString: "12121212-2020-2020-2020-202020202020")!
        let p = try policy()
        var pipeline = AcceptedBatteryRangeLearningPipeline()

        _ = try pipeline.acceptBatteryObservation(
            try verifiedSOC(80, epoch: epoch, sequence: 1, uptime: 1_000),
            policy: p
        )
        try pipeline.recordDistance(deltaMeters: 200, coverage: .complete)
        pipeline.markUnobservedInterval()
        try pipeline.recordDistance(deltaMeters: 100, coverage: .complete)

        let boundary = try pipeline.acceptBatteryObservation(
            try verifiedSOC(
                79,
                epoch: epoch,
                sequence: 2,
                uptime: 2_000,
                continuity: .afterUnobservedInterval
            ),
            policy: p
        )
        #expect(boundary.candidateLearningWindow == nil)

        try pipeline.recordDistance(deltaMeters: 300, coverage: .complete)
        let clean = try pipeline.acceptBatteryObservation(
            try verifiedSOC(76, epoch: epoch, sequence: 3, uptime: 3_000),
            policy: p
        )
        let window = try #require(clean.candidateLearningWindow)
        #expect(window.startSOC.percentage == 79)
        #expect(window.endSOC.percentage == 76)
        #expect(window.distanceMeters == 300)
        #expect(window.transportGapOccurred == false)
    }

    @Test("non-SoC sibling may establish receipt chronology before SoC from the same callback")
    func sameReceiptSiblingThenSOCAcceptsOneAnchor() throws {
        let epoch = UUID(uuidString: "20202020-2020-2020-2020-202020202020")!
        let p = try policy()
        var pipeline = AcceptedBatteryRangeLearningPipeline()

        let voltage = try pipeline.acceptBatteryObservation(
            try verifiedVoltage(36, epoch: epoch, sequence: 1, uptime: 1_000),
            policy: p
        )
        #expect(voltage.acceptedSOC == nil)
        #expect(voltage.candidateLearningWindow == nil)

        let soc = try pipeline.acceptBatteryObservation(
            try verifiedSOC(80, epoch: epoch, sequence: 1, uptime: 1_000),
            policy: p
        )
        let anchor = try #require(soc.acceptedSOC)
        #expect(anchor.sourceReceiptIdentity.sequenceNumber == 1)
        #expect(anchor.continuitySegmentStartReceiptIdentity == anchor.sourceReceiptIdentity)

        try pipeline.recordDistance(deltaMeters: 300, coverage: .complete)
        let closed = try pipeline.acceptBatteryObservation(
            try verifiedSOC(77, epoch: epoch, sequence: 2, uptime: 2_000),
            policy: p
        )
        #expect(closed.candidateLearningWindow?.distanceMeters == 300)
    }

    @Test("failed missing-boundary receipt stays consumed and cannot be replayed")
    func rejectedBoundaryAttemptCannotReenterChronology() throws {
        let epoch = UUID(uuidString: "30303030-3030-3030-3030-303030303030")!
        let p = try policy()
        var pipeline = AcceptedBatteryRangeLearningPipeline()

        _ = try pipeline.acceptBatteryObservation(
            try verifiedSOC(80, epoch: epoch, sequence: 1, uptime: 1_000),
            policy: p
        )
        try pipeline.recordDistance(deltaMeters: 200, coverage: .complete)
        pipeline.markUnobservedInterval()
        try pipeline.recordDistance(deltaMeters: 100, coverage: .complete)

        #expect(throws: BatteryEvidenceStreamValidationError.missingContinuityBoundary) {
            _ = try pipeline.acceptBatteryObservation(
                verifiedSOC(79, epoch: epoch, sequence: 2, uptime: 2_000),
                policy: p
            )
        }

        // Receipt 2 was already consumed with `.continuous` metadata when the missing-boundary
        // attempt failed. Replaying that same immutable receipt while rewriting continuity to
        // `.afterUnobservedInterval` is therefore a metadata rewrite, not a generic stale-sequence
        // replay. Keep the integration contract aligned with `BatteryEvidenceStreamValidator`.
        #expect(throws: BatteryEvidenceStreamValidationError.inconsistentReceiptMetadata) {
            _ = try pipeline.acceptBatteryObservation(
                verifiedSOC(
                    79,
                    epoch: epoch,
                    sequence: 2,
                    uptime: 2_000,
                    continuity: .afterUnobservedInterval
                ),
                policy: p
            )
        }

        let boundary = try pipeline.acceptBatteryObservation(
            try verifiedSOC(
                79,
                epoch: epoch,
                sequence: 3,
                uptime: 3_000,
                continuity: .afterUnobservedInterval
            ),
            policy: p
        )
        #expect(boundary.acceptedSOC?.percentage == 79)
        #expect(boundary.candidateLearningWindow == nil)

        try pipeline.recordDistance(deltaMeters: 300, coverage: .complete)
        let clean = try pipeline.acceptBatteryObservation(
            try verifiedSOC(76, epoch: epoch, sequence: 4, uptime: 4_000),
            policy: p
        )
        let window = try #require(clean.candidateLearningWindow)
        #expect(window.startSOC.percentage == 79)
        #expect(window.endSOC.percentage == 76)
        #expect(window.distanceMeters == 300)
        #expect(window.transportGapOccurred == false)
    }

    @Test("unverified observations are rejected before adaptive-range authority")
    func unverifiedObservationRejected() throws {
        let epoch = UUID(uuidString: "40404040-4040-4040-4040-404040404040")!
        let p = try policy()
        var pipeline = AcceptedBatteryRangeLearningPipeline()
        let receipt = BatteryEvidenceReceiptIdentity(acquisitionEpoch: epoch, sequenceNumber: 1)
        let unverified = try BatteryEvidenceObservation(
            value: .stateOfChargePercent(80),
            role: .publicReference,
            receiptIdentity: receipt,
            receivedAtUptimeNanoseconds: 1_000,
            receivedAtDate: Date(timeIntervalSinceReferenceDate: 1),
            continuity: .continuous
        )

        #expect(throws: AdaptiveBatteryRangeLiveTruthError.notVerifiedStateOfCharge) {
            _ = try pipeline.acceptBatteryObservation(unverified, policy: p)
        }
    }

    private func policy() throws -> AdaptiveBatteryRangePolicy {
        try AdaptiveBatteryRangePolicy(
            minimumConsumedPercentagePoints: 2,
            minimumDistanceMeters: 100,
            recentWindowCapacity: 4,
            recentWeight: 0.5,
            outlierLowerEfficiencyRatio: 0.5,
            outlierUpperEfficiencyRatio: 2,
            estimateDeadbandFraction: 0,
            estimateSmoothingFactor: 1,
            provisionalEfficiencyMetersPerPercentagePoint: 100,
            lowConfidenceConsumedPercentagePoints: 5,
            normalConfidenceConsumedPercentagePoints: 10,
            highConfidenceConsumedPercentagePoints: 20
        )
    }

    private func verifiedSOC(
        _ percentage: Double,
        epoch: UUID,
        sequence: UInt64,
        uptime: UInt64,
        continuity: BatteryEvidenceContinuity = .continuous
    ) throws -> BatteryEvidenceObservation {
        try BatteryEvidenceObservation(
            value: .stateOfChargePercent(percentage),
            role: .verifiedVehicleMeasurement,
            receiptIdentity: BatteryEvidenceReceiptIdentity(
                acquisitionEpoch: epoch,
                sequenceNumber: sequence
            ),
            receivedAtUptimeNanoseconds: uptime,
            receivedAtDate: Date(timeIntervalSinceReferenceDate: Double(uptime) / 1_000),
            continuity: continuity
        )
    }

    private func verifiedVoltage(
        _ volts: Double,
        epoch: UUID,
        sequence: UInt64,
        uptime: UInt64,
        continuity: BatteryEvidenceContinuity = .continuous
    ) throws -> BatteryEvidenceObservation {
        try BatteryEvidenceObservation(
            value: .voltageVolts(volts),
            role: .verifiedVehicleMeasurement,
            receiptIdentity: BatteryEvidenceReceiptIdentity(
                acquisitionEpoch: epoch,
                sequenceNumber: sequence
            ),
            receivedAtUptimeNanoseconds: uptime,
            receivedAtDate: Date(timeIntervalSinceReferenceDate: Double(uptime) / 1_000),
            continuity: continuity
        )
    }
}
