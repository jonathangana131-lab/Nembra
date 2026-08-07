import Foundation
import Testing
@testable import NembraCore

@Suite("Observed power envelope persistence")
struct ObservedPowerEnvelopePersistenceTests {
    private func policy(
        headroom: Double = 0.05,
        hysteresis: Double = 0.05
    ) throws -> ObservedPowerEnvelopePolicy {
        try ObservedPowerEnvelopePolicy(
            windowCapacity: 6,
            minimumLearningSampleCount: 3,
            minimumUpperBandSupportCount: 2,
            upperPercentile: 0.8,
            upperBandFraction: 0.15,
            headroomFraction: headroom,
            upwardHysteresisFraction: hysteresis
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
            _ = learner.record(.simulatorQA(
                scope: scope,
                powerWatts: watts,
                receiptSequenceNumber: UInt64(index + 1),
                observedAtUptimeNanoseconds: uptimes?[index] ?? UInt64(index + 1) * 1_000,
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

    private func expectEquivalent(
        _ restored: ObservedPowerEnvelopeRestoredCalibration,
        _ live: ObservedPowerEnvelopeCalibration,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(restored.scope == live.scope, sourceLocation: sourceLocation)
        #expect(restored.evidenceAuthority == live.evidenceAuthority, sourceLocation: sourceLocation)
        #expect(restored.learnedObservedCeilingWatts == live.learnedObservedCeilingWatts, sourceLocation: sourceLocation)
        #expect(restored.learnedGaugeScaleWatts == live.learnedGaugeScaleWatts, sourceLocation: sourceLocation)
        #expect(restored.learningSampleCount == live.learningSampleCount, sourceLocation: sourceLocation)
        #expect(restored.upperBandSupportCount == live.upperBandSupportCount, sourceLocation: sourceLocation)
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

    @Test("simulator checkpoint round-trip restores equivalent retained data")
    func simulatorRoundTrip() throws {
        let learner = try simulatorLearner()
        let live = try #require(learner.calibration)
        let checkpoint = try ObservedPowerEnvelopeCalibrationCheckpoint.simulatorQA(from: learner)
        let encoded = try JSONEncoder().encode(checkpoint)
        let decoded = try JSONDecoder().decode(ObservedPowerEnvelopeCalibrationCheckpoint.self, from: encoded)
        let restored = try decoded.restoredSimulatorQA(
            expectedScope: learner.scope,
            expectedPolicy: learner.policy
        )
        #expect(decoded == checkpoint)
        expectEquivalent(restored, live)
    }

    @Test("restored value is separate from live calibration construction authority")
    func restoredValueIsSeparateType() throws {
        let learner = try simulatorLearner()
        let checkpoint = try ObservedPowerEnvelopeCalibrationCheckpoint.simulatorQA(from: learner)
        let restored = try checkpoint.restoredSimulatorQA(
            expectedScope: learner.scope,
            expectedPolicy: learner.policy
        )
        #expect(String(reflecting: type(of: restored)).contains("ObservedPowerEnvelopeRestoredCalibration"))
        #expect(!String(reflecting: type(of: restored)).contains("ObservedPowerEnvelopeCalibration>"))
    }

    @Test("equal uptime callbacks remain persistable under strict receipt sequence")
    func equalUptimeSequencePersists() throws {
        let learner = try simulatorLearner(
            watts: [400, 420, 410],
            uptimes: [5_000, 5_000, 5_000]
        )
        let live = try #require(learner.calibration)
        #expect(live.learningSampleCount == 3)
        let checkpoint = try ObservedPowerEnvelopeCalibrationCheckpoint.simulatorQA(from: learner)
        let restored = try checkpoint.restoredSimulatorQA(
            expectedScope: learner.scope,
            expectedPolicy: learner.policy
        )
        expectEquivalent(restored, live)
    }

    @Test("checkpoint stores no observation chronology or rolling window")
    func checkpointExcludesChronology() throws {
        let checkpoint = try ObservedPowerEnvelopeCalibrationCheckpoint.simulatorQA(from: simulatorLearner())
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
        let learner = try verifiedLearner(scope: scope, policy: chosenPolicy, watts: [400, 420, 410])
        #expect(throws: ObservedPowerEnvelopeCheckpointError.authorityMismatch) {
            try ObservedPowerEnvelopeCalibrationCheckpoint.simulatorQA(from: learner)
        }
    }

    @Test("verified package checkpoint round-trip preserves exact scope without forging live calibration")
    func verifiedRoundTrip() throws {
        let scope = try ObservedPowerEnvelopeScope.verifiedVehicleIdentity(
            vehicleIdentityKey: "physical-es80-a",
            confirmedModeKey: "sport"
        )
        let chosenPolicy = try policy()
        let learner = try verifiedLearner(scope: scope, policy: chosenPolicy, watts: [400, 420, 410])
        let live = try #require(learner.calibration)
        let checkpoint = try ObservedPowerEnvelopeCalibrationCheckpoint
            .verifiedVehicleMeasurements(from: learner)
        let restored = try checkpoint.restoredVerifiedVehicleMeasurement(
            expectedScope: scope,
            expectedPolicy: chosenPolicy
        )
        expectEquivalent(restored, live)
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
        vehicle["vehicleIdentityKey"] = "  \n"
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

    @Test("lower current session cannot shrink retained effective calibration")
    func retainedCalibrationIsFloor() throws {
        let retainedLearner = try simulatorLearner(watts: [500, 520, 510])
        let retainedLive = try #require(retainedLearner.calibration)
        let checkpoint = try ObservedPowerEnvelopeCalibrationCheckpoint.simulatorQA(from: retainedLearner)
        let current = try simulatorLearner(watts: [250, 260, 255], policy: retainedLearner.policy)

        let effective = try checkpoint.effectiveSimulatorQACalibration(
            expectedScope: retainedLearner.scope,
            expectedPolicy: retainedLearner.policy,
            currentSessionLearner: current
        )
        #expect(effective.origin == .retainedCheckpoint)
        expectEquivalent(effective.calibration, retainedLive)
    }

    @Test("small fresh-session increase cannot bypass retained upward hysteresis")
    func smallIncreaseKeepsRetainedCalibration() throws {
        let chosenPolicy = try policy(hysteresis: 0.05)
        let retainedLearner = try simulatorLearner(
            watts: [500, 510, 520],
            policy: chosenPolicy
        )
        let retainedLive = try #require(retainedLearner.calibration)
        let retained = try ObservedPowerEnvelopeCalibrationCheckpoint.simulatorQA(from: retainedLearner)
        let slightlyHigher = try simulatorLearner(
            watts: [515, 520, 525],
            policy: chosenPolicy
        )
        let currentLive = try #require(slightlyHigher.calibration)
        #expect(currentLive.learnedGaugeScaleWatts > retainedLive.learnedGaugeScaleWatts)
        #expect(
            currentLive.learnedGaugeScaleWatts
                < retainedLive.learnedGaugeScaleWatts * (1 + chosenPolicy.upwardHysteresisFraction)
        )

        let effective = try retained.effectiveSimulatorQACalibration(
            expectedScope: retainedLearner.scope,
            expectedPolicy: chosenPolicy,
            currentSessionLearner: slightlyHigher
        )
        #expect(effective.origin == .retainedCheckpoint)
        expectEquivalent(effective.calibration, retainedLive)
        #expect(try retained.reconciledSimulatorQACheckpoint(with: slightlyHigher) == retained)
    }

    @Test("qualified fresh-session increase advances effective and durable calibration")
    func qualifiedIncreaseReplacesRetainedCalibration() throws {
        let chosenPolicy = try policy(hysteresis: 0.05)
        let retainedLearner = try simulatorLearner(
            watts: [500, 510, 520],
            policy: chosenPolicy
        )
        let retainedLive = try #require(retainedLearner.calibration)
        let retained = try ObservedPowerEnvelopeCalibrationCheckpoint.simulatorQA(from: retainedLearner)
        let stronger = try simulatorLearner(
            watts: [550, 560, 570],
            policy: chosenPolicy
        )
        let strongerLive = try #require(stronger.calibration)
        #expect(
            strongerLive.learnedGaugeScaleWatts
                > retainedLive.learnedGaugeScaleWatts * (1 + chosenPolicy.upwardHysteresisFraction)
        )

        let effective = try retained.effectiveSimulatorQACalibration(
            expectedScope: retainedLearner.scope,
            expectedPolicy: chosenPolicy,
            currentSessionLearner: stronger
        )
        #expect(effective.origin == .currentSession)
        expectEquivalent(effective.calibration, strongerLive)

        let replacement = try retained.reconciledSimulatorQACheckpoint(with: stronger)
        #expect(replacement != retained)
        let restored = try replacement.restoredSimulatorQA(
            expectedScope: stronger.scope,
            expectedPolicy: chosenPolicy
        )
        expectEquivalent(restored, strongerLive)
    }

    @Test("zero hysteresis still requires a strict increase")
    func zeroHysteresisRequiresStrictIncrease() throws {
        let chosenPolicy = try policy(hysteresis: 0)
        let retainedLearner = try simulatorLearner(watts: [500, 510, 520], policy: chosenPolicy)
        let retained = try ObservedPowerEnvelopeCalibrationCheckpoint.simulatorQA(from: retainedLearner)
        let equal = try simulatorLearner(watts: [500, 510, 520], policy: chosenPolicy)

        let effective = try retained.effectiveSimulatorQACalibration(
            expectedScope: retainedLearner.scope,
            expectedPolicy: chosenPolicy,
            currentSessionLearner: equal
        )
        #expect(effective.origin == .retainedCheckpoint)
        #expect(try retained.reconciledSimulatorQACheckpoint(with: equal) == retained)
    }

    @Test("uncalibrated new session keeps retained checkpoint")
    func uncalibratedCurrentSessionKeepsRetained() throws {
        let retainedLearner = try simulatorLearner(watts: [500, 520, 510])
        let retained = try ObservedPowerEnvelopeCalibrationCheckpoint.simulatorQA(from: retainedLearner)
        let current = try ObservedPowerEnvelopeLearner.simulatorQA(
            scope: retainedLearner.scope,
            policy: retainedLearner.policy
        )
        #expect(try retained.reconciledSimulatorQACheckpoint(with: current) == retained)
    }

    @Test("current learner must match retained vehicle scope")
    func currentLearnerMustMatch() throws {
        let retainedLearner = try simulatorLearner()
        let checkpoint = try ObservedPowerEnvelopeCalibrationCheckpoint.simulatorQA(from: retainedLearner)
        let wrong = try simulatorLearner(
            vehicle: "sim-es80-b",
            mode: retainedLearner.scope.confirmedModeKey,
            policy: retainedLearner.policy
        )
        #expect(throws: ObservedPowerEnvelopeCheckpointError.scopeMismatch) {
            try checkpoint.effectiveSimulatorQACalibration(
                expectedScope: wrong.scope,
                expectedPolicy: wrong.policy,
                currentSessionLearner: wrong
            )
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
        #expect(
            try retained.reconciledVerifiedVehicleMeasurementCheckpoint(with: lower)
                == retained
        )
    }
}
