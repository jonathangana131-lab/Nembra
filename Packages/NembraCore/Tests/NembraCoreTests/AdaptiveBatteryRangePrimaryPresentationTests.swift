import Testing
@testable import NembraCore

@Suite("Adaptive battery range primary presentation")
struct AdaptiveBatteryRangePrimaryPresentationTests {
    private let policy = AdaptiveBatteryRangePrimaryPresentationPolicy()

    private func estimate(
        presentedRemainingMeters: Double = 1_200,
        basis: AdaptiveRangeEstimateBasis = .learned,
        confidence: AdaptiveRangeConfidence = .normal,
        socProvenance: BatterySOCProvenance = .authoritativeMeasurement,
        lowSOCConservatismApplied: Bool = false
    ) -> AdaptiveBatteryRangeEstimate {
        AdaptiveBatteryRangeEstimate(
            rawRemainingMeters: 1_500,
            presentedRemainingMeters: presentedRemainingMeters,
            metersPerPercentagePoint: 100,
            basis: basis,
            confidence: confidence,
            socProvenance: socProvenance,
            lowSOCConservatismApplied: lowSOCConservatismApplied
        )
    }

    @Test("learned normal-confidence live range may reach the primary readout")
    func learnedNormalLiveRangeIsEligible() {
        let decision = policy.resolve(
            estimate: estimate(presentedRemainingMeters: 1_234),
            vehicleAvailability: .live
        )

        #expect(decision == .valueMeters(1_234))
        #expect(decision.primaryReadoutDisplay == .valueMeters(1_234))
    }

    @Test("high confidence remains eligible and preserves model presentation smoothing")
    func highConfidenceUsesPresentedValue() {
        let decision = policy.resolve(
            estimate: estimate(
                presentedRemainingMeters: 900,
                confidence: .high,
                lowSOCConservatismApplied: true
            ),
            vehicleAvailability: .live
        )

        #expect(decision == .valueMeters(900))
    }

    @Test("zero remaining range is a legitimate numeric endpoint")
    func zeroRangeIsEligible() {
        let decision = policy.resolve(
            estimate: estimate(presentedRemainingMeters: 0, confidence: .high),
            vehicleAvailability: .live
        )

        #expect(decision == .valueMeters(0))
    }

    @Test("provisional cold-start range stays learning instead of becoming learned-looking mileage")
    func provisionalSeedIsWithheld() {
        let decision = policy.resolve(
            estimate: estimate(basis: .provisionalSeed, confidence: .learning),
            vehicleAvailability: .live
        )

        #expect(decision == .learning(.provisionalSeed))
        #expect(decision.primaryReadoutDisplay == .learning)
    }

    @Test("learning confidence stays learning")
    func learningConfidenceIsWithheld() {
        let decision = policy.resolve(
            estimate: estimate(confidence: .learning),
            vehicleAvailability: .live
        )

        #expect(decision == .learning(.learningConfidence))
    }

    @Test("low confidence requires a qualifier before numeric presentation")
    func lowConfidenceIsWithheld() {
        let decision = policy.resolve(
            estimate: estimate(confidence: .low),
            vehicleAvailability: .live
        )

        #expect(decision == .learning(.lowConfidenceRequiresQualifier))
    }

    @Test("estimated SoC cannot become an unqualified numeric range")
    func estimatedSOCIsWithheld() {
        let decision = policy.resolve(
            estimate: estimate(confidence: .high, socProvenance: .estimate),
            vehicleAvailability: .live
        )

        #expect(decision == .unavailable(.estimatedSOCRequiresQualifier))
        #expect(decision.primaryReadoutDisplay == .unavailable)
    }

    @Test("retained vehicle data cannot masquerade as a live numeric range")
    func retainedVehicleDataIsWithheld() {
        let decision = policy.resolve(
            estimate: estimate(confidence: .high),
            vehicleAvailability: .retained
        )

        #expect(decision == .unavailable(.retainedVehicleDataRequiresQualifier))
    }

    @Test("unavailable vehicle data dominates a stale estimate")
    func unavailableVehicleDataIsWithheld() {
        let decision = policy.resolve(
            estimate: estimate(confidence: .high),
            vehicleAvailability: .unavailable
        )

        #expect(decision == .unavailable(.vehicleDataUnavailable))
    }

    @Test("missing estimate fails closed")
    func missingEstimateIsUnavailable() {
        let decision = policy.resolve(
            estimate: nil,
            vehicleAvailability: .live
        )

        #expect(decision == .unavailable(.noEstimate))
    }

    @Test("invalid smoothed range fails closed instead of leaking through presentation")
    func invalidPresentedRangeIsUnavailable() {
        let negative = policy.resolve(
            estimate: estimate(presentedRemainingMeters: -1, confidence: .high),
            vehicleAvailability: .live
        )
        let nonFinite = policy.resolve(
            estimate: estimate(presentedRemainingMeters: .infinity, confidence: .high),
            vehicleAvailability: .live
        )

        #expect(negative == .unavailable(.invalidPresentedRange))
        #expect(nonFinite == .unavailable(.invalidPresentedRange))
    }
}
