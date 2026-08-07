import Foundation
import Testing
@testable import NembraCore

@Suite("Observed power envelope persistence")
struct ObservedPowerEnvelopePersistenceTests {
    private func policy(headroom: Double = 0.05) throws -> ObservedPowerEnvelopePolicy {
        try ObservedPowerEnvelopePolicy(
            windowCapacity: 6,
            minimumLearningSampleCount: 3,
            minimumUpperBandSupportCount: 2,
            upperPercentile: 0.8,
            upperBandFraction: 0.15,
            headroomFraction: headroom,
            upwardHysteresisFraction: 0.05
        )
    }

    private func simulatorLearner(
        vehicle: String = "sim-es80-a",
        mode: String? = "sport",
        watts: [Double] = [400, 420, 410],
        policy: ObservedPowerEnvelopePolicy? = nil
    ) throws -> ObservedPowerEnvelopeLearner {
        let scope = try ObservedPowerEnvelopeScope.simulatorQA(
            vehicleIdentityKey: vehicle,
            confirmedModeKey: mode
        )
        let policy = try policy ?? self.policy()
        var learner = try ObservedPowerEnvelopeLearner.simulatorQA(scope: scope, policy: policy)
        for (index, watts) in watts.enumerated() {
            _ = learner.record(.simulatorQA(
                powerWatts: watts,
                observedAtUptimeNanoseconds: UInt64(index + 1) * 1_000,
                learningEligibility: .eligibleForEnvelopeLearning
            ))
        }
        return learner
    }

    private func decodedJSONObject(
        _ checkpoint: ObservedPowerEnvelopeCalibrationCheckpoint
    ) throws -> [String: Any] {
        let data = try JSONEncoder().encode(checkpoint)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func encodedJSONObject(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    @Test("checkpoint round-trip restores the same simulator calibration under the exact scope and policy")
    func simulatorRoundTrip() throws {
        let learner = try simulatorLearner()
        let original = try #require(learner.calibration)
        let checkpoint = try ObservedPowerEnvelopeCalibrationCheckpoint.simulatorQA(from: learner)
        let data = try JSONEncoder().encode(checkpoint)
        let decoded = try JSONDecoder().decode(ObservedPowerEnvelopeCalibrationCheckpoint.self, from: data)
        let restored = try decoded.restoredSimulatorQA(
            expectedScope: learner.scope,
            expectedPolicy: learner.policy
        )

        #expect(decoded == checkpoint)
        #expect(restored == original)
    }

    @Test("checkpoint refuses to snapshot a learner before calibration exists")
    func requiresCalibration() throws {
        let scope = try ObservedPowerEnvelopeScope.simulatorQA(vehicleIdentityKey: "sim-es80")
        let learner = try ObservedPowerEnvelopeLearner.simulatorQA(scope: scope, policy: policy())

        #expect(throws: ObservedPowerEnvelopeCheckpointError.calibrationUnavailable) {
            try ObservedPowerEnvelopeCalibrationCheckpoint.simulatorQA(from: learner)
        }
    }

    @Test("simulator entry point cannot relabel a verified learner")
    func simulatorCannotSnapshotVerifiedLearner() throws {
        let scope = try ObservedPowerEnvelopeScope.verifiedVehicleIdentity(vehicleIdentityKey: "physical-es80")
        var learner = try ObservedPowerEnvelopeLearner.verifiedVehicleMeasurements(scope: scope, policy: policy())
        for (index, watts) in [400.0, 420.0, 410.0].enumerated() {
            _ = learner.record(.verifiedVehicleMeasurement(
                powerWatts: watts,
                observedAtUptimeNanoseconds: UInt64(index + 1) * 1_000,
                learningEligibility: .eligibleForEnvelopeLearning
            ))
        }

        #expect(throws: ObservedPowerEnvelopeCheckpointError.authorityMismatch) {
            try ObservedPowerEnvelopeCalibrationCheckpoint.simulatorQA(from: learner)
        }
    }

    @Test("package-sealed verified checkpoint round-trip preserves only calibration, not process chronology")
    func verifiedRoundTrip() throws {
        let scope = try ObservedPowerEnvelopeScope.verifiedVehicleIdentity(
            vehicleIdentityKey: "physical-es80-a",
            confirmedModeKey: "sport"
        )
        let policy = try policy()
        var learner = try ObservedPowerEnvelopeLearner.verifiedVehicleMeasurements(scope: scope, policy: policy)
        for (index, watts) in [400.0, 420.0, 410.0].enumerated() {
            _ = learner.record(.verifiedVehicleMeasurement(
                powerWatts: watts,
                observedAtUptimeNanoseconds: UInt64(index + 1) * 9_000_000,
                learningEligibility: .eligibleForEnvelopeLearning
            ))
        }

        let checkpoint = try ObservedPowerEnvelopeCalibrationCheckpoint.verifiedVehicleMeasurements(from: learner)
        let data = try JSONEncoder().encode(checkpoint)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(!json.contains("observedAtUptime"))
        #expect(!json.contains("lastObservedUptime"))
        #expect(!json.contains("eligiblePowerWindow"))

        let decoded = try JSONDecoder().decode(ObservedPowerEnvelopeCalibrationCheckpoint.self, from: data)
        let restored = try decoded.restoredVerifiedVehicleMeasurement(
            expectedScope: scope,
            expectedPolicy: policy
        )
        #expect(restored == learner.calibration)
    }

    @Test("unsupported checkpoint schema fails closed")
    func rejectsFutureSchema() throws {
        let checkpoint = try ObservedPowerEnvelopeCalibrationCheckpoint.simulatorQA(from: simulatorLearner())
        var object = try decodedJSONObject(checkpoint)
        object["schemaVersion"] = 99
        let data = try encodedJSONObject(object)

        #expect(throws: ObservedPowerEnvelopeCheckpointError.unsupportedSchemaVersion(99)) {
            try JSONDecoder().decode(ObservedPowerEnvelopeCalibrationCheckpoint.self, from: data)
        }
    }

    @Test("tampered empty vehicle identity and empty mode fail decode")
    func rejectsEmptyIdentityFields() throws {
        let checkpoint = try ObservedPowerEnvelopeCalibrationCheckpoint.simulatorQA(from: simulatorLearner())
        var vehicleObject = try decodedJSONObject(checkpoint)
        vehicleObject["vehicleIdentityKey"] = "   \n"
        #expect(throws: ObservedPowerEnvelopeCheckpointError.invalidVehicleIdentityKey) {
            try JSONDecoder().decode(
                ObservedPowerEnvelopeCalibrationCheckpoint.self,
                from: encodedJSONObject(vehicleObject)
            )
        }

        var modeObject = try decodedJSONObject(checkpoint)
        modeObject["confirmedModeKey"] = "\t"
        #expect(throws: ObservedPowerEnvelopeCheckpointError.invalidConfirmedModeKey) {
            try JSONDecoder().decode(
                ObservedPowerEnvelopeCalibrationCheckpoint.self,
                from: encodedJSONObject(modeObject)
            )
        }
    }

    @Test("tampered authority pairing cannot turn simulator persistence into verified physical calibration")
    func rejectsAuthorityPairMismatch() throws {
        let checkpoint = try ObservedPowerEnvelopeCalibrationCheckpoint.simulatorQA(from: simulatorLearner())
        var object = try decodedJSONObject(checkpoint)
        object["identityAuthority"] = "verifiedVehicleIdentity"
        let data = try encodedJSONObject(object)

        #expect(throws: ObservedPowerEnvelopeCheckpointError.authorityMismatch) {
            try JSONDecoder().decode(ObservedPowerEnvelopeCalibrationCheckpoint.self, from: data)
        }
    }

    @Test("tampered policy fails decode rather than silently becoming a new calibration contract")
    func rejectsInvalidPolicy() throws {
        let checkpoint = try ObservedPowerEnvelopeCalibrationCheckpoint.simulatorQA(from: simulatorLearner())
        var object = try decodedJSONObject(checkpoint)
        var policyObject = try #require(object["policy"] as? [String: Any])
        policyObject["windowCapacity"] = 0
        object["policy"] = policyObject

        #expect(throws: ObservedPowerEnvelopeCheckpointError.invalidPolicy) {
            try JSONDecoder().decode(
                ObservedPowerEnvelopeCalibrationCheckpoint.self,
                from: encodedJSONObject(object)
            )
        }
    }

    @Test("tampered sample/support counts fail calibration validation")
    func rejectsImpossibleCounts() throws {
        let checkpoint = try ObservedPowerEnvelopeCalibrationCheckpoint.simulatorQA(from: simulatorLearner())

        var sampleObject = try decodedJSONObject(checkpoint)
        sampleObject["learningSampleCount"] = 2
        #expect(throws: ObservedPowerEnvelopeCheckpointError.invalidLearningSampleCount) {
            try JSONDecoder().decode(
                ObservedPowerEnvelopeCalibrationCheckpoint.self,
                from: encodedJSONObject(sampleObject)
            )
        }

        var supportObject = try decodedJSONObject(checkpoint)
        supportObject["upperBandSupportCount"] = 99
        #expect(throws: ObservedPowerEnvelopeCheckpointError.invalidUpperBandSupportCount) {
            try JSONDecoder().decode(
                ObservedPowerEnvelopeCalibrationCheckpoint.self,
                from: encodedJSONObject(supportObject)
            )
        }
    }

    @Test("retained calibration restores only for the exact vehicle, confirmed mode, and policy")
    func restoreRequiresExactScopeAndPolicy() throws {
        let learner = try simulatorLearner()
        let checkpoint = try ObservedPowerEnvelopeCalibrationCheckpoint.simulatorQA(from: learner)
        let otherScope = try ObservedPowerEnvelopeScope.simulatorQA(
            vehicleIdentityKey: learner.scope.vehicleIdentityKey,
            confirmedModeKey: "eco"
        )
        #expect(throws: ObservedPowerEnvelopeCheckpointError.scopeMismatch) {
            try checkpoint.restoredSimulatorQA(expectedScope: otherScope, expectedPolicy: learner.policy)
        }

        let changedPolicy = try policy(headroom: 0.06)
        #expect(throws: ObservedPowerEnvelopeCheckpointError.policyMismatch) {
            try checkpoint.restoredSimulatorQA(expectedScope: learner.scope, expectedPolicy: changedPolicy)
        }
    }

    @Test("lower current-session calibration cannot shrink the retained ceiling after relaunch")
    func retainedCalibrationIsFloor() throws {
        let retainedLearner = try simulatorLearner(watts: [500, 520, 510])
        let checkpoint = try ObservedPowerEnvelopeCalibrationCheckpoint.simulatorQA(from: retainedLearner)
        let current = try simulatorLearner(watts: [250, 260, 255], policy: retainedLearner.policy)

        let effective = try checkpoint.effectiveSimulatorQACalibration(
            expectedScope: retainedLearner.scope,
            expectedPolicy: retainedLearner.policy,
            currentSessionLearner: current
        )
        #expect(effective.origin == .retainedCheckpoint)
        #expect(effective.calibration == retainedLearner.calibration)
    }

    @Test("stronger current-session calibration can raise the retained ceiling")
    func strongerCurrentSessionWins() throws {
        let retainedLearner = try simulatorLearner(watts: [400, 420, 410])
        let checkpoint = try ObservedPowerEnvelopeCalibrationCheckpoint.simulatorQA(from: retainedLearner)
        let current = try simulatorLearner(watts: [600, 620, 610], policy: retainedLearner.policy)

        let effective = try checkpoint.effectiveSimulatorQACalibration(
            expectedScope: retainedLearner.scope,
            expectedPolicy: retainedLearner.policy,
            currentSessionLearner: current
        )
        #expect(effective.origin == .currentSession)
        #expect(effective.calibration == current.calibration)
    }

    @Test("current learner must share the exact retained scope, policy, and authority")
    func currentLearnerMustMatch() throws {
        let retainedLearner = try simulatorLearner()
        let checkpoint = try ObservedPowerEnvelopeCalibrationCheckpoint.simulatorQA(from: retainedLearner)
        let wrongLearner = try simulatorLearner(
            vehicle: "sim-es80-b",
            mode: retainedLearner.scope.confirmedModeKey,
            policy: retainedLearner.policy
        )

        #expect(throws: ObservedPowerEnvelopeCheckpointError.currentSessionLearnerMismatch) {
            try checkpoint.effectiveSimulatorQACalibration(
                expectedScope: retainedLearner.scope,
                expectedPolicy: retainedLearner.policy,
                currentSessionLearner: wrongLearner
            )
        }
    }
}
