import Foundation
import Testing
@testable import NembraCore

@Suite("Observed power envelope")
struct ObservedPowerEnvelopeTests {
    private func scope(mode: String? = nil) throws -> ObservedPowerEnvelopeScope {
        try ObservedPowerEnvelopeScope(vehicleIdentityKey: "physical-es80-opaque-id", confirmedModeKey: mode)
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

    @Test("scope requires an explicit nonempty vehicle key and trustworthy mode key")
    func scopeValidation() throws {
        #expect(throws: ObservedPowerEnvelopeScopeError.emptyVehicleIdentityKey) {
            try ObservedPowerEnvelopeScope(vehicleIdentityKey: "  ")
        }
        #expect(throws: ObservedPowerEnvelopeScopeError.emptyConfirmedModeKey) {
            try ObservedPowerEnvelopeScope(vehicleIdentityKey: "es80", confirmedModeKey: "\n")
        }

        let scoped = try scope(mode: "sport-confirmed")
        #expect(scoped.vehicleIdentityKey == "physical-es80-opaque-id")
        #expect(scoped.confirmedModeKey == "sport-confirmed")
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

    @Test("measurement-only evidence can never establish calibration")
    func measurementOnlyDoesNotLearn() throws {
        var learner = ObservedPowerEnvelopeLearner(scope: try scope(), policy: try policy())

        for index in 1...30 {
            let result = learner.recordQualifiedObservation(
                powerWatts: 700,
                observedAtUptimeNanoseconds: UInt64(index),
                learningEligibility: .measurementOnly
            )
            #expect(result == .acceptedMeasurementOnly)
        }

        #expect(learner.calibration == nil)
        #expect(learner.normalizedPresentationPosition(forAcceptedPowerWatts: 700) == nil)
    }

    @Test("one spike cannot establish a false high ceiling")
    func singleSpikeIsRobustlyIgnored() throws {
        var learner = ObservedPowerEnvelopeLearner(scope: try scope(), policy: try policy())
        let samples: [Double] = [500, 505, 498, 502, 501, 499, 503, 500, 1_400, 504]

        for (index, watts) in samples.enumerated() {
            _ = learner.recordQualifiedObservation(
                powerWatts: watts,
                observedAtUptimeNanoseconds: UInt64(index + 1),
                learningEligibility: .eligibleForEnvelopeLearning
            )
        }

        let calibration = try #require(learner.calibration)
        #expect(calibration.learnedObservedCeilingWatts < 510)
        #expect(calibration.learnedGaugeScaleWatts < 531)
        #expect(calibration.upperBandSupportCount >= 3)
    }

    @Test("repeated stronger physical observations raise the envelope")
    func repeatedStrongerEvidenceRaisesEnvelope() throws {
        var learner = ObservedPowerEnvelopeLearner(scope: try scope(), policy: try policy())

        for index in 1...10 {
            _ = learner.recordQualifiedObservation(
                powerWatts: 500 + Double(index % 3),
                observedAtUptimeNanoseconds: UInt64(index),
                learningEligibility: .eligibleForEnvelopeLearning
            )
        }
        let initial = try #require(learner.calibration)

        var sawRaise = false
        for index in 11...22 {
            let result = learner.recordQualifiedObservation(
                powerWatts: 650 + Double(index % 4),
                observedAtUptimeNanoseconds: UInt64(index),
                learningEligibility: .eligibleForEnvelopeLearning
            )
            if case .calibrationRaised = result { sawRaise = true }
        }

        let raised = try #require(learner.calibration)
        #expect(sawRaise)
        #expect(raised.learnedObservedCeilingWatts > initial.learnedObservedCeilingWatts)
        #expect(raised.learnedGaugeScaleWatts > initial.learnedGaugeScaleWatts)
    }

    @Test("ordinary lower output never silently shrinks an established ceiling")
    func lowerOutputDoesNotDownAdapt() throws {
        var learner = ObservedPowerEnvelopeLearner(scope: try scope(), policy: try policy())

        for index in 1...12 {
            _ = learner.recordQualifiedObservation(
                powerWatts: 700 + Double(index % 3),
                observedAtUptimeNanoseconds: UInt64(index),
                learningEligibility: .eligibleForEnvelopeLearning
            )
        }
        let initial = try #require(learner.calibration)

        for index in 13...60 {
            _ = learner.recordQualifiedObservation(
                powerWatts: 380 + Double(index % 4),
                observedAtUptimeNanoseconds: UInt64(index),
                learningEligibility: .eligibleForEnvelopeLearning
            )
        }

        #expect(learner.calibration == initial)
    }

    @Test("fresh invalid numeric evidence closes chronology to delayed callbacks")
    func invalidFreshSampleStillAdvancesChronology() throws {
        var learner = ObservedPowerEnvelopeLearner(scope: try scope(), policy: try policy())

        #expect(learner.recordQualifiedObservation(
            powerWatts: 500,
            observedAtUptimeNanoseconds: 100,
            learningEligibility: .eligibleForEnvelopeLearning
        ) == .acceptedLearningSample)

        #expect(learner.recordQualifiedObservation(
            powerWatts: .infinity,
            observedAtUptimeNanoseconds: 300,
            learningEligibility: .eligibleForEnvelopeLearning
        ) == .rejected(.invalidPowerWatts))

        #expect(learner.recordQualifiedObservation(
            powerWatts: 510,
            observedAtUptimeNanoseconds: 200,
            learningEligibility: .eligibleForEnvelopeLearning
        ) == .rejected(.nonIncreasingObservationTimestamp))

        #expect(learner.recordQualifiedObservation(
            powerWatts: 520,
            observedAtUptimeNanoseconds: 400,
            learningEligibility: .eligibleForEnvelopeLearning
        ) == .acceptedLearningSample)
    }

    @Test("presentation normalization reaches the edge near learned observed output and never rewrites watts")
    func normalizedPresentationPositionIsRenderOnly() throws {
        var learner = ObservedPowerEnvelopeLearner(
            scope: try scope(),
            policy: try policy(headroomFraction: 0.02)
        )

        for index in 1...10 {
            _ = learner.recordQualifiedObservation(
                powerWatts: 600,
                observedAtUptimeNanoseconds: UInt64(index),
                learningEligibility: .eligibleForEnvelopeLearning
            )
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

    @Test("extreme finite power stays accepted even when headroom math cannot produce a finite scale")
    func extremeFinitePowerDoesNotInventHardwareCap() throws {
        var learner = ObservedPowerEnvelopeLearner(
            scope: try scope(),
            policy: try policy(
                windowCapacity: 3,
                minimumLearningSampleCount: 3,
                minimumUpperBandSupportCount: 2,
                upperPercentile: 0.5,
                headroomFraction: 0.5
            )
        )

        for index in 1...3 {
            let result = learner.recordQualifiedObservation(
                powerWatts: Double.greatestFiniteMagnitude,
                observedAtUptimeNanoseconds: UInt64(index),
                learningEligibility: .eligibleForEnvelopeLearning
            )
            #expect(result == .acceptedLearningSample)
        }
        #expect(learner.calibration == nil)
    }
}
