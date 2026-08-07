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
        uptimes: [UInt64]? = nil,
        policy suppliedPolicy: ObservedPowerEnvelopePolicy? = nil
    ) throws -> ObservedPowerEnvelopeLearner {
        let scope = try ObservedPowerEnvelopeScope.simulatorQA(
            vehicleIdentityKey: vehicle,
            confirmedModeKey: mode
        )
        let chosenPolicy = try suppliedPolicy ?? policy()
        var learner = try ObservedPowerEnvelopeLearner.simulatorQA(
            scope: scope,
            policy: chosenPolicy
        )

        for (index, watts) in watts.enumerated() {
            let uptime = uptimes?[index] ?? UInt64(index + 1) * 1_000
            _ = learner.record(.simulatorQA(
                scope: scope,
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
                scope: scope,
                powerWatts: watts,
                receiptSequenceNumber: UInt64(index + 1),
                observedAtUptimeNanoseconds: UInt64(index + 1) * 9_000,
                learningEligibility: .eligibleForEnvelopeLearning
            ))
        }
        return learner
    }

    private func object(
        from checkpoint: ObservedPowerEnvelopeCalibrationCheckpoint
    ) throws -> [String: Any] {
        let data = try JSONEncoder().encode(checkpoint)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func data(from object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    @Test("simulator checkpoint round-trip restores exact calibration")
    func simulatorRoundTrip() throws {
        let learner = try simulatorLearner()
        let calibration = try #require(learner.calibration)
        let checkpoint = try ObservedPowerEnvelopeCalibrationCheckpoint.simulatorQA(from: learner)
        let encoded = try JSONEncoder().encode(checkpoint)
        let decoded = try JSONDecoder().decode(ObservedPowerEnvelopeCalibrationCheckpoint.self, from: encoded)
        let restored = try decoded.restoredSimulatorQA(
            expectedScope: learner.scope,
            expectedPolicy: learner.policy
        )
        #expect(decoded == checkpoint)
        #expect(restored == calibration)
    }

    @Test("equal uptime callbacks remain persistable under strict receipt sequence")
    func equalUptimeSequencePersists() throws {
        let learner = try simulatorLearner(
            watts: [400, 420, 410],
            uptimes: [5_000, 5_000, 5_000]
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

    @Test("checkpoint stores no scope observation chronology")
    func checkpointExcludesObservationChronology() throws {
        let learner = try simulatorLearner()
        let checkpoint = try ObservedPowerEnvelopeCalibrationCheckpoint.simulatorQA(from: learner)
        let encoded = try JSONEncoder().encode(checkpoint)
        let json = try #require(String(data: encoded, encoding: .utf8))
        #expect(!json.contains("receiptSequence"))
        #expect(!json.contains("observedAtUptime"))
        #expect(!json.contains("eligiblePowerWindow"))
    }

    @Test("uncalibrated learner cannot produce checkpoint")
    func requiresCalibration() throws {
        let scope = try ObservedPowerEnvelopeScope.simulatorQA(vehicleIdentityKey: "sim-es80")
        let learner = try ObservedPowerEnvelopeLearner.simulatorQA(scope: scope, policy: policy())
        #expect(throws: ObservedPowerEnvelopeCheckpointError.calibrationUnavailable) {
            try ObservedPowerEnvelopeCalibrationCheckpoint.simulatorQA(from: learner)
        }
    }

    @Test("simulator checkpoint entry point rejects verified learner")
    func simulatorCannotRelabelVerifiedLearner() throws {
        let scope = try ObservedPowerEnvelopeScope.verifiedVehicleIdentity(
            vehicleIdentityKey: "physical-es80"
        )
        let chosenPolicy = try policy()
        let learner = try verifiedLearner(
            scope: scope,
            policy: chosenPolicy,
            watts: [400, 420, 410]
        )
        #expect(throws: ObservedPowerEnvelopeCheckpointError.authorityMismatch) {
            try ObservedPowerEnvelopeCalibrationCheckpoint.simulatorQA(from: learner)
        }
    }

    @Test("verified checkpoint round-trip uses exact verified scope")
    func verifiedRoundTrip() throws {
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
        let checkpoint = try ObservedPowerEnvelopeCalibrationCheckpoint
            .verifiedVehicleMeasurements(from: learner)
        let restored = try checkpoint.restoredVerifiedVehicleMeasurement(
            expectedScope: scope,
            expectedPolicy: chosenPolicy
        )
        #expect(restored == learner.calibration)
    }

    @Test("unsupported schema fails closed")
    func rejectsFutureSchema() throws {
        let checkpoint = try ObservedPowerEnvelopeCalibrationCheckpoint.simulatorQA(from: simulatorLearner())
        var json = try object(from: checkpoint)
        json["schemaVersion"] = 99
        #expect(throws: ObservedPowerEnvelopeCheckpointError.unsupportedSchemaVersion(99)) {
            try JSONDecoder().decode(
                ObservedPowerEnvelopeCalibrationCheckpoint.self,
                from: data(from: json)
            )
        }
    }

    @Test("empty persisted vehicle and mode identities fail decode")
    func rejectsEmptyIdentityFields() throws {
        let checkpoint = try ObservedPowerEnvelopeCalibrationCheckpoint.simulatorQA(from: simulatorLearner())
        var vehicle = try object(from: checkpoint)
        vehicle["vehicleIdentityKey"] = "   \n"
        #expect(throws: ObservedPowerEnvelopeCheckpointError.invalidVehicleIdentityKey) {
            try JSONDecoder().decode(
                ObservedPowerEnvelopeCalibrationCheckpoint.self,
                from: data(from: vehicle)
            )
        }

        var mode = try object(from: checkpoint)
        mode["confirmedModeKey"] = "\t"
        #expect(throws: ObservedPowerEnvelopeCheckpointError.invalidConfirmedModeKey) {
            try JSONDecoder().decode(
                ObservedPowerEnvelopeCalibrationCheckpoint.self,
                from: data(from: mode)
            )
        }
    }

    @Test("tampered authority pairing fails decode")
    func rejectsAuthorityPairMismatch() throws {
        let checkpoint = try ObservedPowerEnvelopeCalibrationCheckpoint.simulatorQA(from: simulatorLearner())
        var json = try object(from: checkpoint)
        json["identityAuthority"] = "verifiedVehicleIdentity"
        #expect(throws: ObservedPowerEnvelopeCheckpointError.authorityMismatch) {
            try JSONDecoder().decode(
                ObservedPowerEnvelopeCalibrationCheckpoint.self,
                from: data(from: json)
            )
        }
    }

    @Test("tampered invalid policy fails decode")
    func rejectsInvalidPolicy() throws {
        let checkpoint = try ObservedPowerEnvelopeCalibrationCheckpoint.simulatorQA(from: simulatorLearner())
        var json = try object(from: checkpoint)
        var policyJSON = try #require(json["policy"] as? [String: Any])
        policyJSON["windowCapacity"] = 0
        json["policy"] = policyJSON
        #expect(throws: ObservedPowerEnvelopeCheckpointError.invalidPolicy) {
            try JSONDecoder().decode(
                ObservedPowerEnvelopeCalibrationCheckpoint.self,
                from: data(from: json)
            )
        }
    }

    @Test("tampered sample and support counts fail decode")
    func rejectsImpossibleCounts() throws {
        let checkpoint = try ObservedPowerEnvelopeCalibrationCheckpoint.simulatorQA(from: simulatorLearner())

        var samples = try object(from: checkpoint)
        samples["learningSampleCount"] = 2
        #expect(throws: ObservedPowerEnvelopeCheckpointError.invalidLearningSampleCount) {
            try JSONDecoder().decode(
                ObservedPowerEnvelopeCalibrationCheckpoint.self,
                from: data(from: samples)
            )
        }

        var support = try object(from: checkpoint)
        support["upperBandSupportCount"] = 99
        #expect(throws: ObservedPowerEnvelopeCheckpointError.invalidUpperBandSupportCount) {
            try JSONDecoder().decode(
                ObservedPowerEnvelopeCalibrationCheckpoint.self,
                from: data(from: support)
            )
        }
    }

    @Test("restore requires exact vehicle mode and policy")
    func restoreRequiresExactScopeAndPolicy() throws {
        let learner = try simulatorLearner()
        let checkpoint = try ObservedPowerEnvelopeCalibrationCheckpoint.simulatorQA(from: learner)
        let otherScope = try ObservedPowerEnvelopeScope.simulatorQA(
            vehicleIdentityKey: learner.scope.vehicleIdentityKey,
            confirmedModeKey: "eco"
        )
        #expect(throws: ObservedPowerEnvelopeCheckpointError.scopeMismatch) {
            try checkpoint.restoredSimulatorQA(
                expectedScope: otherScope,
                expectedPolicy: learner.policy
            )
        }

        let changedPolicy = try policy(headroom: 0.06)
        #expect(throws: ObservedPowerEnvelopeCheckpointError.policyMismatch) {
            try checkpoint.restoredSimulatorQA(
                expectedScope: learner.scope,
                expectedPolicy: changedPolicy
            )
        }
    }

    @Test("retained effective calibration is floor against lower current session")
    func retainedCalibrationIsFloor() throws {
        let retainedLearner = try simulatorLearner(watts: [500, 520, 510])
        let checkpoint = try ObservedPowerEnvelopeCalibrationCheckpoint.simulatorQA(from: retainedLearner)
        let current = try simulatorLearner(
            watts: [250, 260, 255],
            policy: retainedLearner.policy
        )
        let effective = try checkpoint.effectiveSimulatorQACalibration(
            expectedScope: retainedLearner.scope,
            expectedPolicy: retainedLearner.policy,
            currentSessionLearner: current
        )
        #expect(effective.origin == .retainedCheckpoint)
        #expect(effective.calibration == retainedLearner.calibration)
    }

    @Test("stronger current session can raise effective calibration")
    func strongerCurrentSessionWins() throws {
        let retainedLearner = try simulatorLearner(watts: [400, 420, 410])
        let checkpoint = try ObservedPowerEnvelopeCalibrationCheckpoint.simulatorQA(from: retainedLearner)
        let current = try simulatorLearner(
            watts: [600, 620, 610],
            policy: retainedLearner.policy
        )
        let effective = try checkpoint.effectiveSimulatorQACalibration(
            expectedScope: retainedLearner.scope,
            expectedPolicy: retainedLearner.policy,
            currentSessionLearner: current
        )
        #expect(effective.origin == .currentSession)
        #expect(effective.calibration == current.calibration)
    }

    @Test("current learner must match retained scope and policy")
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

    @Test("lower session cannot overwrite stronger retained checkpoint")
    func lowerCurrentSessionCannotPersistDowngrade() throws {
        let retainedLearner = try simulatorLearner(watts: [500, 520, 510])
        let retained = try ObservedPowerEnvelopeCalibrationCheckpoint.simulatorQA(from: retainedLearner)
        let lowerCurrent = try simulatorLearner(
            watts: [250, 260, 255],
            policy: retainedLearner.policy
        )
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

    @Test("uncalibrated new session keeps retained checkpoint")
    func uncalibratedCurrentSessionKeepsRetained() throws {
        let retainedLearner = try simulatorLearner(watts: [500, 520, 510])
        let retained = try ObservedPowerEnvelopeCalibrationCheckpoint.simulatorQA(from: retainedLearner)
        let current = try ObservedPowerEnvelopeLearner.simulatorQA(
            scope: retainedLearner.scope,
            policy: retainedLearner.policy
        )
        let reconciled = try retained.reconciledSimulatorQACheckpoint(with: current)
        #expect(reconciled == retained)
    }

    @Test("stronger session replaces checkpoint and survives round-trip")
    func strongerCurrentSessionPersists() throws {
        let retainedLearner = try simulatorLearner(watts: [400, 420, 410])
        let retained = try ObservedPowerEnvelopeCalibrationCheckpoint.simulatorQA(from: retainedLearner)
        let stronger = try simulatorLearner(
            watts: [600, 620, 610],
            policy: retainedLearner.policy
        )
        let reconciled = try retained.reconciledSimulatorQACheckpoint(with: stronger)
        #expect(reconciled != retained)

        let encoded = try JSONEncoder().encode(reconciled)
        let decoded = try JSONDecoder().decode(
            ObservedPowerEnvelopeCalibrationCheckpoint.self,
            from: encoded
        )
        let restored = try decoded.restoredSimulatorQA(
            expectedScope: stronger.scope,
            expectedPolicy: stronger.policy
        )
        #expect(restored == stronger.calibration)
    }

    @Test("checkpoint reconciliation rejects different vehicle")
    func reconciliationRejectsScopeMismatch() throws {
        let retainedLearner = try simulatorLearner(watts: [500, 520, 510])
        let retained = try ObservedPowerEnvelopeCalibrationCheckpoint.simulatorQA(from: retainedLearner)
        let other = try simulatorLearner(
            vehicle: "sim-es80-b",
            mode: retainedLearner.scope.confirmedModeKey,
            watts: [600, 620, 610],
            policy: retainedLearner.policy
        )
        #expect(throws: ObservedPowerEnvelopeCheckpointError.scopeMismatch) {
            try retained.reconciledSimulatorQACheckpoint(with: other)
        }
    }

    @Test("verified production reconciliation preserves retained floor")
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
        let lower = try verifiedLearner(
            scope: scope,
            policy: chosenPolicy,
            watts: [250, 260, 255]
        )
        let reconciled = try retained
            .reconciledVerifiedVehicleMeasurementCheckpoint(with: lower)
        #expect(reconciled == retained)
    }
}
