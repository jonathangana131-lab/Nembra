import Foundation
import Testing
@testable import NembraCore

@Suite("Observed power envelope checkpoint reconciliation")
struct ObservedPowerEnvelopeCheckpointReconciliationTests {
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
        vehicle: String = "sim-es80-a",
        mode: String? = "sport",
        watts: [Double]
    ) throws -> ObservedPowerEnvelopeLearner {
        let scope = try ObservedPowerEnvelopeScope.simulatorQA(
            vehicleIdentityKey: vehicle,
            confirmedModeKey: mode
        )
        var learner = try ObservedPowerEnvelopeLearner.simulatorQA(
            scope: scope,
            policy: policy()
        )
        for (index, watts) in watts.enumerated() {
            _ = learner.record(.simulatorQA(
                powerWatts: watts,
                observedAtUptimeNanoseconds: UInt64(index + 1) * 1_000,
                learningEligibility: .eligibleForEnvelopeLearning
            ))
        }
        return learner
    }

    @Test("lower current session cannot overwrite a stronger retained checkpoint")
    func lowerCurrentSessionCannotPersistDowngrade() throws {
        let retainedLearner = try simulatorLearner(watts: [500, 520, 510])
        let retained = try ObservedPowerEnvelopeCalibrationCheckpoint.simulatorQA(from: retainedLearner)
        let lowerCurrent = try simulatorLearner(watts: [250, 260, 255])

        let reconciled = try retained.reconciledSimulatorQACheckpoint(with: lowerCurrent)
        #expect(reconciled == retained)

        let encoded = try JSONEncoder().encode(reconciled)
        let decoded = try JSONDecoder().decode(
            ObservedPowerEnvelopeCalibrationCheckpoint.self,
            from: encoded
        )
        let restored = try decoded.restoredSimulatorQA(
            expectedScope: retainedLearner.scope,
            expectedPolicy: retainedLearner.policy
        )
        #expect(restored == retainedLearner.calibration)
    }

    @Test("uncalibrated new session keeps retained checkpoint instead of failing or erasing it")
    func uncalibratedCurrentSessionKeepsRetained() throws {
        let retainedLearner = try simulatorLearner(watts: [500, 520, 510])
        let retained = try ObservedPowerEnvelopeCalibrationCheckpoint.simulatorQA(from: retainedLearner)
        let scope = retainedLearner.scope
        let emptyCurrent = try ObservedPowerEnvelopeLearner.simulatorQA(
            scope: scope,
            policy: retainedLearner.policy
        )

        let reconciled = try retained.reconciledSimulatorQACheckpoint(with: emptyCurrent)
        #expect(reconciled == retained)
    }

    @Test("stronger current session replaces retained checkpoint and survives round-trip")
    func strongerCurrentSessionPersists() throws {
        let retainedLearner = try simulatorLearner(watts: [400, 420, 410])
        let retained = try ObservedPowerEnvelopeCalibrationCheckpoint.simulatorQA(from: retainedLearner)
        let strongerCurrent = try simulatorLearner(watts: [600, 620, 610])

        let reconciled = try retained.reconciledSimulatorQACheckpoint(with: strongerCurrent)
        #expect(reconciled != retained)

        let encoded = try JSONEncoder().encode(reconciled)
        let decoded = try JSONDecoder().decode(
            ObservedPowerEnvelopeCalibrationCheckpoint.self,
            from: encoded
        )
        let restored = try decoded.restoredSimulatorQA(
            expectedScope: strongerCurrent.scope,
            expectedPolicy: strongerCurrent.policy
        )
        #expect(restored == strongerCurrent.calibration)
    }

    @Test("checkpoint reconciliation rejects a different vehicle or mode")
    func reconciliationRejectsScopeMismatch() throws {
        let retainedLearner = try simulatorLearner(watts: [500, 520, 510])
        let retained = try ObservedPowerEnvelopeCalibrationCheckpoint.simulatorQA(from: retainedLearner)
        let otherVehicle = try simulatorLearner(
            vehicle: "sim-es80-b",
            mode: retainedLearner.scope.confirmedModeKey,
            watts: [600, 620, 610]
        )

        #expect(throws: ObservedPowerEnvelopeCheckpointError.scopeMismatch) {
            try retained.reconciledSimulatorQACheckpoint(with: otherVehicle)
        }
    }

    @Test("verified production reconciliation also preserves the retained floor")
    func verifiedReconciliationPreservesFloor() throws {
        let scope = try ObservedPowerEnvelopeScope.verifiedVehicleIdentity(
            vehicleIdentityKey: "physical-es80-a",
            confirmedModeKey: "sport"
        )
        let policy = try policy()

        var retainedLearner = try ObservedPowerEnvelopeLearner.verifiedVehicleMeasurements(
            scope: scope,
            policy: policy
        )
        for (index, watts) in [500.0, 520.0, 510.0].enumerated() {
            _ = retainedLearner.record(.verifiedVehicleMeasurement(
                powerWatts: watts,
                observedAtUptimeNanoseconds: UInt64(index + 1) * 1_000,
                learningEligibility: .eligibleForEnvelopeLearning
            ))
        }
        let retained = try ObservedPowerEnvelopeCalibrationCheckpoint
            .verifiedVehicleMeasurements(from: retainedLearner)

        var lowerCurrent = try ObservedPowerEnvelopeLearner.verifiedVehicleMeasurements(
            scope: scope,
            policy: policy
        )
        for (index, watts) in [250.0, 260.0, 255.0].enumerated() {
            _ = lowerCurrent.record(.verifiedVehicleMeasurement(
                powerWatts: watts,
                observedAtUptimeNanoseconds: UInt64(index + 1) * 2_000,
                learningEligibility: .eligibleForEnvelopeLearning
            ))
        }

        let reconciled = try retained
            .reconciledVerifiedVehicleMeasurementCheckpoint(with: lowerCurrent)
        #expect(reconciled == retained)
    }
}
