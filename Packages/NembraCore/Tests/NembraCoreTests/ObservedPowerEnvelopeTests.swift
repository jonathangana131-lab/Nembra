import Foundation
import Testing
@testable import NembraCore

@Suite("Observed power envelope")
struct ObservedPowerEnvelopeTests {
    private func physicalScope(mode: String? = nil) throws -> ObservedPowerEnvelopeScope {
        try .verifiedVehicleIdentity(
            vehicleIdentityKey: "physical-es80-opaque-id",
            confirmedModeKey: mode
        )
    }

    private func simulatorScope(mode: String? = nil) throws -> ObservedPowerEnvelopeScope {
        try .simulatorQA(vehicleIdentityKey: "sim-es80", confirmedModeKey: mode)
    }

    private func policy(
        windowCapacity: Int = 12,
        minimumLearningSampleCount: Int = 10,
        minimumUpperBandSupportCount: Int = 3,
        upperPercentile: Double = 0.80,
        upperBandFraction: Double = 0.05,
        headroomFraction: Double = 0.04,
        upwardHysteresisFraction: Double = 0.03
    ) throws -> ObservedPowerEnvelopePolicy {
        try ObservedPowerEnvelopePolicy(
            windowCapacity: windowCapacity,
            minimumLearningSampleCount: minimumLearningSampleCount,
            minimumUpperBandSupportCount: minimumUpperBandSupportCount,
            upperPercentile: upperPercentile,
            upperBandFraction: upperBandFraction,
            headroomFraction: headroomFraction,
            upwardHysteresisFraction: upwardHysteresisFraction
        )
    }

    private func physicalObservation(
        watts: Double,
        uptime: UInt64,
        sequence: UInt64? = nil,
        eligibility: ObservedPowerEnvelopeLearningEligibility = .eligibleForEnvelopeLearning
    ) -> ObservedPowerEnvelopeObservation {
        .verifiedVehicleMeasurement(
            powerWatts: watts,
            receiptSequenceNumber: sequence ?? uptime,
            observedAtUptimeNanoseconds: uptime,
            learningEligibility: eligibility
        )
    }

    private func physicalLearner() throws -> ObservedPowerEnvelopeLearner {
        try .verifiedVehicleMeasurements(scope: physicalScope(), policy: policy())
    }

    @Test("scope requires explicit nonempty keys and preserves identity provenance")
    func scopeValidation() throws {
        #expect(throws: ObservedPowerEnvelopeScopeError.emptyVehicleIdentityKey) {
            try ObservedPowerEnvelopeScope.simulatorQA(vehicleIdentityKey: "  ")
        }
        #expect(throws: ObservedPowerEnvelopeScopeError.emptyConfirmedModeKey) {
            try ObservedPowerEnvelopeScope.simulatorQA(vehicleIdentityKey: "es80", confirmedModeKey: "\n")
        }

        let physical = try physicalScope(mode: "sport-confirmed")
        #expect(physical.vehicleIdentityKey == "physical-es80-opaque-id")
        #expect(physical.confirmedModeKey == "sport-confirmed")
        #expect(physical.identityAuthority == .verifiedVehicleIdentity)

        let simulator = try simulatorScope()
        #expect(simulator.identityAuthority == .simulatorQA)
    }

    @Test("learner rejects an identity scope from the wrong authority")
    func learnerScopeAuthorityMismatchFailsClosed() throws {
        let p = try policy()

        #expect(throws: ObservedPowerEnvelopeLearnerError.scopeAuthorityMismatch(
            expected: .verifiedVehicleIdentity,
            actual: .simulatorQA
        )) {
            try ObservedPowerEnvelopeLearner.verifiedVehicleMeasurements(
                scope: simulatorScope(),
                policy: p
            )
        }

        #expect(throws: ObservedPowerEnvelopeLearnerError.scopeAuthorityMismatch(
            expected: .simulatorQA,
            actual: .verifiedVehicleIdentity
        )) {
            try ObservedPowerEnvelopeLearner.simulatorQA(
                scope: physicalScope(),
                policy: p
            )
        }
    }

    @Test("policy rejects shapes that cannot provide repeated upper-envelope evidence")
    func policyValidation() {
        #expect(throws: ObservedPowerEnvelopePolicyError.invalidWindowCapacity) {
            try policy(windowCapacity: 0)
        }
        #expect(throws: ObservedPowerEnvelopePolicyError.invalidMinimumLearningSampleCount) {
            try policy(windowCapacity: 4, minimumLearningSampleCount: 5)
        }
        #expect(throws: ObservedPowerEnvelopePolicyError.invalidMinimumUpperBandSupportCount) {
            try policy(minimumUpperBandSupportCount: 1)
        }
        #expect(throws: ObservedPowerEnvelopePolicyError.invalidUpperPercentile) {
            try policy(upperPercentile: 1)
        }
    }

    @Test("simulator learner produces explicitly simulator-only calibration")
    func simulatorCalibrationKeepsProvenance() throws {
        var learner = try ObservedPowerEnvelopeLearner.simulatorQA(scope: simulatorScope(), policy: policy())

        for index in 1...10 {
            _ = learner.record(.simulatorQA(
                powerWatts: 600,
                receiptSequenceNumber: UInt64(index),
                observedAtUptimeNanoseconds: UInt64(index),
                learningEligibility: .eligibleForEnvelopeLearning
            ))
        }

        let calibration = try #require(learner.calibration)
        #expect(calibration.evidenceAuthority == .simulatorQA)
        #expect(learner.evidenceAuthority == .simulatorQA)
    }

    @Test("simulator evidence cannot enter a verified physical learner")
    func authorityMismatchFailsClosedWithoutConsumingPhysicalChronology() throws {
        var learner = try physicalLearner()

        #expect(learner.record(.simulatorQA(
            powerWatts: 900,
            receiptSequenceNumber: 1,
            observedAtUptimeNanoseconds: 100,
            learningEligibility: .eligibleForEnvelopeLearning
        )) == .rejected(.evidenceAuthorityMismatch(
            expected: .verifiedVehicleMeasurement,
            actual: .simulatorQA
        )))

        #expect(learner.record(physicalObservation(watts: 500, uptime: 100)) == .acceptedLearningSample)
    }

    @Test("measurement-only physical evidence can never establish calibration")
    func measurementOnlyDoesNotLearn() throws {
        var learner = try physicalLearner()

        for index in 1...30 {
            let result = learner.record(physicalObservation(
                watts: 700,
                uptime: UInt64(index),
                eligibility: .measurementOnly
            ))
            #expect(result == .acceptedMeasurementOnly)
        }

        #expect(learner.calibration == nil)
        #expect(learner.normalizedPresentationPosition(forAcceptedPowerWatts: 700) == nil)
    }

    @Test("one spike cannot establish a false high ceiling")
    func singleSpikeIsRobustlyIgnored() throws {
        var learner = try physicalLearner()
        let samples: [Double] = [500, 505, 498, 502, 501, 499, 503, 500, 1_400, 504]

        for (index, watts) in samples.enumerated() {
            _ = learner.record(physicalObservation(watts: watts, uptime: UInt64(index + 1)))
        }

        let calibration = try #require(learner.calibration)
        #expect(calibration.evidenceAuthority == .verifiedVehicleMeasurement)
        #expect(calibration.learnedObservedCeilingWatts < 510)
        #expect(calibration.learnedGaugeScaleWatts < 531)
        #expect(calibration.upperBandSupportCount >= 3)
    }

    @Test("repeated stronger physical observations raise the envelope")
    func repeatedStrongerEvidenceRaisesEnvelope() throws {
        var learner = try physicalLearner()

        for index in 1...10 {
            _ = learner.record(physicalObservation(
                watts: 500 + Double(index % 3),
                uptime: UInt64(index)
            ))
        }
        let initial = try #require(learner.calibration)

        var sawRaise = false
        for index in 11...22 {
            let result = learner.record(physicalObservation(
                watts: 650 + Double(index % 4),
                uptime: UInt64(index)
            ))
            if case .calibrationRaised = result { sawRaise = true }
        }

        let raised = try #require(learner.calibration)
        #expect(sawRaise)
        #expect(raised.learnedObservedCeilingWatts > initial.learnedObservedCeilingWatts)
        #expect(raised.learnedGaugeScaleWatts > initial.learnedGaugeScaleWatts)
    }

    @Test("ordinary lower output never silently shrinks an established ceiling")
    func lowerOutputDoesNotDownAdapt() throws {
        var learner = try physicalLearner()

        for index in 1...12 {
            _ = learner.record(physicalObservation(
                watts: 700 + Double(index % 3),
                uptime: UInt64(index)
            ))
        }
        let initial = try #require(learner.calibration)

        for index in 13...60 {
            _ = learner.record(physicalObservation(
                watts: 380 + Double(index % 4),
                uptime: UInt64(index)
            ))
        }

        #expect(learner.calibration == initial)
    }

    @Test("finite negative physical power is preserved as measurement-only rather than called invalid")
    func negativePowerDoesNotBecomePropulsionOrFakeInvalidTelemetry() throws {
        var learner = try physicalLearner()

        #expect(learner.record(physicalObservation(watts: -120, uptime: 100)) == .acceptedMeasurementOnly)
        #expect(learner.calibration == nil)
        #expect(learner.record(physicalObservation(watts: 500, uptime: 200)) == .acceptedLearningSample)
    }

    @Test("equal uptime ticks remain valid when receipt sequence is strictly ordered")
    func equalUptimeUsesSequenceTieBreaker() throws {
        var learner = try physicalLearner()

        #expect(learner.record(physicalObservation(
            watts: 500,
            uptime: 100,
            sequence: 1
        )) == .acceptedLearningSample)
        #expect(learner.record(physicalObservation(
            watts: 510,
            uptime: 100,
            sequence: 2
        )) == .acceptedLearningSample)
    }

    @Test("receipt sequence and uptime both fail closed when evidence order regresses")
    func orderingRegressionFailsClosed() throws {
        var learner = try physicalLearner()

        #expect(learner.record(physicalObservation(
            watts: 500,
            uptime: 100,
            sequence: 10
        )) == .acceptedLearningSample)
        #expect(learner.record(physicalObservation(
            watts: 510,
            uptime: 200,
            sequence: 9
        )) == .rejected(.nonIncreasingObservationSequence))
        #expect(learner.record(physicalObservation(
            watts: 520,
            uptime: 99,
            sequence: 11
        )) == .rejected(.nonIncreasingObservationTimestamp))
        #expect(learner.record(physicalObservation(
            watts: 530,
            uptime: 100,
            sequence: 11
        )) == .acceptedLearningSample)
    }

    @Test("fresh invalid physical numeric evidence closes sequence chronology to delayed callbacks")
    func invalidFreshSampleStillAdvancesChronology() throws {
        var learner = try physicalLearner()

        #expect(learner.record(physicalObservation(
            watts: 500,
            uptime: 100,
            sequence: 1
        )) == .acceptedLearningSample)
        #expect(learner.record(physicalObservation(
            watts: .infinity,
            uptime: 300,
            sequence: 3
        )) == .rejected(.invalidPowerWatts))
        #expect(learner.record(physicalObservation(
            watts: 510,
            uptime: 200,
            sequence: 2
        )) == .rejected(.nonIncreasingObservationSequence))
        #expect(learner.record(physicalObservation(
            watts: 520,
            uptime: 300,
            sequence: 4
        )) == .acceptedLearningSample)
    }

    @Test("presentation normalization reaches the edge near learned observed output and never rewrites watts")
    func normalizedPresentationPositionIsRenderOnly() throws {
        var learner = try ObservedPowerEnvelopeLearner.verifiedVehicleMeasurements(
            scope: physicalScope(),
            policy: policy(headroomFraction: 0.02)
        )

        for index in 1...10 {
            _ = learner.record(physicalObservation(watts: 600, uptime: UInt64(index)))
        }

        let calibration = try #require(learner.calibration)
        let atObservedCeiling = try #require(learner.normalizedPresentationPosition(
            forAcceptedPowerWatts: calibration.learnedObservedCeilingWatts
        ))
        let aboveScale = try #require(learner.normalizedPresentationPosition(
            forAcceptedPowerWatts: calibration.learnedGaugeScaleWatts * 1.5
        ))

        #expect(atObservedCeiling > 0.97)
        #expect(atObservedCeiling < 1)
        #expect(aboveScale == 1)
        #expect(calibration.learnedObservedCeilingWatts == 600)
    }

    @Test("extreme finite physical power stays accepted even when headroom math cannot produce a finite scale")
    func extremeFinitePowerDoesNotInventHardwareCap() throws {
        var learner = try ObservedPowerEnvelopeLearner.verifiedVehicleMeasurements(
            scope: physicalScope(),
            policy: policy(
                windowCapacity: 3,
                minimumLearningSampleCount: 3,
                minimumUpperBandSupportCount: 2,
                upperPercentile: 0.5,
                headroomFraction: 0.5
            )
        )

        for index in 1...3 {
            let result = learner.record(physicalObservation(
                watts: Double.greatestFiniteMagnitude,
                uptime: UInt64(index)
            ))
            #expect(result == .acceptedLearningSample)
        }
        #expect(learner.calibration == nil)
    }
}
