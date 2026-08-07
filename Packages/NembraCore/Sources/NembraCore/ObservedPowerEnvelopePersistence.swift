import Foundation

public enum ObservedPowerEnvelopeCheckpointError: Error, Equatable, Sendable {
    case calibrationUnavailable
    case authorityMismatch
    case unsupportedSchemaVersion(Int)
    case invalidVehicleIdentityKey
    case invalidConfirmedModeKey
    case invalidPolicy
    case invalidLearnedObservedCeilingWatts
    case invalidLearningSampleCount
    case invalidUpperBandSupportCount
    case derivedGaugeScaleOverflow
    case scopeMismatch
    case policyMismatch
    case currentSessionLearnerMismatch
}

/// Codable copy of the exact software policy that produced a retained calibration.
public struct ObservedPowerEnvelopePolicyCheckpoint: Codable, Equatable, Sendable {
    public let windowCapacity: Int
    public let minimumLearningSampleCount: Int
    public let minimumUpperBandSupportCount: Int
    public let upperPercentile: Double
    public let upperBandFraction: Double
    public let headroomFraction: Double
    public let upwardHysteresisFraction: Double

    fileprivate init(_ policy: ObservedPowerEnvelopePolicy) {
        windowCapacity = policy.windowCapacity
        minimumLearningSampleCount = policy.minimumLearningSampleCount
        minimumUpperBandSupportCount = policy.minimumUpperBandSupportCount
        upperPercentile = policy.upperPercentile
        upperBandFraction = policy.upperBandFraction
        headroomFraction = policy.headroomFraction
        upwardHysteresisFraction = policy.upwardHysteresisFraction
    }

    fileprivate func validatedPolicy() throws -> ObservedPowerEnvelopePolicy {
        do {
            return try ObservedPowerEnvelopePolicy(
                windowCapacity: windowCapacity,
                minimumLearningSampleCount: minimumLearningSampleCount,
                minimumUpperBandSupportCount: minimumUpperBandSupportCount,
                upperPercentile: upperPercentile,
                upperBandFraction: upperBandFraction,
                headroomFraction: headroomFraction,
                upwardHysteresisFraction: upwardHysteresisFraction
            )
        } catch {
            throw ObservedPowerEnvelopeCheckpointError.invalidPolicy
        }
    }

    fileprivate func matches(_ policy: ObservedPowerEnvelopePolicy) -> Bool {
        self == Self(policy)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        windowCapacity = try container.decode(Int.self, forKey: .windowCapacity)
        minimumLearningSampleCount = try container.decode(Int.self, forKey: .minimumLearningSampleCount)
        minimumUpperBandSupportCount = try container.decode(Int.self, forKey: .minimumUpperBandSupportCount)
        upperPercentile = try container.decode(Double.self, forKey: .upperPercentile)
        upperBandFraction = try container.decode(Double.self, forKey: .upperBandFraction)
        headroomFraction = try container.decode(Double.self, forKey: .headroomFraction)
        upwardHysteresisFraction = try container.decode(Double.self, forKey: .upwardHysteresisFraction)
        _ = try validatedPolicy()
    }
}

/// Retained calibration data restored from durable state.
///
/// This deliberately is NOT `ObservedPowerEnvelopeCalibration`. The live domain's
/// calibration initializer is package-sealed under SwiftPM and file-private in the
/// app's direct-source build. Persistence must not reopen that construction boundary
/// merely to make old state look like freshly minted domain calibration.
public struct ObservedPowerEnvelopeRestoredCalibration: Equatable, Sendable {
    public let scope: ObservedPowerEnvelopeScope
    public let evidenceAuthority: ObservedPowerEnvelopeEvidenceAuthority
    public let learnedObservedCeilingWatts: Double
    public let learnedGaugeScaleWatts: Double
    public let learningSampleCount: Int
    public let upperBandSupportCount: Int

    fileprivate init(
        scope: ObservedPowerEnvelopeScope,
        evidenceAuthority: ObservedPowerEnvelopeEvidenceAuthority,
        learnedObservedCeilingWatts: Double,
        learnedGaugeScaleWatts: Double,
        learningSampleCount: Int,
        upperBandSupportCount: Int
    ) {
        self.scope = scope
        self.evidenceAuthority = evidenceAuthority
        self.learnedObservedCeilingWatts = learnedObservedCeilingWatts
        self.learnedGaugeScaleWatts = learnedGaugeScaleWatts
        self.learningSampleCount = learningSampleCount
        self.upperBandSupportCount = upperBandSupportCount
    }

    fileprivate init(_ calibration: ObservedPowerEnvelopeCalibration) {
        self.init(
            scope: calibration.scope,
            evidenceAuthority: calibration.evidenceAuthority,
            learnedObservedCeilingWatts: calibration.learnedObservedCeilingWatts,
            learnedGaugeScaleWatts: calibration.learnedGaugeScaleWatts,
            learningSampleCount: calibration.learningSampleCount,
            upperBandSupportCount: calibration.upperBandSupportCount
        )
    }
}

public enum ObservedPowerEnvelopeEffectiveCalibrationOrigin: String, Equatable, Sendable {
    case retainedCheckpoint
    case currentSession
}

/// Presentation/calibration selection after reconciling retained history with the
/// current learner. `calibration` is a read-only retained-value representation and
/// cannot be injected back into the live learner as fresh measurement evidence.
public struct ObservedPowerEnvelopeEffectiveCalibration: Equatable, Sendable {
    public let calibration: ObservedPowerEnvelopeRestoredCalibration
    public let origin: ObservedPowerEnvelopeEffectiveCalibrationOrigin
}

/// Durable, validation-first representation of one learned observed power ceiling.
/// Receipt chronology, rolling measurements, and display interpolation are never
/// persisted as fresh evidence across process relaunch.
public struct ObservedPowerEnvelopeCalibrationCheckpoint: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let vehicleIdentityKey: String
    public let confirmedModeKey: String?
    public let identityAuthority: ObservedPowerEnvelopeScopeAuthority
    public let evidenceAuthority: ObservedPowerEnvelopeEvidenceAuthority
    public let policy: ObservedPowerEnvelopePolicyCheckpoint
    public let learnedObservedCeilingWatts: Double
    public let learningSampleCount: Int
    public let upperBandSupportCount: Int

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case vehicleIdentityKey
        case confirmedModeKey
        case identityAuthority
        case evidenceAuthority
        case policy
        case learnedObservedCeilingWatts
        case learningSampleCount
        case upperBandSupportCount
    }

    private init(
        learner: ObservedPowerEnvelopeLearner,
        requiredScopeAuthority: ObservedPowerEnvelopeScopeAuthority,
        requiredEvidenceAuthority: ObservedPowerEnvelopeEvidenceAuthority
    ) throws {
        guard learner.scope.identityAuthority == requiredScopeAuthority,
              learner.evidenceAuthority == requiredEvidenceAuthority else {
            throw ObservedPowerEnvelopeCheckpointError.authorityMismatch
        }
        guard let calibration = learner.calibration else {
            throw ObservedPowerEnvelopeCheckpointError.calibrationUnavailable
        }
        guard calibration.scope == learner.scope,
              calibration.evidenceAuthority == learner.evidenceAuthority else {
            throw ObservedPowerEnvelopeCheckpointError.authorityMismatch
        }

        let checkpointPolicy = ObservedPowerEnvelopePolicyCheckpoint(learner.policy)
        try Self.validateCalibrationFields(
            learnedObservedCeilingWatts: calibration.learnedObservedCeilingWatts,
            learningSampleCount: calibration.learningSampleCount,
            upperBandSupportCount: calibration.upperBandSupportCount,
            policy: checkpointPolicy
        )
        let expectedScale = try Self.derivedGaugeScale(
            ceilingWatts: calibration.learnedObservedCeilingWatts,
            policy: checkpointPolicy
        )
        guard calibration.learnedGaugeScaleWatts == expectedScale else {
            throw ObservedPowerEnvelopeCheckpointError.invalidLearnedObservedCeilingWatts
        }

        schemaVersion = Self.currentSchemaVersion
        vehicleIdentityKey = learner.scope.vehicleIdentityKey
        confirmedModeKey = learner.scope.confirmedModeKey
        identityAuthority = learner.scope.identityAuthority
        evidenceAuthority = learner.evidenceAuthority
        policy = checkpointPolicy
        learnedObservedCeilingWatts = calibration.learnedObservedCeilingWatts
        learningSampleCount = calibration.learningSampleCount
        upperBandSupportCount = calibration.upperBandSupportCount
    }

    public static func simulatorQA(
        from learner: ObservedPowerEnvelopeLearner
    ) throws -> Self {
        try Self(
            learner: learner,
            requiredScopeAuthority: .simulatorQA,
            requiredEvidenceAuthority: .simulatorQA
        )
    }

#if SWIFT_PACKAGE
    package static func verifiedVehicleMeasurements(
        from learner: ObservedPowerEnvelopeLearner
    ) throws -> Self {
        try Self(
            learner: learner,
            requiredScopeAuthority: .verifiedVehicleIdentity,
            requiredEvidenceAuthority: .verifiedVehicleMeasurement
        )
    }
#else
    fileprivate static func verifiedVehicleMeasurements(
        from learner: ObservedPowerEnvelopeLearner
    ) throws -> Self {
        try Self(
            learner: learner,
            requiredScopeAuthority: .verifiedVehicleIdentity,
            requiredEvidenceAuthority: .verifiedVehicleMeasurement
        )
    }
#endif

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw ObservedPowerEnvelopeCheckpointError.unsupportedSchemaVersion(schemaVersion)
        }

        let vehicleIdentityKey = try container.decode(String.self, forKey: .vehicleIdentityKey)
        guard !vehicleIdentityKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ObservedPowerEnvelopeCheckpointError.invalidVehicleIdentityKey
        }
        let confirmedModeKey = try container.decodeIfPresent(String.self, forKey: .confirmedModeKey)
        if let confirmedModeKey,
           confirmedModeKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ObservedPowerEnvelopeCheckpointError.invalidConfirmedModeKey
        }

        let identityAuthorityRaw = try container.decode(String.self, forKey: .identityAuthority)
        guard let identityAuthority = ObservedPowerEnvelopeScopeAuthority(rawValue: identityAuthorityRaw) else {
            throw ObservedPowerEnvelopeCheckpointError.authorityMismatch
        }
        let evidenceAuthorityRaw = try container.decode(String.self, forKey: .evidenceAuthority)
        guard let evidenceAuthority = ObservedPowerEnvelopeEvidenceAuthority(rawValue: evidenceAuthorityRaw) else {
            throw ObservedPowerEnvelopeCheckpointError.authorityMismatch
        }
        guard Self.authoritiesMatch(
            identityAuthority: identityAuthority,
            evidenceAuthority: evidenceAuthority
        ) else {
            throw ObservedPowerEnvelopeCheckpointError.authorityMismatch
        }

        let policy = try container.decode(ObservedPowerEnvelopePolicyCheckpoint.self, forKey: .policy)
        let learnedObservedCeilingWatts = try container.decode(Double.self, forKey: .learnedObservedCeilingWatts)
        let learningSampleCount = try container.decode(Int.self, forKey: .learningSampleCount)
        let upperBandSupportCount = try container.decode(Int.self, forKey: .upperBandSupportCount)
        try Self.validateCalibrationFields(
            learnedObservedCeilingWatts: learnedObservedCeilingWatts,
            learningSampleCount: learningSampleCount,
            upperBandSupportCount: upperBandSupportCount,
            policy: policy
        )
        _ = try Self.derivedGaugeScale(
            ceilingWatts: learnedObservedCeilingWatts,
            policy: policy
        )

        self.schemaVersion = schemaVersion
        self.vehicleIdentityKey = vehicleIdentityKey
        self.confirmedModeKey = confirmedModeKey
        self.identityAuthority = identityAuthority
        self.evidenceAuthority = evidenceAuthority
        self.policy = policy
        self.learnedObservedCeilingWatts = learnedObservedCeilingWatts
        self.learningSampleCount = learningSampleCount
        self.upperBandSupportCount = upperBandSupportCount
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(vehicleIdentityKey, forKey: .vehicleIdentityKey)
        try container.encodeIfPresent(confirmedModeKey, forKey: .confirmedModeKey)
        try container.encode(identityAuthority.rawValue, forKey: .identityAuthority)
        try container.encode(evidenceAuthority.rawValue, forKey: .evidenceAuthority)
        try container.encode(policy, forKey: .policy)
        try container.encode(learnedObservedCeilingWatts, forKey: .learnedObservedCeilingWatts)
        try container.encode(learningSampleCount, forKey: .learningSampleCount)
        try container.encode(upperBandSupportCount, forKey: .upperBandSupportCount)
    }

    public func restoredSimulatorQA(
        expectedScope: ObservedPowerEnvelopeScope,
        expectedPolicy: ObservedPowerEnvelopePolicy
    ) throws -> ObservedPowerEnvelopeRestoredCalibration {
        try restoredCalibration(
            expectedScope: expectedScope,
            expectedPolicy: expectedPolicy,
            requiredScopeAuthority: .simulatorQA,
            requiredEvidenceAuthority: .simulatorQA
        )
    }

#if SWIFT_PACKAGE
    package func restoredVerifiedVehicleMeasurement(
        expectedScope: ObservedPowerEnvelopeScope,
        expectedPolicy: ObservedPowerEnvelopePolicy
    ) throws -> ObservedPowerEnvelopeRestoredCalibration {
        try restoredCalibration(
            expectedScope: expectedScope,
            expectedPolicy: expectedPolicy,
            requiredScopeAuthority: .verifiedVehicleIdentity,
            requiredEvidenceAuthority: .verifiedVehicleMeasurement
        )
    }
#else
    fileprivate func restoredVerifiedVehicleMeasurement(
        expectedScope: ObservedPowerEnvelopeScope,
        expectedPolicy: ObservedPowerEnvelopePolicy
    ) throws -> ObservedPowerEnvelopeRestoredCalibration {
        try restoredCalibration(
            expectedScope: expectedScope,
            expectedPolicy: expectedPolicy,
            requiredScopeAuthority: .verifiedVehicleIdentity,
            requiredEvidenceAuthority: .verifiedVehicleMeasurement
        )
    }
#endif

    public func effectiveSimulatorQACalibration(
        expectedScope: ObservedPowerEnvelopeScope,
        expectedPolicy: ObservedPowerEnvelopePolicy,
        currentSessionLearner: ObservedPowerEnvelopeLearner
    ) throws -> ObservedPowerEnvelopeEffectiveCalibration {
        try effectiveCalibration(
            expectedScope: expectedScope,
            expectedPolicy: expectedPolicy,
            currentSessionLearner: currentSessionLearner,
            requiredScopeAuthority: .simulatorQA,
            requiredEvidenceAuthority: .simulatorQA
        )
    }

#if SWIFT_PACKAGE
    package func effectiveVerifiedVehicleCalibration(
        expectedScope: ObservedPowerEnvelopeScope,
        expectedPolicy: ObservedPowerEnvelopePolicy,
        currentSessionLearner: ObservedPowerEnvelopeLearner
    ) throws -> ObservedPowerEnvelopeEffectiveCalibration {
        try effectiveCalibration(
            expectedScope: expectedScope,
            expectedPolicy: expectedPolicy,
            currentSessionLearner: currentSessionLearner,
            requiredScopeAuthority: .verifiedVehicleIdentity,
            requiredEvidenceAuthority: .verifiedVehicleMeasurement
        )
    }
#else
    fileprivate func effectiveVerifiedVehicleCalibration(
        expectedScope: ObservedPowerEnvelopeScope,
        expectedPolicy: ObservedPowerEnvelopePolicy,
        currentSessionLearner: ObservedPowerEnvelopeLearner
    ) throws -> ObservedPowerEnvelopeEffectiveCalibration {
        try effectiveCalibration(
            expectedScope: expectedScope,
            expectedPolicy: expectedPolicy,
            currentSessionLearner: currentSessionLearner,
            requiredScopeAuthority: .verifiedVehicleIdentity,
            requiredEvidenceAuthority: .verifiedVehicleMeasurement
        )
    }
#endif

    private func restoredCalibration(
        expectedScope: ObservedPowerEnvelopeScope,
        expectedPolicy: ObservedPowerEnvelopePolicy,
        requiredScopeAuthority: ObservedPowerEnvelopeScopeAuthority,
        requiredEvidenceAuthority: ObservedPowerEnvelopeEvidenceAuthority
    ) throws -> ObservedPowerEnvelopeRestoredCalibration {
        guard expectedScope.identityAuthority == requiredScopeAuthority,
              identityAuthority == requiredScopeAuthority,
              evidenceAuthority == requiredEvidenceAuthority else {
            throw ObservedPowerEnvelopeCheckpointError.authorityMismatch
        }
        guard expectedScope.vehicleIdentityKey == vehicleIdentityKey,
              expectedScope.confirmedModeKey == confirmedModeKey else {
            throw ObservedPowerEnvelopeCheckpointError.scopeMismatch
        }
        guard policy.matches(expectedPolicy) else {
            throw ObservedPowerEnvelopeCheckpointError.policyMismatch
        }

        let scale = try Self.derivedGaugeScale(
            ceilingWatts: learnedObservedCeilingWatts,
            policy: policy
        )
        return ObservedPowerEnvelopeRestoredCalibration(
            scope: expectedScope,
            evidenceAuthority: requiredEvidenceAuthority,
            learnedObservedCeilingWatts: learnedObservedCeilingWatts,
            learnedGaugeScaleWatts: scale,
            learningSampleCount: learningSampleCount,
            upperBandSupportCount: upperBandSupportCount
        )
    }

    private func effectiveCalibration(
        expectedScope: ObservedPowerEnvelopeScope,
        expectedPolicy: ObservedPowerEnvelopePolicy,
        currentSessionLearner: ObservedPowerEnvelopeLearner,
        requiredScopeAuthority: ObservedPowerEnvelopeScopeAuthority,
        requiredEvidenceAuthority: ObservedPowerEnvelopeEvidenceAuthority
    ) throws -> ObservedPowerEnvelopeEffectiveCalibration {
        let retained = try restoredCalibration(
            expectedScope: expectedScope,
            expectedPolicy: expectedPolicy,
            requiredScopeAuthority: requiredScopeAuthority,
            requiredEvidenceAuthority: requiredEvidenceAuthority
        )
        guard currentSessionLearner.scope == expectedScope,
              currentSessionLearner.policy == expectedPolicy,
              currentSessionLearner.evidenceAuthority == requiredEvidenceAuthority else {
            throw ObservedPowerEnvelopeCheckpointError.currentSessionLearnerMismatch
        }

        guard let current = currentSessionLearner.calibration,
              current.scope == expectedScope,
              current.evidenceAuthority == requiredEvidenceAuthority else {
            return ObservedPowerEnvelopeEffectiveCalibration(
                calibration: retained,
                origin: .retainedCheckpoint
            )
        }

        let requiredRaisedScale = retained.learnedGaugeScaleWatts
            * (1 + expectedPolicy.upwardHysteresisFraction)
        guard requiredRaisedScale.isFinite,
              current.learnedGaugeScaleWatts > requiredRaisedScale else {
            return ObservedPowerEnvelopeEffectiveCalibration(
                calibration: retained,
                origin: .retainedCheckpoint
            )
        }

        return ObservedPowerEnvelopeEffectiveCalibration(
            calibration: ObservedPowerEnvelopeRestoredCalibration(current),
            origin: .currentSession
        )
    }

    private static func authoritiesMatch(
        identityAuthority: ObservedPowerEnvelopeScopeAuthority,
        evidenceAuthority: ObservedPowerEnvelopeEvidenceAuthority
    ) -> Bool {
        switch (identityAuthority, evidenceAuthority) {
        case (.verifiedVehicleIdentity, .verifiedVehicleMeasurement),
             (.simulatorQA, .simulatorQA):
            true
        default:
            false
        }
    }

    private static func validateCalibrationFields(
        learnedObservedCeilingWatts: Double,
        learningSampleCount: Int,
        upperBandSupportCount: Int,
        policy: ObservedPowerEnvelopePolicyCheckpoint
    ) throws {
        _ = try policy.validatedPolicy()
        guard learnedObservedCeilingWatts.isFinite,
              learnedObservedCeilingWatts > 0 else {
            throw ObservedPowerEnvelopeCheckpointError.invalidLearnedObservedCeilingWatts
        }
        guard learningSampleCount >= policy.minimumLearningSampleCount,
              learningSampleCount <= policy.windowCapacity else {
            throw ObservedPowerEnvelopeCheckpointError.invalidLearningSampleCount
        }
        guard upperBandSupportCount >= policy.minimumUpperBandSupportCount,
              upperBandSupportCount <= learningSampleCount else {
            throw ObservedPowerEnvelopeCheckpointError.invalidUpperBandSupportCount
        }
    }

    private static func derivedGaugeScale(
        ceilingWatts: Double,
        policy: ObservedPowerEnvelopePolicyCheckpoint
    ) throws -> Double {
        let scale = ceilingWatts * (1 + policy.headroomFraction)
        guard scale.isFinite, scale > 0 else {
            throw ObservedPowerEnvelopeCheckpointError.derivedGaugeScaleOverflow
        }
        return scale
    }
}
