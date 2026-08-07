import Testing
@testable import NembraCore

@Suite("Adaptive battery range primary presentation")
struct AdaptiveBatteryRangePrimaryPresentationTests {
    private let policy = AdaptiveBatteryRangePrimaryPresentationPolicy()

    private func estimate(
        rawRemainingMeters: Double = 1_500,
        presentedRemainingMeters: Double = 1_200,
        metersPerPercentagePoint: Double = 100,
        basis: AdaptiveRangeEstimateBasis = .learned,
        confidence: AdaptiveRangeConfidence = .normal,
        socProvenance: BatterySOCProvenance = .authoritativeMeasurement,
        lowSOCConservatismApplied: Bool = false
    ) -> AdaptiveBatteryRangeEstimate {
        AdaptiveBatteryRangeEstimate(
            rawRemainingMeters: rawRemainingMeters,
            presentedRemainingMeters: presentedRemainingMeters,
            metersPerPercentagePoint: metersPerPercentagePoint,
            basis: basis,
            confidence: confidence,
            socProvenance: socProvenance,
            lowSOCConservatismApplied: lowSOCConservatismApplied
        )
    }

    private func vehicleState(
        connection: VehicleConnectionState,
        batteryPercent: Int?
    ) -> VehicleState {
        VehicleState(
            connection: connection,
            batteryPercent: batteryPercent,
            speedKilometersPerHour: nil,
            odometerKilometers: nil,
            tripKilometers: nil,
            rideMode: nil,
            startMode: nil,
            speedLimitsKilometersPerHour: [:],
            isLocked: nil,
            isHeadlightOn: nil,
            isCruiseEnabled: nil,
            powerWatts: nil,
            currentAmps: nil
        )
    }

    private var liveState: VehicleState {
        vehicleState(connection: .connected, batteryPercent: 70)
    }

    private var retainedState: VehicleState {
        vehicleState(connection: .disconnected, batteryPercent: 70)
    }

    private var unavailableState: VehicleState {
        vehicleState(connection: .disconnected, batteryPercent: nil)
    }

    @Test("learned normal-confidence live range may reach the primary readout")
    func learnedNormalLiveRangeIsEligible() {
        let decision = policy.resolve(
            estimate: estimate(presentedRemainingMeters: 1_234),
            vehicleState: liveState
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
            vehicleState: liveState
        )

        #expect(decision == .valueMeters(900))
    }

    @Test("zero remaining range is a legitimate numeric endpoint")
    func zeroRangeIsEligible() {
        let decision = policy.resolve(
            estimate: estimate(rawRemainingMeters: 0, presentedRemainingMeters: 0, confidence: .high),
            vehicleState: liveState
        )

        #expect(decision == .valueMeters(0))
    }

    @Test("provisional cold-start range stays learning instead of becoming learned-looking mileage")
    func provisionalSeedIsWithheld() {
        let decision = policy.resolve(
            estimate: estimate(basis: .provisionalSeed, confidence: .learning),
            vehicleState: liveState
        )

        #expect(decision == .learning(.provisionalSeed))
        #expect(decision.primaryReadoutDisplay == .learning)
    }

    @Test("estimated SoC outranks provisional basis in fail-closed reason precedence")
    func estimatedSOCOutranksProvisionalBasis() {
        let decision = policy.resolve(
            estimate: estimate(
                basis: .provisionalSeed,
                confidence: .learning,
                socProvenance: .estimate
            ),
            vehicleState: liveState
        )

        #expect(decision == .unavailable(.estimatedSOCRequiresQualifier))
        #expect(decision.primaryReadoutDisplay == .unavailable)
    }

    @Test("learning confidence stays learning")
    func learningConfidenceIsWithheld() {
        let decision = policy.resolve(
            estimate: estimate(confidence: .learning),
            vehicleState: liveState
        )

        #expect(decision == .learning(.learningConfidence))
    }

    @Test("low confidence requires a qualifier before numeric presentation")
    func lowConfidenceIsWithheld() {
        let decision = policy.resolve(
            estimate: estimate(confidence: .low),
            vehicleState: liveState
        )

        #expect(decision == .learning(.lowConfidenceRequiresQualifier))
    }

    @Test("estimated SoC cannot become an unqualified numeric range")
    func estimatedSOCIsWithheld() {
        let decision = policy.resolve(
            estimate: estimate(confidence: .high, socProvenance: .estimate),
            vehicleState: liveState
        )

        #expect(decision == .unavailable(.estimatedSOCRequiresQualifier))
        #expect(decision.primaryReadoutDisplay == .unavailable)
    }

    @Test("disconnected confirmed vehicle state becomes retained instead of live")
    func retainedVehicleDataIsWithheld() {
        let decision = policy.resolve(
            estimate: estimate(confidence: .high),
            vehicleState: retainedState
        )

        #expect(retainedState.dataAvailability == .retained)
        #expect(decision == .unavailable(.retainedVehicleDataRequiresQualifier))
    }

    @Test("reconnecting confirmed vehicle state also remains retained")
    func reconnectingVehicleDataIsWithheld() {
        let state = vehicleState(connection: .reconnecting, batteryPercent: 70)
        let decision = policy.resolve(
            estimate: estimate(confidence: .high),
            vehicleState: state
        )

        #expect(state.dataAvailability == .retained)
        #expect(decision == .unavailable(.retainedVehicleDataRequiresQualifier))
    }

    @Test("retained state without a range reports missing estimate rather than a fake qualifier need")
    func retainedMissingEstimateIsNoEstimate() {
        let decision = policy.resolve(
            estimate: nil,
            vehicleState: retainedState
        )

        #expect(decision == .unavailable(.noEstimate))
    }

    @Test("retained state cannot hide a malformed presented range")
    func retainedInvalidPresentedRangeIsInvalid() {
        let decision = policy.resolve(
            estimate: estimate(presentedRemainingMeters: .infinity, confidence: .high),
            vehicleState: retainedState
        )

        #expect(decision == .unavailable(.invalidPresentedRange))
    }

    @Test("retained state cannot hide a malformed estimate structure")
    func retainedInvalidStructureIsInvalid() {
        let decision = policy.resolve(
            estimate: estimate(rawRemainingMeters: -1, confidence: .high),
            vehicleState: retainedState
        )

        #expect(decision == .unavailable(.invalidEstimateStructure))
    }

    @Test("no confirmed vehicle data is unavailable even while connection says connected")
    func connectedWithoutConfirmedDataIsUnavailable() {
        let state = vehicleState(connection: .connected, batteryPercent: nil)
        let decision = policy.resolve(
            estimate: estimate(confidence: .high),
            vehicleState: state
        )

        #expect(state.dataAvailability == .unavailable)
        #expect(decision == .unavailable(.vehicleDataUnavailable))
    }

    @Test("unavailable vehicle data dominates a stale estimate")
    func unavailableVehicleDataIsWithheld() {
        let decision = policy.resolve(
            estimate: estimate(confidence: .high),
            vehicleState: unavailableState
        )

        #expect(decision == .unavailable(.vehicleDataUnavailable))
    }

    @Test("missing estimate fails closed")
    func missingEstimateIsUnavailable() {
        let decision = policy.resolve(
            estimate: nil,
            vehicleState: liveState
        )

        #expect(decision == .unavailable(.noEstimate))
    }

    @Test("invalid smoothed range fails closed instead of leaking through presentation")
    func invalidPresentedRangeIsUnavailable() {
        let negative = policy.resolve(
            estimate: estimate(presentedRemainingMeters: -1, confidence: .high),
            vehicleState: liveState
        )
        let nonFinite = policy.resolve(
            estimate: estimate(presentedRemainingMeters: .infinity, confidence: .high),
            vehicleState: liveState
        )

        #expect(negative == .unavailable(.invalidPresentedRange))
        #expect(nonFinite == .unavailable(.invalidPresentedRange))
    }

    @Test("negative or non-finite raw range is structurally invalid")
    func invalidRawRangeIsUnavailable() {
        let negative = policy.resolve(
            estimate: estimate(rawRemainingMeters: -1, confidence: .high),
            vehicleState: liveState
        )
        let nonFinite = policy.resolve(
            estimate: estimate(rawRemainingMeters: .infinity, confidence: .high),
            vehicleState: liveState
        )

        #expect(negative == .unavailable(.invalidEstimateStructure))
        #expect(nonFinite == .unavailable(.invalidEstimateStructure))
    }

    @Test("non-positive or non-finite efficiency is structurally invalid")
    func invalidEfficiencyIsUnavailable() {
        let zero = policy.resolve(
            estimate: estimate(metersPerPercentagePoint: 0, confidence: .high),
            vehicleState: liveState
        )
        let nonFinite = policy.resolve(
            estimate: estimate(metersPerPercentagePoint: .infinity, confidence: .high),
            vehicleState: liveState
        )

        #expect(zero == .unavailable(.invalidEstimateStructure))
        #expect(nonFinite == .unavailable(.invalidEstimateStructure))
    }

    @Test("raw range cannot exceed the current full-charge equivalent")
    func rawRangeAboveFullChargeEquivalentIsUnavailable() {
        let decision = policy.resolve(
            estimate: estimate(
                rawRemainingMeters: 10_001,
                presentedRemainingMeters: 9_000,
                metersPerPercentagePoint: 100,
                confidence: .high
            ),
            vehicleState: liveState
        )

        #expect(decision == .unavailable(.invalidEstimateStructure))
    }

    @Test("provisional estimates cannot claim learned confidence")
    func provisionalNonLearningConfidenceIsUnavailable() {
        let decision = policy.resolve(
            estimate: estimate(basis: .provisionalSeed, confidence: .normal),
            vehicleState: liveState
        )

        #expect(decision == .unavailable(.invalidEstimateStructure))
    }

    @Test("presented range may legitimately exceed the current full-charge equivalent during smoothing")
    func presentedRangeIsNotIncorrectlyCapped() {
        let decision = policy.resolve(
            estimate: estimate(
                rawRemainingMeters: 5_000,
                presentedRemainingMeters: 12_000,
                metersPerPercentagePoint: 100,
                confidence: .high
            ),
            vehicleState: liveState
        )

        #expect(decision == .valueMeters(12_000))
    }
}
