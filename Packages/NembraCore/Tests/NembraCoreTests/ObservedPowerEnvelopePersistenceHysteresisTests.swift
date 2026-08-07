import Testing
@testable import NembraCore

@Suite("Observed power envelope persistence hysteresis")
struct ObservedPowerEnvelopePersistenceHysteresisTests {
    private func policy() throws -> ObservedPowerEnvelopePolicy {
        try ObservedPowerEnvelopePolicy(
            windowCapacity: 6,
            minimumLearningSampleCount: 3,
            minimumUpperBandSupportCount: 2,
            upperPercentile: 0.8,
            upperBandFraction: 0.15,
            headroomFraction: 0.05,
            upwardHysteresisFraction: 0.05
        )
    }

    private func learner(
        watts: [Double],
        policy: ObservedPowerEnvelopePolicy
    ) throws -> ObservedPowerEnvelopeLearner {
        let scope = try ObservedPowerEnvelopeScope.simulatorQA(
            vehicleIdentityKey: "sim-es80-hysteresis",
            confirmedModeKey: "sport"
        )
        var learner = try ObservedPowerEnvelopeLearner.simulatorQA(
            scope: scope,
            policy: policy
        )
        for (index, watts) in watts.enumerated() {
            _ = learner.record(.simulatorQA(
                scope: scope,
                powerWatts: watts,
                receiptSequenceNumber: UInt64(index + 1),
                observedAtUptimeNanoseconds: UInt64(index + 1) * 1_000,
                learningEligibility: .eligibleForEnvelopeLearning
            ))
        }
        return learner
    }

    @Test("small fresh-session increase cannot bypass retained upward hysteresis")
    func smallIncreaseKeepsRetainedCalibration() throws {
        let policy = try policy()
        let retainedLearner = try learner(
            watts: [500, 510, 520],
            policy: policy
        )
        let retained = try ObservedPowerEnvelopeCalibrationCheckpoint
            .simulatorQA(from: retainedLearner)
        let slightlyHigher = try learner(
            watts: [515, 520, 525],
            policy: policy
        )

        let retainedScale = try #require(retainedLearner.calibration?.learnedGaugeScaleWatts)
        let currentScale = try #require(slightlyHigher.calibration?.learnedGaugeScaleWatts)
        #expect(currentScale > retainedScale)
        #expect(currentScale < retainedScale * (1 + policy.upwardHysteresisFraction))

        let effective = try retained.effectiveSimulatorQACalibration(
            expectedScope: retainedLearner.scope,
            expectedPolicy: policy,
            currentSessionLearner: slightlyHigher
        )
        #expect(effective.origin == .retainedCheckpoint)
        #expect(effective.calibration == retainedLearner.calibration)

        let reconciled = try retained.reconciledSimulatorQACheckpoint(with: slightlyHigher)
        #expect(reconciled == retained)
    }

    @Test("qualified fresh-session increase above retained hysteresis may advance persistence")
    func qualifiedIncreaseReplacesRetainedCalibration() throws {
        let policy = try policy()
        let retainedLearner = try learner(
            watts: [500, 510, 520],
            policy: policy
        )
        let retained = try ObservedPowerEnvelopeCalibrationCheckpoint
            .simulatorQA(from: retainedLearner)
        let stronger = try learner(
            watts: [540, 545, 550],
            policy: policy
        )

        let retainedScale = try #require(retainedLearner.calibration?.learnedGaugeScaleWatts)
        let currentScale = try #require(stronger.calibration?.learnedGaugeScaleWatts)
        #expect(currentScale > retainedScale * (1 + policy.upwardHysteresisFraction))

        let effective = try retained.effectiveSimulatorQACalibration(
            expectedScope: retainedLearner.scope,
            expectedPolicy: policy,
            currentSessionLearner: stronger
        )
        #expect(effective.origin == .currentSession)
        #expect(effective.calibration == stronger.calibration)

        let reconciled = try retained.reconciledSimulatorQACheckpoint(with: stronger)
        #expect(reconciled != retained)
        let restored = try reconciled.restoredSimulatorQA(
            expectedScope: stronger.scope,
            expectedPolicy: policy
        )
        #expect(restored == stronger.calibration)
    }
}
