import Foundation
import Testing
@testable import NembraCore

@Suite("Accepted adaptive battery range model")
struct AcceptedAdaptiveBatteryRangeModelTests {
    @Test("trusted same-segment receipt window teaches only with evidence-backed first-window ceiling")
    func trustedWindowTeachesAcceptedModel() throws {
        let epoch = UUID(uuidString: "77777777-7777-7777-7777-777777777777")!
        var stream = AcceptedBatterySOCStream()
        let start = try #require(stream.accept(
            try verifiedSOC(percent: 80, epoch: epoch, sequence: 1, uptime: 1_000)
        ))
        let end = try #require(stream.accept(
            try verifiedSOC(percent: 70, epoch: epoch, sequence: 2, uptime: 2_000)
        ))

        #expect(start.continuitySegmentStartReceiptIdentity == start.sourceReceiptIdentity)
        #expect(end.continuitySegmentStartReceiptIdentity == start.sourceReceiptIdentity)

        let window = try AcceptedBatteryRangeLearningWindow(
            distanceMeters: 1_200,
            distanceCoverage: .complete,
            transportGapOccurred: false,
            startSOC: start,
            endSOC: end
        )
        let plausibility = try AcceptedAdaptiveRangePlausibilityPolicy(
            maximumFullChargeEquivalentMeters: 20_000
        )
        var model = AcceptedAdaptiveBatteryRangeModel()
        let result = model.ingest(
            window,
            policy: try policy(),
            plausibilityPolicy: plausibility
        )

        #expect(window.transportGapOccurred == false)
        #expect(result.disposition == .accepted)
        #expect(model.hasLearnedEfficiency)
        #expect(model.historicalConsumedPercentagePoints == 10)
        #expect(model.acceptedWindowCount == 1)
        #expect(model.typicalFullChargeRangeMeters(using: try policy()) == 12_000)
    }

    @Test("deferred plausibility policy never teaches from the lone first production window")
    func firstWindowDefersWithoutPlausibilityEvidence() throws {
        let epoch = UUID(uuidString: "77777777-7777-7777-7777-777777777778")!
        var stream = AcceptedBatterySOCStream()
        let start = try #require(stream.accept(
            try verifiedSOC(percent: 80, epoch: epoch, sequence: 1, uptime: 1_000)
        ))
        let end = try #require(stream.accept(
            try verifiedSOC(percent: 70, epoch: epoch, sequence: 2, uptime: 2_000)
        ))
        let window = try AcceptedBatteryRangeLearningWindow(
            distanceMeters: 1_200,
            distanceCoverage: .complete,
            transportGapOccurred: false,
            startSOC: start,
            endSOC: end
        )
        var model = AcceptedAdaptiveBatteryRangeModel()

        let result = model.ingest(
            window,
            policy: try policy(),
            plausibilityPolicy: .deferredUntilVerifiedEvidence
        )

        #expect(result.disposition == .deferred(.firstWindowPlausibilityUnverified))
        #expect(result.sample == nil)
        #expect(result.confidence == .learning)
        #expect(model.hasLearnedEfficiency == false)
        #expect(model.historicalConsumedPercentagePoints == 0)
        #expect(model.acceptedWindowCount == 0)
        #expect(model.typicalFullChargeRangeMeters(using: try policy()) == nil)
    }

    @Test("deferred absolute ceiling is allowed after accepted history exists")
    func learnedHistoryCanContinueWithRelativeOutlierPolicy() throws {
        let epoch = UUID(uuidString: "77777777-7777-7777-7777-777777777779")!
        var stream = AcceptedBatterySOCStream()
        let firstStart = try #require(stream.accept(
            try verifiedSOC(percent: 90, epoch: epoch, sequence: 1, uptime: 1_000)
        ))
        let firstEnd = try #require(stream.accept(
            try verifiedSOC(percent: 80, epoch: epoch, sequence: 2, uptime: 2_000)
        ))
        let firstWindow = try AcceptedBatteryRangeLearningWindow(
            distanceMeters: 1_000,
            distanceCoverage: .complete,
            transportGapOccurred: false,
            startSOC: firstStart,
            endSOC: firstEnd
        )
        let initialCeiling = try AcceptedAdaptiveRangePlausibilityPolicy(
            maximumFullChargeEquivalentMeters: 20_000
        )
        var model = AcceptedAdaptiveBatteryRangeModel()
        #expect(model.ingest(
            firstWindow,
            policy: try policy(),
            plausibilityPolicy: initialCeiling
        ).disposition == .accepted)

        let secondStart = try #require(stream.accept(
            try verifiedSOC(percent: 80, epoch: epoch, sequence: 3, uptime: 3_000)
        ))
        let secondEnd = try #require(stream.accept(
            try verifiedSOC(percent: 70, epoch: epoch, sequence: 4, uptime: 4_000)
        ))
        let secondWindow = try AcceptedBatteryRangeLearningWindow(
            distanceMeters: 1_050,
            distanceCoverage: .complete,
            transportGapOccurred: false,
            startSOC: secondStart,
            endSOC: secondEnd
        )

        let result = model.ingest(
            secondWindow,
            policy: try policy(),
            plausibilityPolicy: .deferredUntilVerifiedEvidence
        )

        #expect(result.disposition == .accepted)
        #expect(model.acceptedWindowCount == 2)
        #expect(model.historicalConsumedPercentagePoints == 20)
    }

    @Test("evidence-backed plausibility ceiling rejects an absurd first window before baseline learning")
    func firstWindowPlausibilityCeilingRejectsExtremeEvidence() throws {
        let epoch = UUID(uuidString: "78787878-7878-7878-7878-787878787878")!
        var stream = AcceptedBatterySOCStream()
        let start = try #require(stream.accept(
            try verifiedSOC(percent: 80, epoch: epoch, sequence: 1, uptime: 1_000)
        ))
        let end = try #require(stream.accept(
            try verifiedSOC(percent: 70, epoch: epoch, sequence: 2, uptime: 2_000)
        ))
        let window = try AcceptedBatteryRangeLearningWindow(
            distanceMeters: 100_000,
            distanceCoverage: .complete,
            transportGapOccurred: false,
            startSOC: start,
            endSOC: end
        )
        let plausibility = try AcceptedAdaptiveRangePlausibilityPolicy(
            maximumFullChargeEquivalentMeters: 20_000
        )
        var model = AcceptedAdaptiveBatteryRangeModel()

        let result = model.ingest(
            window,
            policy: try policy(),
            plausibilityPolicy: plausibility
        )

        #expect(result.disposition == .rejected(.efficiencyOutlier))
        #expect(model.hasLearnedEfficiency == false)
        #expect(model.historicalConsumedPercentagePoints == 0)
        #expect(model.acceptedWindowCount == 0)
    }

    @Test("non-finite full-charge equivalent stays numerical overflow rather than plausibility outlier")
    func plausibilityOverflowRetainsNumericalClassification() throws {
        let epoch = UUID(uuidString: "78787878-7878-7878-7878-787878787879")!
        var stream = AcceptedBatterySOCStream()
        let start = try #require(stream.accept(
            try verifiedSOC(percent: 80, epoch: epoch, sequence: 1, uptime: 1_000)
        ))
        let end = try #require(stream.accept(
            try verifiedSOC(percent: 70, epoch: epoch, sequence: 2, uptime: 2_000)
        ))
        let window = try AcceptedBatteryRangeLearningWindow(
            distanceMeters: .greatestFiniteMagnitude,
            distanceCoverage: .complete,
            transportGapOccurred: false,
            startSOC: start,
            endSOC: end
        )
        let plausibility = try AcceptedAdaptiveRangePlausibilityPolicy(
            maximumFullChargeEquivalentMeters: 20_000
        )
        var model = AcceptedAdaptiveBatteryRangeModel()

        let result = model.ingest(
            window,
            policy: try policy(),
            plausibilityPolicy: plausibility
        )

        #expect(result.disposition == .rejected(.numericalOverflow))
        #expect(model.hasLearnedEfficiency == false)
        #expect(model.acceptedWindowCount == 0)
    }

    @Test("plausibility ceiling accepts an otherwise-valid window exactly at its bound")
    func firstWindowPlausibilityCeilingAcceptsBoundary() throws {
        let epoch = UUID(uuidString: "79797979-7979-7979-7979-797979797979")!
        var stream = AcceptedBatterySOCStream()
        let start = try #require(stream.accept(
            try verifiedSOC(percent: 80, epoch: epoch, sequence: 1, uptime: 1_000)
        ))
        let end = try #require(stream.accept(
            try verifiedSOC(percent: 70, epoch: epoch, sequence: 2, uptime: 2_000)
        ))
        let window = try AcceptedBatteryRangeLearningWindow(
            distanceMeters: 2_000,
            distanceCoverage: .complete,
            transportGapOccurred: false,
            startSOC: start,
            endSOC: end
        )
        let plausibility = try AcceptedAdaptiveRangePlausibilityPolicy(
            maximumFullChargeEquivalentMeters: 20_000
        )
        var model = AcceptedAdaptiveBatteryRangeModel()

        let result = model.ingest(
            window,
            policy: try policy(),
            plausibilityPolicy: plausibility
        )

        #expect(result.disposition == .accepted)
        #expect(model.hasLearnedEfficiency)
        #expect(model.typicalFullChargeRangeMeters(using: try policy()) == 20_000)
    }

    @Test("plausibility ceiling itself is finite and positive")
    func invalidPlausibilityCeilingRejected() {
        #expect(throws: AcceptedAdaptiveRangeValidationError.invalidPlausibilityPolicy) {
            _ = try AcceptedAdaptiveRangePlausibilityPolicy(
                maximumFullChargeEquivalentMeters: 0
            )
        }
        #expect(throws: AcceptedAdaptiveRangeValidationError.invalidPlausibilityPolicy) {
            _ = try AcceptedAdaptiveRangePlausibilityPolicy(
                maximumFullChargeEquivalentMeters: .infinity
            )
        }
    }

    @Test("direct post-gap boundary forces learning window transport gap")
    func postGapBoundaryForcesGap() throws {
        let epoch = UUID(uuidString: "88888888-8888-8888-8888-888888888888")!
        var stream = AcceptedBatterySOCStream()
        let start = try #require(stream.accept(
            try verifiedSOC(percent: 80, epoch: epoch, sequence: 1, uptime: 1_000)
        ))

        stream.markUnobservedInterval()
        let end = try #require(stream.accept(
            try verifiedSOC(
                percent: 70,
                epoch: epoch,
                sequence: 2,
                uptime: 2_000,
                continuity: .afterUnobservedInterval
            )
        ))

        #expect(start.continuitySegmentStartReceiptIdentity != end.continuitySegmentStartReceiptIdentity)

        let window = try AcceptedBatteryRangeLearningWindow(
            distanceMeters: 1_200,
            distanceCoverage: .complete,
            transportGapOccurred: false,
            startSOC: start,
            endSOC: end
        )
        var model = AcceptedAdaptiveBatteryRangeModel()
        let result = model.ingest(
            window,
            policy: try policy(),
            plausibilityPolicy: .deferredUntilVerifiedEvidence
        )

        #expect(window.transportGapOccurred)
        #expect(result.disposition == .rejected(.transportGap))
        #expect(model.hasLearnedEfficiency == false)
        #expect(model.acceptedWindowCount == 0)
    }

    @Test("intermediate boundary cannot be hidden by later continuous endpoint")
    func hiddenIntermediateGapTaintsWholeSpan() throws {
        let epoch = UUID(uuidString: "89898989-8989-8989-8989-898989898989")!
        var stream = AcceptedBatterySOCStream()
        let start = try #require(stream.accept(
            try verifiedSOC(percent: 80, epoch: epoch, sequence: 1, uptime: 1_000)
        ))

        stream.markUnobservedInterval()
        let boundary = try #require(stream.accept(
            try verifiedSOC(
                percent: 75,
                epoch: epoch,
                sequence: 2,
                uptime: 2_000,
                continuity: .afterUnobservedInterval
            )
        ))
        let end = try #require(stream.accept(
            try verifiedSOC(percent: 70, epoch: epoch, sequence: 3, uptime: 3_000)
        ))

        #expect(boundary.continuitySegmentStartReceiptIdentity == boundary.sourceReceiptIdentity)
        #expect(end.continuity == .continuous)
        #expect(end.continuitySegmentStartReceiptIdentity == boundary.sourceReceiptIdentity)
        #expect(start.continuitySegmentStartReceiptIdentity != end.continuitySegmentStartReceiptIdentity)

        let window = try AcceptedBatteryRangeLearningWindow(
            distanceMeters: 1_200,
            distanceCoverage: .complete,
            transportGapOccurred: false,
            startSOC: start,
            endSOC: end
        )
        var model = AcceptedAdaptiveBatteryRangeModel()
        let result = model.ingest(
            window,
            policy: try policy(),
            plausibilityPolicy: .deferredUntilVerifiedEvidence
        )

        #expect(window.transportGapOccurred)
        #expect(result.disposition == .rejected(.transportGap))
        #expect(model.acceptedWindowCount == 0)
    }

    @Test("one-off current anchors cannot masquerade as span-proven learning evidence")
    func unsegmentedCurrentAnchorsRejectedForLearning() throws {
        let epoch = UUID(uuidString: "90909090-9090-9090-9090-909090909090")!
        var validator = BatteryEvidenceStreamValidator()
        let startObservation = try verifiedSOC(percent: 80, epoch: epoch, sequence: 1, uptime: 1_000)
        try validator.accept(startObservation)
        let start = try AcceptedBatterySOCAnchor.current(
            observation: startObservation,
            acceptedBy: validator
        )
        let endObservation = try verifiedSOC(percent: 70, epoch: epoch, sequence: 2, uptime: 2_000)
        try validator.accept(endObservation)
        let end = try AcceptedBatterySOCAnchor.current(
            observation: endObservation,
            acceptedBy: validator
        )

        #expect(start.continuitySegmentStartReceiptIdentity == nil)
        #expect(end.continuitySegmentStartReceiptIdentity == nil)
        #expect(throws: AcceptedAdaptiveRangeValidationError.missingContinuitySegmentIdentity) {
            _ = try AcceptedBatteryRangeLearningWindow(
                distanceMeters: 1_200,
                distanceCoverage: .complete,
                transportGapOccurred: false,
                startSOC: start,
                endSOC: end
            )
        }
    }

    @Test("window rejects cross-acquisition anchors")
    func crossAcquisitionRejected() throws {
        var firstStream = AcceptedBatterySOCStream()
        let start = try #require(firstStream.accept(
            try verifiedSOC(
                percent: 80,
                epoch: UUID(uuidString: "99999999-9999-9999-9999-999999999999")!,
                sequence: 1,
                uptime: 1_000
            )
        ))

        var secondStream = AcceptedBatterySOCStream()
        let end = try #require(secondStream.accept(
            try verifiedSOC(
                percent: 70,
                epoch: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
                sequence: 1,
                uptime: 2_000
            )
        ))

        #expect(throws: AcceptedAdaptiveRangeValidationError.acquisitionEpochChanged) {
            _ = try AcceptedBatteryRangeLearningWindow(
                distanceMeters: 1_200,
                distanceCoverage: .complete,
                transportGapOccurred: false,
                startSOC: start,
                endSOC: end
            )
        }
    }

    @Test("window rejects invalid distance before it can reach learned history")
    func invalidDistanceRejected() throws {
        let epoch = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        var stream = AcceptedBatterySOCStream()
        let start = try #require(stream.accept(
            try verifiedSOC(percent: 80, epoch: epoch, sequence: 1, uptime: 1_000)
        ))
        let end = try #require(stream.accept(
            try verifiedSOC(percent: 70, epoch: epoch, sequence: 2, uptime: 2_000)
        ))

        #expect(throws: AcceptedAdaptiveRangeValidationError.invalidDistance) {
            _ = try AcceptedBatteryRangeLearningWindow(
                distanceMeters: .nan,
                distanceCoverage: .complete,
                transportGapOccurred: false,
                startSOC: start,
                endSOC: end
            )
        }
    }

    @Test("accepted wrapper estimates only while receipt-bound SoC is current")
    func acceptedWrapperProducesReceiptBoundEstimate() throws {
        let epoch = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        var stream = AcceptedBatterySOCStream()
        let soc = try #require(stream.accept(
            try verifiedSOC(percent: 50, epoch: epoch, sequence: 1, uptime: 5_000)
        ))
        let model = AcceptedAdaptiveBatteryRangeModel()
        let rangePolicy = try policy(provisional: 100)
        let live = try #require(
            model.estimateRemainingRange(
                atAcceptedSOC: soc,
                acceptedBy: stream.validator,
                policy: rangePolicy
            )
        )

        #expect(live.estimate.rawRemainingMeters == 5_000)
        #expect(live.isCurrent(in: stream.validator))

        stream.markUnobservedInterval()
        #expect(live.isCurrent(in: stream.validator) == false)
        #expect(model.estimateRemainingRange(
            atAcceptedSOC: soc,
            acceptedBy: stream.validator,
            policy: rangePolicy
        ) == nil)
    }

    private func policy(provisional: Double? = nil) throws -> AdaptiveBatteryRangePolicy {
        try AdaptiveBatteryRangePolicy(
            minimumConsumedPercentagePoints: 5,
            minimumDistanceMeters: 100,
            recentWindowCapacity: 4,
            recentWeight: 0.5,
            outlierLowerEfficiencyRatio: 0.5,
            outlierUpperEfficiencyRatio: 2,
            estimateDeadbandFraction: 0,
            estimateSmoothingFactor: 1,
            provisionalEfficiencyMetersPerPercentagePoint: provisional,
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
        try BatteryEvidenceObservation(
            value: .stateOfChargePercent(percent),
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
