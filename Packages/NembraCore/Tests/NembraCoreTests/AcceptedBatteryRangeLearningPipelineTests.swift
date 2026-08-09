import Foundation
import Testing
@testable import NembraCore

@Suite("Accepted battery range learning pipeline")
struct AcceptedBatteryRangeLearningPipelineTests {
    private func policy(
        minimumConsumedPercentagePoints: Double = 3,
        minimumDistanceMeters: Double = 300
    ) throws -> AdaptiveBatteryRangePolicy {
        try AdaptiveBatteryRangePolicy(
            minimumConsumedPercentagePoints: minimumConsumedPercentagePoints,
            minimumDistanceMeters: minimumDistanceMeters,
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
        value: BatterySemanticValue,
        role: BatteryEvidenceRole,
        epoch: UUID,
        sequence: UInt64,
        uptime: UInt64,
        continuity: BatteryEvidenceContinuity = .continuous
    ) throws -> BatteryEvidenceObservation {
        try BatteryEvidenceObservation(
            value: value,
            role: role,
            receiptIdentity: BatteryEvidenceReceiptIdentity(
                acquisitionEpoch: epoch,
                sequenceNumber: sequence
            ),
            receivedAtUptimeNanoseconds: uptime,
            receivedAtDate: Date(timeIntervalSinceReferenceDate: Double(sequence)),
            continuity: continuity
        )
    }

    private func verifiedSOC(
        _ percentage: Double,
        epoch: UUID,
        sequence: UInt64,
        uptime: UInt64,
        continuity: BatteryEvidenceContinuity = .continuous
    ) throws -> BatteryEvidenceObservation {
        try observation(
            value: .stateOfChargePercent(percentage),
            role: .verifiedVehicleMeasurement,
            epoch: epoch,
            sequence: sequence,
            uptime: uptime,
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
        try observation(
            value: .voltageVolts(volts),
            role: .verifiedVehicleMeasurement,
            epoch: epoch,
            sequence: sequence,
            uptime: uptime,
            continuity: continuity
        )
    }

    @Test("verified same-segment chronology emits a receipt-bound candidate")
    func verifiedChronologyEmitsAcceptedWindow() throws {
        let epoch = UUID(uuidString: "10101010-1010-1010-1010-101010101010")!
        let p = try policy()
        var pipeline = AcceptedBatteryRangeLearningPipeline()

        let startResult = try pipeline.acceptBatteryObservation(
            try verifiedSOC(80, epoch: epoch, sequence: 1, uptime: 1_000),
            policy: p
        )
        let start = try #require(startResult.acceptedSOC)
        #expect(startResult.candidateLearningWindow == nil)

        try pipeline.recordDistance(deltaMeters: 360, coverage: .complete)
        let endResult = try pipeline.acceptBatteryObservation(
            try verifiedSOC(77, epoch: epoch, sequence: 2, uptime: 2_000),
            policy: p
        )
        let window = try #require(endResult.candidateLearningWindow)

        #expect(window.startSOC == start)
        #expect(window.endSOC == endResult.acceptedSOC)
        #expect(window.startSOC.continuitySegmentStartReceiptIdentity == start.sourceReceiptIdentity)
        #expect(window.endSOC.continuitySegmentStartReceiptIdentity == start.sourceReceiptIdentity)
        #expect(window.distanceMeters == 360)
        #expect(window.distanceCoverage == .complete)
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

        #expect(throws: BatteryEvidenceStreamValidationError.staleReceiptIdentity) {
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

    @Test("continuity boundary on a non-SoC sibling resets pre-boundary range evidence")
    func nonSOCBoundaryResetsRangeSpan() throws {
        let epoch = UUID(uuidString: "40404040-4040-4040-4040-404040404040")!
        let p = try policy()
        var pipeline = AcceptedBatteryRangeLearningPipeline()

        _ = try pipeline.acceptBatteryObservation(
            try verifiedSOC(80, epoch: epoch, sequence: 1, uptime: 1_000),
            policy: p
        )
        try pipeline.recordDistance(deltaMeters: 200, coverage: .complete)

        let boundaryVoltage = try pipeline.acceptBatteryObservation(
            try verifiedVoltage(
                36,
                epoch: epoch,
                sequence: 2,
                uptime: 2_000,
                continuity: .afterUnobservedInterval
            ),
            policy: p
        )
        #expect(boundaryVoltage.acceptedSOC == nil)

        let boundarySOC = try pipeline.acceptBatteryObservation(
            try verifiedSOC(
                79,
                epoch: epoch,
                sequence: 2,
                uptime: 2_000,
                continuity: .afterUnobservedInterval
            ),
            policy: p
        )
        #expect(boundarySOC.acceptedSOC?.percentage == 79)
        #expect(boundarySOC.candidateLearningWindow == nil)

        try pipeline.recordDistance(deltaMeters: 300, coverage: .complete)
        let clean = try pipeline.acceptBatteryObservation(
            try verifiedSOC(76, epoch: epoch, sequence: 3, uptime: 3_000),
            policy: p
        )
        let window = try #require(clean.candidateLearningWindow)
        #expect(window.startSOC.percentage == 79)
        #expect(window.distanceMeters == 300)
        #expect(window.transportGapOccurred == false)
    }

    @Test("non-authoritative SoC can advance chronology but cannot establish learned-range authority")
    func nonAuthoritativeSOCNeverAnchors() throws {
        let epoch = UUID(uuidString: "50505050-5050-5050-5050-505050505050")!
        let p = try policy()
        var pipeline = AcceptedBatteryRangeLearningPipeline()

        let estimated = try pipeline.acceptBatteryObservation(
            try observation(
                value: .stateOfChargePercent(81),
                role: .derivedEstimate,
                epoch: epoch,
                sequence: 1,
                uptime: 1_000
            ),
            policy: p
        )
        #expect(estimated.acceptedSOC == nil)
        #expect(estimated.candidateLearningWindow == nil)

        try pipeline.recordDistance(deltaMeters: 500, coverage: .partial)
        let verified = try pipeline.acceptBatteryObservation(
            try verifiedSOC(80, epoch: epoch, sequence: 2, uptime: 2_000),
            policy: p
        )
        #expect(verified.acceptedSOC?.percentage == 80)
        #expect(verified.candidateLearningWindow == nil)

        try pipeline.recordDistance(deltaMeters: 300, coverage: .complete)
        let closed = try pipeline.acceptBatteryObservation(
            try verifiedSOC(77, epoch: epoch, sequence: 3, uptime: 3_000),
            policy: p
        )
        let window = try #require(closed.candidateLearningWindow)
        #expect(window.distanceMeters == 300)
        #expect(window.distanceCoverage == .complete)
    }

    @Test("unknown distance coverage survives into accepted candidate and model rejection")
    func unknownCoverageFailsClosedAtModel() throws {
        let epoch = UUID(uuidString: "60606060-6060-6060-6060-606060606060")!
        let p = try policy()
        var pipeline = AcceptedBatteryRangeLearningPipeline()

        _ = try pipeline.acceptBatteryObservation(
            try verifiedSOC(80, epoch: epoch, sequence: 1, uptime: 1_000),
            policy: p
        )
        try pipeline.recordDistance(deltaMeters: 300)
        let result = try pipeline.acceptBatteryObservation(
            try verifiedSOC(77, epoch: epoch, sequence: 2, uptime: 2_000),
            policy: p
        )
        let window = try #require(result.candidateLearningWindow)
        #expect(window.distanceCoverage == .unknown)

        var model = AcceptedAdaptiveBatteryRangeModel()
        let plausibility = try AcceptedAdaptiveRangePlausibilityPolicy(
            maximumFullChargeEquivalentMeters: 20_000
        )
        let learned = model.ingest(
            window,
            policy: p,
            plausibilityPolicy: plausibility
        )
        #expect(learned.disposition == .rejected(.incompleteDistanceEvidence))
        #expect(model.acceptedWindowCount == 0)
    }

    @Test("explicit transport-gap evidence remains sticky in the accepted candidate")
    func transportGapRemainsSticky() throws {
        let epoch = UUID(uuidString: "70707070-7070-7070-7070-707070707070")!
        let p = try policy()
        var pipeline = AcceptedBatteryRangeLearningPipeline()

        _ = try pipeline.acceptBatteryObservation(
            try verifiedSOC(80, epoch: epoch, sequence: 1, uptime: 1_000),
            policy: p
        )
        try pipeline.recordDistance(deltaMeters: 300, coverage: .complete)
        pipeline.recordTransportGap()

        let result = try pipeline.acceptBatteryObservation(
            try verifiedSOC(77, epoch: epoch, sequence: 2, uptime: 2_000),
            policy: p
        )
        let window = try #require(result.candidateLearningWindow)
        #expect(window.transportGapOccurred)
    }

    @Test("measured SoC rebound rebases and discards earlier distance evidence")
    func reboundRebasesAcceptedSpan() throws {
        let epoch = UUID(uuidString: "80808080-8080-8080-8080-808080808080")!
        let p = try policy(minimumConsumedPercentagePoints: 3, minimumDistanceMeters: 1_000)
        var pipeline = AcceptedBatteryRangeLearningPipeline()

        _ = try pipeline.acceptBatteryObservation(
            try verifiedSOC(80, epoch: epoch, sequence: 1, uptime: 1_000),
            policy: p
        )
        try pipeline.recordDistance(deltaMeters: 200, coverage: .partial)
        #expect(try pipeline.acceptBatteryObservation(
            verifiedSOC(77, epoch: epoch, sequence: 2, uptime: 2_000),
            policy: p
        ).candidateLearningWindow == nil)

        #expect(try pipeline.acceptBatteryObservation(
            verifiedSOC(79, epoch: epoch, sequence: 3, uptime: 3_000),
            policy: p
        ).candidateLearningWindow == nil)

        try pipeline.recordDistance(deltaMeters: 1_000, coverage: .complete)
        let result = try pipeline.acceptBatteryObservation(
            try verifiedSOC(76, epoch: epoch, sequence: 4, uptime: 4_000),
            policy: p
        )
        let window = try #require(result.candidateLearningWindow)
        #expect(window.startSOC.percentage == 79)
        #expect(window.endSOC.percentage == 76)
        #expect(window.distanceMeters == 1_000)
        #expect(window.distanceCoverage == .complete)
    }

    @Test("distinct accepted receipts may share one uptime tick without corrupting sequence chronology")
    func equalUptimeDistinctReceiptsDeferSafely() throws {
        let epoch = UUID(uuidString: "90909090-9090-9090-9090-909090909090")!
        let p = try policy()
        var pipeline = AcceptedBatteryRangeLearningPipeline()

        _ = try pipeline.acceptBatteryObservation(
            try verifiedSOC(80, epoch: epoch, sequence: 1, uptime: 1_000),
            policy: p
        )
        try pipeline.recordDistance(deltaMeters: 100, coverage: .complete)
        let sameTick = try pipeline.acceptBatteryObservation(
            try verifiedSOC(79, epoch: epoch, sequence: 2, uptime: 1_000),
            policy: p
        )
        #expect(sameTick.acceptedSOC?.sourceReceiptIdentity.sequenceNumber == 2)
        #expect(sameTick.candidateLearningWindow == nil)

        try pipeline.recordDistance(deltaMeters: 200, coverage: .complete)
        let result = try pipeline.acceptBatteryObservation(
            try verifiedSOC(77, epoch: epoch, sequence: 3, uptime: 2_000),
            policy: p
        )
        let window = try #require(result.candidateLearningWindow)
        #expect(window.startSOC.percentage == 80)
        #expect(window.endSOC.percentage == 77)
        #expect(window.distanceMeters == 300)
    }

    @Test("invalid distance evidence cannot partially mutate the ephemeral range span")
    func invalidDistanceIsRangeAtomic() throws {
        let epoch = UUID(uuidString: "A0A0A0A0-A0A0-A0A0-A0A0-A0A0A0A0A0A0")!
        let p = try policy()
        var pipeline = AcceptedBatteryRangeLearningPipeline()

        _ = try pipeline.acceptBatteryObservation(
            try verifiedSOC(80, epoch: epoch, sequence: 1, uptime: 1_000),
            policy: p
        )
        let before = pipeline
        #expect(throws: BatteryRangeWindowAssemblyError.invalidDistanceDelta) {
            try pipeline.recordDistance(deltaMeters: -1, coverage: .complete)
        }
        #expect(pipeline.hasSameInternalRangeState(as: before))

        try pipeline.recordDistance(deltaMeters: 300, coverage: .complete)
        let result = try pipeline.acceptBatteryObservation(
            try verifiedSOC(77, epoch: epoch, sequence: 2, uptime: 2_000),
            policy: p
        )
        #expect(result.candidateLearningWindow?.distanceMeters == 300)
    }
}
