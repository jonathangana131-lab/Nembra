import Testing
@testable import NembraCore

@Suite("Observed power envelope gauge scale bridge")
struct ObservedPowerEnvelopeGaugeScaleBridgeTests {
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

    private func simulatorLearner(
        scope: ObservedPowerEnvelopeScope,
        policy: ObservedPowerEnvelopePolicy,
        watts: [Double]
    ) throws -> ObservedPowerEnvelopeLearner {
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

    private func verifiedLearner(
        scope: ObservedPowerEnvelopeScope,
        policy: ObservedPowerEnvelopePolicy,
        watts: [Double]
    ) throws -> ObservedPowerEnvelopeLearner {
        var learner = try ObservedPowerEnvelopeLearner.verifiedVehicleMeasurements(
            scope: scope,
            policy: policy
        )
        for (index, watts) in watts.enumerated() {
            _ = learner.record(.verifiedVehicleMeasurement(
                scope: scope,
                powerWatts: watts,
                receiptSequenceNumber: UInt64(index + 1),
                observedAtUptimeNanoseconds: UInt64(index + 1) * 9_000,
                learningEligibility: .eligibleForEnvelopeLearning
            ))
        }
        return learner
    }

    @Test("retained Simulator calibration becomes a Simulator presentation scale")
    func retainedSimulatorCalibrationBridgesToScale() throws {
        let scope = try ObservedPowerEnvelopeScope.simulatorQA(
            vehicleIdentityKey: "sim-es80-retained",
            confirmedModeKey: "sport"
        )
        let chosenPolicy = try policy()
        let learner = try simulatorLearner(
            scope: scope,
            policy: chosenPolicy,
            watts: [400, 420, 410]
        )
        let checkpoint = try ObservedPowerEnvelopeCalibrationCheckpoint.simulatorQA(from: learner)
        let restored = try checkpoint.restoredSimulatorQA(
            expectedScope: scope,
            expectedPolicy: chosenPolicy
        )

        let scale = try PropulsionGaugeScale.observedEnvelope(restored)

        #expect(scale.identity.vehicleID == scope.vehicleIdentityKey)
        #expect(scale.identity.modeKey == scope.confirmedModeKey)
        #expect(scale.ceilingWatts == restored.learnedGaugeScaleWatts)
        #expect(scale.origin == .simulator)
    }

    @Test("effective retained floor reaches presentation without becoming live calibration")
    func effectiveRetainedFloorBridgesToScale() throws {
        let scope = try ObservedPowerEnvelopeScope.simulatorQA(
            vehicleIdentityKey: "sim-es80-floor",
            confirmedModeKey: "sport"
        )
        let chosenPolicy = try policy()
        let retainedLearner = try simulatorLearner(
            scope: scope,
            policy: chosenPolicy,
            watts: [500, 520, 510]
        )
        let checkpoint = try ObservedPowerEnvelopeCalibrationCheckpoint.simulatorQA(from: retainedLearner)
        let currentLearner = try simulatorLearner(
            scope: scope,
            policy: chosenPolicy,
            watts: [300, 320, 310]
        )
        let effective = try checkpoint.effectiveSimulatorQACalibration(
            expectedScope: scope,
            expectedPolicy: chosenPolicy,
            currentSessionLearner: currentLearner
        )

        #expect(effective.origin == .retainedCheckpoint)
        let scale = try PropulsionGaugeScale.observedEnvelope(effective)
        #expect(scale.ceilingWatts == effective.calibration.learnedGaugeScaleWatts)
        #expect(scale.origin == .simulator)
    }

    @Test("qualified current-session increase reaches presentation after relaunch reconciliation")
    func effectiveCurrentSessionBridgesToScale() throws {
        let scope = try ObservedPowerEnvelopeScope.simulatorQA(
            vehicleIdentityKey: "sim-es80-raised",
            confirmedModeKey: "sport"
        )
        let chosenPolicy = try policy()
        let retainedLearner = try simulatorLearner(
            scope: scope,
            policy: chosenPolicy,
            watts: [400, 420, 410]
        )
        let checkpoint = try ObservedPowerEnvelopeCalibrationCheckpoint.simulatorQA(from: retainedLearner)
        let currentLearner = try simulatorLearner(
            scope: scope,
            policy: chosenPolicy,
            watts: [600, 630, 620]
        )
        let currentCalibration = try #require(currentLearner.calibration)
        let effective = try checkpoint.effectiveSimulatorQACalibration(
            expectedScope: scope,
            expectedPolicy: chosenPolicy,
            currentSessionLearner: currentLearner
        )

        #expect(effective.origin == .currentSession)
        let scale = try PropulsionGaugeScale.observedEnvelope(effective)
        #expect(scale.ceilingWatts == currentCalibration.learnedGaugeScaleWatts)
        #expect(scale.ceilingWatts == effective.calibration.learnedGaugeScaleWatts)
        #expect(scale.origin == .simulator)
    }

    @Test("package-verified retained calibration preserves verified presentation authority")
    func verifiedRetainedCalibrationBridgesToVerifiedScale() throws {
        let scope = try ObservedPowerEnvelopeScope.verifiedVehicleIdentity(
            vehicleIdentityKey: "physical-es80-opaque-id",
            confirmedModeKey: "sport"
        )
        let chosenPolicy = try policy()
        let learner = try verifiedLearner(
            scope: scope,
            policy: chosenPolicy,
            watts: [500, 540, 520]
        )
        let checkpoint = try ObservedPowerEnvelopeCalibrationCheckpoint.verifiedVehicleMeasurements(
            from: learner
        )
        let restored = try checkpoint.restoredVerifiedVehicleMeasurement(
            expectedScope: scope,
            expectedPolicy: chosenPolicy
        )

        let scale = try PropulsionGaugeScale.observedEnvelope(restored)

        #expect(scale.identity.vehicleID == scope.vehicleIdentityKey)
        #expect(scale.identity.modeKey == scope.confirmedModeKey)
        #expect(scale.ceilingWatts == restored.learnedGaugeScaleWatts)
        #expect(scale.origin == .verifiedObservedEnvelope)
    }
}
