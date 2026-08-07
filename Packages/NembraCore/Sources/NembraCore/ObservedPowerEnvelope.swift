import Foundation

public enum ObservedPowerEnvelopeScopeError: Error, Equatable, Sendable {
    case emptyVehicleIdentityKey
    case emptyConfirmedModeKey
}

/// Identity provenance is distinct from power-observation provenance. Simulator
/// identities are intentionally useful for QA but are never physical scooter
/// identity evidence.
public enum ObservedPowerEnvelopeScopeAuthority: String, Equatable, Hashable, Sendable {
    case verifiedVehicleIdentity
    case simulatorQA
}

/// Opaque calibration scope. Verified physical scope construction is package-
/// sealed so app/UI clients cannot manufacture a "physical scooter identity" by
/// passing a profile name, BLE local name, or arbitrary string.
public struct ObservedPowerEnvelopeScope: Equatable, Hashable, Sendable {
    public let vehicleIdentityKey: String
    public let confirmedModeKey: String?
    public let identityAuthority: ObservedPowerEnvelopeScopeAuthority

    private init(
        vehicleIdentityKey: String,
        confirmedModeKey: String?,
        identityAuthority: ObservedPowerEnvelopeScopeAuthority
    ) throws {
        guard !vehicleIdentityKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ObservedPowerEnvelopeScopeError.emptyVehicleIdentityKey
        }
        if let confirmedModeKey {
            guard !confirmedModeKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ObservedPowerEnvelopeScopeError.emptyConfirmedModeKey
            }
        }
        self.vehicleIdentityKey = vehicleIdentityKey
        self.confirmedModeKey = confirmedModeKey
        self.identityAuthority = identityAuthority
    }

    public static func simulatorQA(
        vehicleIdentityKey: String,
        confirmedModeKey: String? = nil
    ) throws -> Self {
        try Self(
            vehicleIdentityKey: vehicleIdentityKey,
            confirmedModeKey: confirmedModeKey,
            identityAuthority: .simulatorQA
        )
    }

#if SWIFT_PACKAGE
    package static func verifiedVehicleIdentity(
        vehicleIdentityKey: String,
        confirmedModeKey: String? = nil
    ) throws -> Self {
        try Self(
            vehicleIdentityKey: vehicleIdentityKey,
            confirmedModeKey: confirmedModeKey,
            identityAuthority: .verifiedVehicleIdentity
        )
    }
#else
    fileprivate static func verifiedVehicleIdentity(
        vehicleIdentityKey: String,
        confirmedModeKey: String? = nil
    ) throws -> Self {
        try Self(
            vehicleIdentityKey: vehicleIdentityKey,
            confirmedModeKey: confirmedModeKey,
            identityAuthority: .verifiedVehicleIdentity
        )
    }
#endif
}

public enum ObservedPowerEnvelopePolicyError: Error, Equatable, Sendable {
    case invalidWindowCapacity
    case invalidMinimumLearningSampleCount
    case invalidMinimumUpperBandSupportCount
    case invalidUpperPercentile
    case invalidUpperBandFraction
    case invalidHeadroomFraction
    case invalidUpwardHysteresisFraction
}

/// Caller-selected software policy for learning a stable *observed* propulsion
/// gauge scale. No values here claim the motor/controller rated maximum.
public struct ObservedPowerEnvelopePolicy: Equatable, Sendable {
    public let windowCapacity: Int
    public let minimumLearningSampleCount: Int
    public let minimumUpperBandSupportCount: Int
    public let upperPercentile: Double
    public let upperBandFraction: Double
    public let headroomFraction: Double
    public let upwardHysteresisFraction: Double

    public init(
        windowCapacity: Int,
        minimumLearningSampleCount: Int,
        minimumUpperBandSupportCount: Int,
        upperPercentile: Double,
        upperBandFraction: Double,
        headroomFraction: Double,
        upwardHysteresisFraction: Double
    ) throws {
        guard windowCapacity > 0 else { throw ObservedPowerEnvelopePolicyError.invalidWindowCapacity }
        guard minimumLearningSampleCount > 0,
              minimumLearningSampleCount <= windowCapacity else {
            throw ObservedPowerEnvelopePolicyError.invalidMinimumLearningSampleCount
        }
        guard minimumUpperBandSupportCount >= 2,
              minimumUpperBandSupportCount <= minimumLearningSampleCount else {
            throw ObservedPowerEnvelopePolicyError.invalidMinimumUpperBandSupportCount
        }
        guard upperPercentile.isFinite,
              upperPercentile > 0,
              upperPercentile < 1 else {
            throw ObservedPowerEnvelopePolicyError.invalidUpperPercentile
        }
        guard upperBandFraction.isFinite,
              upperBandFraction >= 0,
              upperBandFraction < 1 else {
            throw ObservedPowerEnvelopePolicyError.invalidUpperBandFraction
        }
        guard headroomFraction.isFinite,
              headroomFraction >= 0,
              headroomFraction < 1 else {
            throw ObservedPowerEnvelopePolicyError.invalidHeadroomFraction
        }
        guard upwardHysteresisFraction.isFinite,
              upwardHysteresisFraction >= 0,
              upwardHysteresisFraction < 1 else {
            throw ObservedPowerEnvelopePolicyError.invalidUpwardHysteresisFraction
        }

        self.windowCapacity = windowCapacity
        self.minimumLearningSampleCount = minimumLearningSampleCount
        self.minimumUpperBandSupportCount = minimumUpperBandSupportCount
        self.upperPercentile = upperPercentile
        self.upperBandFraction = upperBandFraction
        self.headroomFraction = headroomFraction
        self.upwardHysteresisFraction = upwardHysteresisFraction
    }
}

/// Controls whether an otherwise accepted observation may influence calibration.
/// This is separate from evidence authority: a real measurement can remain
/// `measurementOnly` when battery/thermal conditions are not suitable for scale
/// learning.
public enum ObservedPowerEnvelopeLearningEligibility: Equatable, Sendable {
    case measurementOnly
    case eligibleForEnvelopeLearning
}

/// Provenance of the observations used by one learner. Simulator calibration is
/// useful for visual/runtime QA but can never masquerade as physical ES80 proof.
public enum ObservedPowerEnvelopeEvidenceAuthority: String, Equatable, Sendable {
    case verifiedVehicleMeasurement
    case simulatorQA
}

/// One timestamped propulsion-power observation. External clients can construct
/// simulator evidence; verified physical authority is package-sealed so arbitrary
/// UI/client code cannot mint `.verifiedVehicleMeasurement` merely by choosing an
/// enum value.
public struct ObservedPowerEnvelopeObservation: Equatable, Sendable {
    /// Exact vehicle/mode calibration scope this evidence belongs to. The learner
    /// rejects mismatches before touching chronology or its learning window.
    public let scope: ObservedPowerEnvelopeScope
    public let powerWatts: Double
    /// Strict source-owned callback/sample order. This is the total-order
    /// tiebreaker when multiple accepted observations share one uptime clock tick.
    public let receiptSequenceNumber: UInt64
    /// Monotonic receipt metadata. Equal values are valid when sequence order is
    /// still strict; callers must never synthesize nanoseconds to force ordering.
    public let observedAtUptimeNanoseconds: UInt64
    public let learningEligibility: ObservedPowerEnvelopeLearningEligibility
    public let evidenceAuthority: ObservedPowerEnvelopeEvidenceAuthority

    private init(
        scope: ObservedPowerEnvelopeScope,
        powerWatts: Double,
        receiptSequenceNumber: UInt64,
        observedAtUptimeNanoseconds: UInt64,
        learningEligibility: ObservedPowerEnvelopeLearningEligibility,
        evidenceAuthority: ObservedPowerEnvelopeEvidenceAuthority
    ) {
        self.scope = scope
        self.powerWatts = powerWatts
        self.receiptSequenceNumber = receiptSequenceNumber
        self.observedAtUptimeNanoseconds = observedAtUptimeNanoseconds
        self.learningEligibility = learningEligibility
        self.evidenceAuthority = evidenceAuthority
    }

    public static func simulatorQA(
        scope: ObservedPowerEnvelopeScope,
        powerWatts: Double,
        receiptSequenceNumber: UInt64,
        observedAtUptimeNanoseconds: UInt64,
        learningEligibility: ObservedPowerEnvelopeLearningEligibility
    ) -> Self {
        Self(
            scope: scope,
            powerWatts: powerWatts,
            receiptSequenceNumber: receiptSequenceNumber,
            observedAtUptimeNanoseconds: observedAtUptimeNanoseconds,
            learningEligibility: learningEligibility,
            evidenceAuthority: .simulatorQA
        )
    }

#if SWIFT_PACKAGE
    package static func verifiedVehicleMeasurement(
        scope: ObservedPowerEnvelopeScope,
        powerWatts: Double,
        receiptSequenceNumber: UInt64,
        observedAtUptimeNanoseconds: UInt64,
        learningEligibility: ObservedPowerEnvelopeLearningEligibility
    ) -> Self {
        Self(
            scope: scope,
            powerWatts: powerWatts,
            receiptSequenceNumber: receiptSequenceNumber,
            observedAtUptimeNanoseconds: observedAtUptimeNanoseconds,
            learningEligibility: learningEligibility,
            evidenceAuthority: .verifiedVehicleMeasurement
        )
    }
#else
    fileprivate static func verifiedVehicleMeasurement(
        scope: ObservedPowerEnvelopeScope,
        powerWatts: Double,
        receiptSequenceNumber: UInt64,
        observedAtUptimeNanoseconds: UInt64,
        learningEligibility: ObservedPowerEnvelopeLearningEligibility
    ) -> Self {
        Self(
            scope: scope,
            powerWatts: powerWatts,
            receiptSequenceNumber: receiptSequenceNumber,
            observedAtUptimeNanoseconds: observedAtUptimeNanoseconds,
            learningEligibility: learningEligibility,
            evidenceAuthority: .verifiedVehicleMeasurement
        )
    }
#endif
}

public enum ObservedPowerEnvelopeRejection: Equatable, Sendable {
    case scopeMismatch(
        expected: ObservedPowerEnvelopeScope,
        actual: ObservedPowerEnvelopeScope
    )
    case evidenceAuthorityMismatch(
        expected: ObservedPowerEnvelopeEvidenceAuthority,
        actual: ObservedPowerEnvelopeEvidenceAuthority
    )
    case nonIncreasingObservationSequence
    case nonIncreasingObservationTimestamp
    case invalidPowerWatts
}

public struct ObservedPowerEnvelopeCalibration: Equatable, Sendable {
    public let scope: ObservedPowerEnvelopeScope
    public let evidenceAuthority: ObservedPowerEnvelopeEvidenceAuthority
    /// Robust upper-envelope statistic from qualified accepted observations.
    /// This is not a certified/rated motor or controller maximum.
    public let learnedObservedCeilingWatts: Double
    /// Presentation scale after restrained headroom is applied.
    public let learnedGaugeScaleWatts: Double
    public let learningSampleCount: Int
    public let upperBandSupportCount: Int

#if SWIFT_PACKAGE
    /// Package-owned construction keeps validated learner/persistence code able to
    /// restore calibration without exposing a public forgery surface.
    package init(
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
#else
    /// Nembra's app target directly compiles selected Core files. Keep calibration
    /// minting file-local there so unrelated same-module UI/app code cannot forge
    /// a verified observed ceiling. Direct-source persistence integration must add
    /// an explicit trusted bridge rather than regaining module-wide construction.
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
#endif
}

public enum ObservedPowerEnvelopeRecordResult: Equatable, Sendable {
    case acceptedMeasurementOnly
    case acceptedLearningSample
    case calibrationEstablished(ObservedPowerEnvelopeCalibration)
    case calibrationRaised(ObservedPowerEnvelopeCalibration)
    case rejected(ObservedPowerEnvelopeRejection)
}

public enum ObservedPowerEnvelopeLearnerError: Error, Equatable, Sendable {
    case scopeAuthorityMismatch(
        expected: ObservedPowerEnvelopeScopeAuthority,
        actual: ObservedPowerEnvelopeScopeAuthority
    )
}

/// Learns a stable upward-adapting presentation scale from one explicitly scoped
/// evidence authority.
///
/// This type does **not** decode BLE/Tuya data, establish watts semantics, infer
/// throttle position, or decide whether an observation is free from battery or
/// thermal limiting. Verified physical observation and learner construction are
/// package-sealed; public clients can create only simulator-QA calibration.
///
/// Automatic downward adaptation is intentionally absent at the current product
/// evidence maturity. Once a stronger ceiling has been observed, ordinary lower
/// output cannot shrink the scale and masquerade battery/thermal power reduction
/// as a new "full power" baseline. A future downward-recalibration path needs its
/// own explicit evidence policy rather than silent decay.
public struct ObservedPowerEnvelopeLearner: Sendable {
    public let scope: ObservedPowerEnvelopeScope
    public let policy: ObservedPowerEnvelopePolicy
    public let evidenceAuthority: ObservedPowerEnvelopeEvidenceAuthority

    private var lastSeenReceiptSequenceNumber: UInt64?
    private var lastObservedUptimeNanoseconds: UInt64?
    private var eligiblePowerWindow: [Double] = []
    private var calibrationStorage: ObservedPowerEnvelopeCalibration?

    private init(
        scope: ObservedPowerEnvelopeScope,
        policy: ObservedPowerEnvelopePolicy,
        evidenceAuthority: ObservedPowerEnvelopeEvidenceAuthority
    ) {
        self.scope = scope
        self.policy = policy
        self.evidenceAuthority = evidenceAuthority
    }

    public static func simulatorQA(
        scope: ObservedPowerEnvelopeScope,
        policy: ObservedPowerEnvelopePolicy
    ) throws -> Self {
        guard scope.identityAuthority == .simulatorQA else {
            throw ObservedPowerEnvelopeLearnerError.scopeAuthorityMismatch(
                expected: .simulatorQA,
                actual: scope.identityAuthority
            )
        }
        return Self(scope: scope, policy: policy, evidenceAuthority: .simulatorQA)
    }

#if SWIFT_PACKAGE
    package static func verifiedVehicleMeasurements(
        scope: ObservedPowerEnvelopeScope,
        policy: ObservedPowerEnvelopePolicy
    ) throws -> Self {
        guard scope.identityAuthority == .verifiedVehicleIdentity else {
            throw ObservedPowerEnvelopeLearnerError.scopeAuthorityMismatch(
                expected: .verifiedVehicleIdentity,
                actual: scope.identityAuthority
            )
        }
        return Self(scope: scope, policy: policy, evidenceAuthority: .verifiedVehicleMeasurement)
    }
#else
    fileprivate static func verifiedVehicleMeasurements(
        scope: ObservedPowerEnvelopeScope,
        policy: ObservedPowerEnvelopePolicy
    ) throws -> Self {
        guard scope.identityAuthority == .verifiedVehicleIdentity else {
            throw ObservedPowerEnvelopeLearnerError.scopeAuthorityMismatch(
                expected: .verifiedVehicleIdentity,
                actual: scope.identityAuthority
            )
        }
        return Self(scope: scope, policy: policy, evidenceAuthority: .verifiedVehicleMeasurement)
    }
#endif

    public var calibration: ObservedPowerEnvelopeCalibration? {
        calibrationStorage
    }

    @discardableResult
    public mutating func record(_ observation: ObservedPowerEnvelopeObservation) -> ObservedPowerEnvelopeRecordResult {
        guard observation.scope == scope else {
            return .rejected(.scopeMismatch(expected: scope, actual: observation.scope))
        }
        guard observation.evidenceAuthority == evidenceAuthority else {
            return .rejected(.evidenceAuthorityMismatch(
                expected: evidenceAuthority,
                actual: observation.evidenceAuthority
            ))
        }

        if let lastSeenReceiptSequenceNumber,
           observation.receiptSequenceNumber <= lastSeenReceiptSequenceNumber {
            return .rejected(.nonIncreasingObservationSequence)
        }

        // Scope + authority select this learner's immutable callback stream. Once
        // a genuinely newer receipt identity is seen, consume that identity before
        // validating its uptime/value metadata so the same callback cannot be
        // rewritten and a delayed lower sequence cannot re-enter afterward.
        lastSeenReceiptSequenceNumber = observation.receiptSequenceNumber

        if let lastObservedUptimeNanoseconds,
           observation.observedAtUptimeNanoseconds < lastObservedUptimeNanoseconds {
            // Preserve the prior monotonic uptime floor. A bad newer callback may
            // consume sequence chronology, but it must never move time backward.
            return .rejected(.nonIncreasingObservationTimestamp)
        }
        lastObservedUptimeNanoseconds = observation.observedAtUptimeNanoseconds

        guard observation.powerWatts.isFinite else {
            return .rejected(.invalidPowerWatts)
        }

        // A verified negative value may eventually be legitimate regenerative
        // power. It is not propulsion-envelope evidence, but it must not be
        // relabeled as invalid telemetry by this positive-output learner.
        guard observation.powerWatts >= 0,
              observation.learningEligibility == .eligibleForEnvelopeLearning else {
            return .acceptedMeasurementOnly
        }

        eligiblePowerWindow.append(observation.powerWatts)
        if eligiblePowerWindow.count > policy.windowCapacity {
            eligiblePowerWindow.removeFirst(eligiblePowerWindow.count - policy.windowCapacity)
        }

        guard let candidate = calibrationCandidate() else {
            return .acceptedLearningSample
        }

        guard let existing = calibrationStorage else {
            calibrationStorage = candidate
            return .calibrationEstablished(candidate)
        }

        let requiredScale = existing.learnedGaugeScaleWatts * (1 + policy.upwardHysteresisFraction)
        guard requiredScale.isFinite,
              candidate.learnedGaugeScaleWatts > requiredScale else {
            return .acceptedLearningSample
        }

        calibrationStorage = candidate
        return .calibrationRaised(candidate)
    }

    /// Render-only normalization helper. The raw measured watts remain the
    /// authoritative numeric value; this fraction is only gauge presentation.
    public func normalizedPresentationPosition(forAcceptedPowerWatts powerWatts: Double) -> Double? {
        guard powerWatts.isFinite, powerWatts >= 0,
              let scale = calibrationStorage?.learnedGaugeScaleWatts,
              scale.isFinite, scale > 0 else {
            return nil
        }
        return min(max(powerWatts / scale, 0), 1)
    }

    private func calibrationCandidate() -> ObservedPowerEnvelopeCalibration? {
        guard eligiblePowerWindow.count >= policy.minimumLearningSampleCount else {
            return nil
        }

        let sorted = eligiblePowerWindow.sorted()
        let rawRank = Double(sorted.count - 1) * policy.upperPercentile
        let percentileIndex = Int(rawRank.rounded(.down))
        let observedCeiling = sorted[percentileIndex]
        guard observedCeiling.isFinite, observedCeiling > 0 else { return nil }

        let lowerSupportBound = observedCeiling * (1 - policy.upperBandFraction)
        guard lowerSupportBound.isFinite, lowerSupportBound >= 0 else { return nil }

        let supportCount = sorted.count { $0 >= lowerSupportBound }
        guard supportCount >= policy.minimumUpperBandSupportCount else { return nil }

        let scale = observedCeiling * (1 + policy.headroomFraction)
        guard scale.isFinite, scale > 0 else { return nil }

        return ObservedPowerEnvelopeCalibration(
            scope: scope,
            evidenceAuthority: evidenceAuthority,
            learnedObservedCeilingWatts: observedCeiling,
            learnedGaugeScaleWatts: scale,
            learningSampleCount: eligiblePowerWindow.count,
            upperBandSupportCount: supportCount
        )
    }
}
