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
        uptimeNanoseconds: [UInt64]? = nil,
        policy suppliedPolicy: ObservedPowerEnvelopePolicy? = nil
    ) throws -> ObservedPowerEnvelopeLearner {
        let scope = try ObservedPowerEnvelopeScope.simulatorQA(
            vehicleIdentityKey: vehicle,
            confirmedModeKey: mode
        )
        let chosenPolicy: ObservedPowerEnvelopePolicy
        if let suppliedPolicy {
            chosenPolicy = suppliedPolicy
        } else {
            chosenPolicy = try policy()
        }
        var learner = try ObservedPowerEnvelopeLearner.simulatorQA(
            scope: scope,
            policy: chosenPolicy
        )
        for (index, watts) in watts.enumerated() {
            let uptime = uptimeNanoseconds?[index] ?? UInt64(index + 1) * 1_000
            _ = learner.record(.simulatorQA(
                powerWatts: watts,
                receiptSequenceNumber: UInt64(index + 1),
                observedAtUptimeNanoseconds: uptime,
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
                powerWatts: watts,
                receiptSequenceNumber: UInt64(index + 1),
                observedAtUptimeNanoseconds: UInt64(index + 1) * 9_000,
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

    @Test("checkpoint round-trip restores the same simulator calibration under exact scope and policy")
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

    @Test("equal uptime callbacks remain persistable when receipt sequence is strict")
    func equalUptimeSequencePersists() throws {
        let learner = try simulatorLearner(
            watts: [400, 420, 410],
            uptimeNanoseconds: [5_000, 5_000, 5_000]
        )
        let calibration = try #require(learner.calibration)
        #expect(calibration.learningSampleCount == 3)

        let checkpoint = try ObservedPowerEnvelopeCalibrationCheckpoint.simulatorQA(from: learner)
        let restored = try checkpoint.restoredSimulatorQA(
            expectedScope: learner.scope,
            expectedPolicy: learner.policy
        )
        #expect(restored == calibration)
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
        let verified = try verifiedLearner(scope: scope, policy: policy(), watts: [400, 420, 410])

        #expect(throws: ObservedPowerEnvelopeCheckpointError.authorityMismatch) {
            try ObservedPowerEnvelopeCalibrationCheckpoint.simulatorQA(from: verified)
        }
    }

    @Test("verified checkpoint excludes receipt chronology and round-trips calibration")
    func verifiedRoundTripExcludesChronology() throws {
        let scope = try ObservedPowerEnvelopeScope.verifiedVehicleIdentity(
            vehicleIdentityKey: "physical-es80-a",
            confirmedModeKey: "sport"
        )
        let chosenPolicy = try policy()
        let learner = try verifiedLearner(
            scope: scope,
            policy: chosenPolicy,
            watts: [400, 420, 410]
        )
        let checkpoint = try ObservedPowerEnvelopeCalibrationCheckpoint.verifiedVehicleMeasurements(from: learner)
        let data = try JSONEncoder().encode(checkpoint)
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(!json.contains("receiptSequence"))
        #expect(!json.contains("observedAtUptime"))
        #expect(!json.contains("lastObservedUptime"))
        #expect(!json.contains("eligiblePowerWindow"))

        let decoded = try JSONDecoder().decode(ObservedPowerEnvelopeCalibrationCheckpoint.self, from: data)
        let restored = try decoded.restoredVerifiedVehicleMeasurement(
            expectedScope: scope,
            expectedPolicy: chosenPolicy
        )
        #expect(restored == learner.calibration)
    }

    @Test("unsupported checkpoint schema fails closed")
    func rejectsFutureSchema() throws {
        let checkpoint = try ObservedPowerEnvelopeCalibrationCheckpoint.simulatorQA(from: simulatorLearner())
        var object = try decodedJSONObject(checkpoint)
        object["schemaVersion"] = 99

        #expect(throws: ObservedPowerEnvelopeCheckpointError.unsupportedSchemaVersion(99)) {
            try JSONDecoder().decode(
                ObservedPowerEnvelopeCalibrationCheckpoint.self,
                from: encodedJSONObject(object)
            )
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

        #expect(throws: ObservedPowerEnvelopeCheckpointError.authorityMismatch) {
            try JSONDecoder().decode(
                ObservedPowerEnvelopeCalibrationCheckpoint.self,
                from: encodedJSONObject(object)
            )
        }
    }

    @Test("tampered policy fails decode rather than silently changing calibration contract")
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

    @Test("tampered sample and support counts fail calibration validation")
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

    @Test("retained calibration restores only for exact vehicle mode and policy")
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

    @Test("lower current-session calibration cannot shrink retained effective scale")
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

    @Test("stronger current-session calibration can raise retained effective scale")
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

    @Test("current learner must share exact retained scope policy and authority")
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

    @Test("lower current session cannot overwrite stronger retained checkpoint")
    func lowerCurrentSessionCannotPersistDowngrade() throws {
        let retainedLearner = try simulatorLearner(watts: [500, 520, 510])
        let retained = try ObservedPowerEnvelopeCalibrationCheckpoint.simulatorQA(from: retainedLearner)
        let lowerCurrent = try simulatorLearner(watts: [250, 260, 255], policy: retainedLearner.policy)

        let reconciled = try retained.reconciledSimulatorQACheckpoint(with: lowerCurrent)
        #expect(reconciled == retained)

        let encoded = try JSONEncoder().encode(reconciled)
        let decoded = try JSONDecoder().decode(ObservedPowerEnvelopeCalibrationCheckpoint.self, from: encoded)
        let restored = try decoded.restoredSimulatorQA(
            expectedScope: retainedLearner.scope,
            expectedPolicy: retainedLearner.policy
        )
        #expect(restored == retainedLearner.calibration)
    }

    @Test("uncalibrated new session keeps retained checkpoint")
    func uncalibratedCurrentSessionKeepsRetained() throws {
        let retainedLearner = try simulatorLearner(watts: [500, 520, 510])
        let retained = try ObservedPowerEnvelopeCalibrationCheckpoint.simulatorQA(from: retainedLearner)
        let emptyCurrent = try ObservedPowerEnvelopeLearner.simulatorQA(
            scope: retainedLearner.scope,
            policy: retainedLearner.policy
        )

        let reconciled = try retained.reconciledSimulatorQACheckpoint(with: emptyCurrent)
        #expect(reconciled == retained)
    }

    @Test("stronger current session replaces retained checkpoint and survives round-trip")
    func strongerCurrentSessionPersists() throws {
        let retainedLearner = try simulatorLearner(watts: [400, 420, 410])
        let retained = try ObservedPowerEnvelopeCalibrationCheckpoint.simulatorQA(from: retainedLearner)
        let strongerCurrent = try simulatorLearner(watts: [600, 620, 610], policy: retainedLearner.policy)

        let reconciled = try retained.reconciledSimulatorQACheckpoint(with: strongerCurrent)
        #expect(reconciled != retained)

        let encoded = try JSONEncoder().encode(reconciled)
        let decoded = try JSONDecoder().decode(ObservedPowerEnvelopeCalibrationCheckpoint.self, from: encoded)
        let restored = try decoded.restoredSimulatorQA(
            expectedScope: strongerCurrent.scope,
            expectedPolicy: strongerCurrent.policy
        )
        #expect(restored == strongerCurrent.calibration)
    }

    @Test("checkpoint reconciliation rejects different vehicle scope")
    func reconciliationRejectsScopeMismatch() throws {
        let retainedLearner = try simulatorLearner(watts: [500, 520, 510])
        let retained = try ObservedPowerEnvelopeCalibrationCheckpoint.simulatorQA(from: retainedLearner)
        let otherVehicle = try simulatorLearner(
            vehicle: "sim-es80-b",
            mode: retainedLearner.scope.confirmedModeKey,
            watts: [600, 620, 610],
            policy: retainedLearner.policy
        )

        #expect(throws: ObservedPowerEnvelopeCheckpointError.scopeMismatch) {
            try retained.reconciledSimulatorQACheckpoint(with: otherVehicle)
        }
    }

    @Test("verified production reconciliation also preserves retained floor")
    func verifiedReconciliationPreservesFloor() throws {
        let scope = try ObservedPowerEnvelopeScope.verifiedVehicleIdentity(
            vehicleIdentityKey: "physical-es80-a",
            confirmedModeKey: "sport"
        )
        let chosenPolicy = try policy()
        let retainedLearner = try verifiedLearner(
            scope: scope,
            policy: chosenPolicy,
            watts: [500, 520, 510]
        )
        let retained = try ObservedPowerEnvelopeCalibrationCheckpoint
            .verifiedVehicleMeasurements(from: retainedLearner)
        let lowerCurrent = try verifiedLearner(
            scope: scope,
            policy: chosenPolicy,
            watts: [250, 260, 255]
        )

        let reconciled = try retained
            .reconciledVerifiedVehicleMeasurementCheckpoint(with: lowerCurrent)
        #expect(reconciled == retained)
    }
}
