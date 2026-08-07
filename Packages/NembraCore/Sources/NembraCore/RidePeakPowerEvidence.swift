import Foundation

/// Session-bound peak-power evidence produced only by a ride-owned accumulator.
///
/// `PeakPowerEvidence` remains a reusable scoped measurement primitive. This
/// wrapper adds immutable ride identity before any durable completed-ride
/// projection can associate an observed maximum with one ride.
public struct RidePeakPowerEvidence: Equatable, Sendable {
    public let sessionID: UUID
    public let beganAfterKnownObservationGap: Bool
    public let peakEvidence: PeakPowerEvidence

    public var scope: ObservedPowerEnvelopeScope {
        peakEvidence.scope
    }

    fileprivate init(
        sessionID: UUID,
        beganAfterKnownObservationGap: Bool,
        peakEvidence: PeakPowerEvidence
    ) {
        self.sessionID = sessionID
        self.beganAfterKnownObservationGap = beganAfterKnownObservationGap
        self.peakEvidence = peakEvidence
    }
}

/// Owns one `PeakPowerEvidenceAccumulator` for exactly one ride session.
///
/// There is deliberately no reset API. Construction is package-sealed so callers
/// cannot recreate the same caller-chosen ride UUID and erase already-recorded
/// evidence loss. Simulator-vs-verified authority is derived from the sealed
/// scope authority rather than supplied as a free-form choice.
public struct RidePeakPowerEvidenceAccumulator: Sendable {
    public let sessionID: UUID
    public let beganAfterKnownObservationGap: Bool
    private var peakAccumulator: PeakPowerEvidenceAccumulator

    #if SWIFT_PACKAGE
    package init(
        sessionID: UUID,
        scope: ObservedPowerEnvelopeScope,
        beginsAfterKnownObservationGap: Bool = false
    ) throws {
        self.sessionID = sessionID
        self.beganAfterKnownObservationGap = beginsAfterKnownObservationGap

        var accumulator: PeakPowerEvidenceAccumulator
        switch scope.identityAuthority {
        case .simulatorQA:
            accumulator = try .simulatorQA(scope: scope)
        case .verifiedVehicleIdentity:
            accumulator = try .verifiedVehicleMeasurements(scope: scope)
        }

        if beginsAfterKnownObservationGap {
            accumulator.recordInterruption(.applicationLifecycleInterrupted)
        }
        self.peakAccumulator = accumulator
    }
    #endif

    public var scope: ObservedPowerEnvelopeScope {
        peakAccumulator.scope
    }

    public var evidenceAuthority: ObservedPowerEnvelopeEvidenceAuthority {
        peakAccumulator.evidenceAuthority
    }

    @discardableResult
    public mutating func record(
        _ observation: ObservedPowerEnvelopeObservation
    ) -> PeakPowerRecordResult {
        peakAccumulator.record(observation)
    }

    public mutating func recordInterruption(_ interruption: PeakPowerInterruption) {
        peakAccumulator.recordInterruption(interruption)
    }

    /// Nil means no accepted nonnegative propulsion-power measurement has yet
    /// established an observed peak. Rejections/gaps remain retained internally
    /// and are reflected if later accepted evidence establishes one.
    public var evidence: RidePeakPowerEvidence? {
        guard let peakEvidence = peakAccumulator.evidence else { return nil }
        return RidePeakPowerEvidence(
            sessionID: sessionID,
            beganAfterKnownObservationGap: beganAfterKnownObservationGap,
            peakEvidence: peakEvidence
        )
    }
}

public enum CompletedRidePeakPowerEvidenceError: Error, Equatable, Sendable {
    case sessionMismatch
    case continuityMismatch
    case authorityMismatch
    case scopeMismatch
    case unsupportedCheckpointSchema(Int)
    case invalidEvidence
    case untrustedCheckpointOrigin
}

/// Trusted accepted peak-power evidence bound to one immutable completed ride.
///
/// This value is intentionally **not Decodable**. Arbitrary durable bytes must
/// first decode into `CompletedRidePeakPowerCheckpoint`, which is only a validated
/// persisted representation. Converting durable bytes back into verified-vehicle
/// evidence additionally requires the package-sealed trusted persistence decode
/// boundary; ordinary public decoding can never mint physical authority.
///
/// Process-local receipt sequence and uptime are deliberately stripped before
/// persistence. They are ordering evidence inside one acquisition process, and
/// the current accepted power observation does not carry a mechanically bound
/// source-generation ID that would make those clocks meaningful after relaunch.
///
/// This remains an *observed* peak over retained coverage. It is not a rated
/// motor/controller maximum, learned full-power ceiling, throttle signal, or
/// proof of the unobserved continuous-time physical maximum.
public struct CompletedRidePeakPowerEvidence: Equatable, Sendable {
    public let sessionID: UUID
    public let rideContinuity: RideSessionContinuity
    public let beganAfterKnownObservationGap: Bool
    public let vehicleIdentityKey: String
    public let confirmedModeKey: String?
    public let identityAuthority: ObservedPowerEnvelopeScopeAuthority
    public let evidenceAuthority: ObservedPowerEnvelopeEvidenceAuthority
    public let powerWatts: Double
    public let acceptedMeasurementCount: Int
    public let peakCandidateMeasurementCount: Int
    public let qualityRejectedMeasurementCount: Int
    public let knownInterruptionCount: Int
    public let observationContinuity: PeakPowerObservationContinuity

    /// Package-sealed until a completed-ride adapter mechanically binds live
    /// ride-power ownership to the authoritative ride lifecycle.
    package init(
        completedRide: CompletedRideEvidence,
        ridePeak: RidePeakPowerEvidence
    ) throws {
        guard completedRide.sessionID == ridePeak.sessionID else {
            throw CompletedRidePeakPowerEvidenceError.sessionMismatch
        }

        if completedRide.continuity == .recoveredCheckpoint,
           (!ridePeak.beganAfterKnownObservationGap ||
            ridePeak.peakEvidence.knownInterruptionCount == 0 ||
            ridePeak.peakEvidence.continuity != .partialSelectedSourceEvidence) {
            throw CompletedRidePeakPowerEvidenceError.continuityMismatch
        }

        try self.init(
            sessionID: completedRide.sessionID,
            rideContinuity: completedRide.continuity,
            beganAfterKnownObservationGap: ridePeak.beganAfterKnownObservationGap,
            vehicleIdentityKey: ridePeak.scope.vehicleIdentityKey,
            confirmedModeKey: ridePeak.scope.confirmedModeKey,
            identityAuthority: ridePeak.scope.identityAuthority,
            evidenceAuthority: ridePeak.peakEvidence.evidenceAuthority,
            powerWatts: ridePeak.peakEvidence.peak.powerWatts,
            acceptedMeasurementCount: ridePeak.peakEvidence.acceptedMeasurementCount,
            peakCandidateMeasurementCount: ridePeak.peakEvidence.peakCandidateMeasurementCount,
            qualityRejectedMeasurementCount: ridePeak.peakEvidence.qualityRejectedMeasurementCount,
            knownInterruptionCount: ridePeak.peakEvidence.knownInterruptionCount,
            observationContinuity: ridePeak.peakEvidence.continuity
        )
    }

    package func validate(against completedRide: CompletedRideEvidence) throws {
        guard completedRide.sessionID == sessionID else {
            throw CompletedRidePeakPowerEvidenceError.sessionMismatch
        }
        guard completedRide.continuity == rideContinuity else {
            throw CompletedRidePeakPowerEvidenceError.continuityMismatch
        }
    }

    fileprivate init(
        sessionID: UUID,
        rideContinuity: RideSessionContinuity,
        beganAfterKnownObservationGap: Bool,
        vehicleIdentityKey: String,
        confirmedModeKey: String?,
        identityAuthority: ObservedPowerEnvelopeScopeAuthority,
        evidenceAuthority: ObservedPowerEnvelopeEvidenceAuthority,
        powerWatts: Double,
        acceptedMeasurementCount: Int,
        peakCandidateMeasurementCount: Int,
        qualityRejectedMeasurementCount: Int,
        knownInterruptionCount: Int,
        observationContinuity: PeakPowerObservationContinuity
    ) throws {
        try Self.validateFields(
            rideContinuity: rideContinuity,
            beganAfterKnownObservationGap: beganAfterKnownObservationGap,
            vehicleIdentityKey: vehicleIdentityKey,
            confirmedModeKey: confirmedModeKey,
            identityAuthority: identityAuthority,
            evidenceAuthority: evidenceAuthority,
            powerWatts: powerWatts,
            acceptedMeasurementCount: acceptedMeasurementCount,
            peakCandidateMeasurementCount: peakCandidateMeasurementCount,
            qualityRejectedMeasurementCount: qualityRejectedMeasurementCount,
            knownInterruptionCount: knownInterruptionCount,
            observationContinuity: observationContinuity
        )

        self.sessionID = sessionID
        self.rideContinuity = rideContinuity
        self.beganAfterKnownObservationGap = beganAfterKnownObservationGap
        self.vehicleIdentityKey = vehicleIdentityKey
        self.confirmedModeKey = confirmedModeKey
        self.identityAuthority = identityAuthority
        self.evidenceAuthority = evidenceAuthority
        self.powerWatts = powerWatts
        self.acceptedMeasurementCount = acceptedMeasurementCount
        self.peakCandidateMeasurementCount = peakCandidateMeasurementCount
        self.qualityRejectedMeasurementCount = qualityRejectedMeasurementCount
        self.knownInterruptionCount = knownInterruptionCount
        self.observationContinuity = observationContinuity
    }

    fileprivate static func validateFields(
        rideContinuity: RideSessionContinuity,
        beganAfterKnownObservationGap: Bool,
        vehicleIdentityKey: String,
        confirmedModeKey: String?,
        identityAuthority: ObservedPowerEnvelopeScopeAuthority,
        evidenceAuthority: ObservedPowerEnvelopeEvidenceAuthority,
        powerWatts: Double,
        acceptedMeasurementCount: Int,
        peakCandidateMeasurementCount: Int,
        qualityRejectedMeasurementCount: Int,
        knownInterruptionCount: Int,
        observationContinuity: PeakPowerObservationContinuity
    ) throws {
        guard !vehicleIdentityKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CompletedRidePeakPowerEvidenceError.invalidEvidence
        }
        if let confirmedModeKey,
           confirmedModeKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw CompletedRidePeakPowerEvidenceError.invalidEvidence
        }

        guard authorityPairIsValid(
            identityAuthority: identityAuthority,
            evidenceAuthority: evidenceAuthority
        ),
        powerWatts.isFinite,
        powerWatts >= 0,
        acceptedMeasurementCount > 0,
        peakCandidateMeasurementCount > 0,
        peakCandidateMeasurementCount <= acceptedMeasurementCount,
        qualityRejectedMeasurementCount >= 0,
        knownInterruptionCount >= 0 else {
            throw CompletedRidePeakPowerEvidenceError.invalidEvidence
        }

        switch observationContinuity {
        case .noRecordedSelectedSourceEvidenceLoss:
            guard qualityRejectedMeasurementCount == 0,
                  knownInterruptionCount == 0,
                  !beganAfterKnownObservationGap else {
                throw CompletedRidePeakPowerEvidenceError.invalidEvidence
            }
        case .partialSelectedSourceEvidence:
            guard qualityRejectedMeasurementCount > 0 || knownInterruptionCount > 0 else {
                throw CompletedRidePeakPowerEvidenceError.invalidEvidence
            }
        }

        if beganAfterKnownObservationGap,
           knownInterruptionCount == 0 {
            throw CompletedRidePeakPowerEvidenceError.invalidEvidence
        }

        if rideContinuity == .recoveredCheckpoint,
           (!beganAfterKnownObservationGap ||
            observationContinuity != .partialSelectedSourceEvidence ||
            knownInterruptionCount == 0) {
            throw CompletedRidePeakPowerEvidenceError.invalidEvidence
        }
    }

    fileprivate static func authorityPairIsValid(
        identityAuthority: ObservedPowerEnvelopeScopeAuthority,
        evidenceAuthority: ObservedPowerEnvelopeEvidenceAuthority
    ) -> Bool {
        switch (identityAuthority, evidenceAuthority) {
        case (.simulatorQA, .simulatorQA),
             (.verifiedVehicleIdentity, .verifiedVehicleMeasurement):
            true
        default:
            false
        }
    }
}

/// Durable serialized representation of completed ride peak-power evidence.
///
/// A decoded checkpoint is **not** trusted vehicle evidence. It may retain raw
/// authority labels for validation/correlation, but those labels do not acquire
/// domain authority by surviving Codable. Public clients can restore only
/// Simulator-QA evidence. Verified-vehicle restoration requires a package-sealed
/// trusted decode of the durable bytes before the same ride/scope checks run.
public struct CompletedRidePeakPowerCheckpoint: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let sessionID: UUID
    public let rideContinuity: RideSessionContinuity
    public let beganAfterKnownObservationGap: Bool
    public let vehicleIdentityKey: String
    public let confirmedModeKey: String?
    public let identityAuthority: ObservedPowerEnvelopeScopeAuthority
    public let evidenceAuthority: ObservedPowerEnvelopeEvidenceAuthority
    public let powerWatts: Double
    public let acceptedMeasurementCount: Int
    public let peakCandidateMeasurementCount: Int
    public let qualityRejectedMeasurementCount: Int
    public let knownInterruptionCount: Int
    public let observationContinuity: PeakPowerObservationContinuity

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case sessionID
        case rideContinuity
        case beganAfterKnownObservationGap
        case vehicleIdentityKey
        case confirmedModeKey
        case identityAuthority
        case evidenceAuthority
        case powerWatts
        case acceptedMeasurementCount
        case peakCandidateMeasurementCount
        case qualityRejectedMeasurementCount
        case knownInterruptionCount
        case observationContinuity
    }

    private init(
        evidence: CompletedRidePeakPowerEvidence,
        requiredScopeAuthority: ObservedPowerEnvelopeScopeAuthority,
        requiredEvidenceAuthority: ObservedPowerEnvelopeEvidenceAuthority
    ) throws {
        guard evidence.identityAuthority == requiredScopeAuthority,
              evidence.evidenceAuthority == requiredEvidenceAuthority else {
            throw CompletedRidePeakPowerEvidenceError.authorityMismatch
        }

        schemaVersion = Self.currentSchemaVersion
        sessionID = evidence.sessionID
        rideContinuity = evidence.rideContinuity
        beganAfterKnownObservationGap = evidence.beganAfterKnownObservationGap
        vehicleIdentityKey = evidence.vehicleIdentityKey
        confirmedModeKey = evidence.confirmedModeKey
        identityAuthority = evidence.identityAuthority
        evidenceAuthority = evidence.evidenceAuthority
        powerWatts = evidence.powerWatts
        acceptedMeasurementCount = evidence.acceptedMeasurementCount
        peakCandidateMeasurementCount = evidence.peakCandidateMeasurementCount
        qualityRejectedMeasurementCount = evidence.qualityRejectedMeasurementCount
        knownInterruptionCount = evidence.knownInterruptionCount
        observationContinuity = evidence.observationContinuity
    }

    public static func simulatorQA(
        from evidence: CompletedRidePeakPowerEvidence
    ) throws -> Self {
        try Self(
            evidence: evidence,
            requiredScopeAuthority: .simulatorQA,
            requiredEvidenceAuthority: .simulatorQA
        )
    }

    #if SWIFT_PACKAGE
    package static func verifiedVehicleMeasurements(
        from evidence: CompletedRidePeakPowerEvidence
    ) throws -> Self {
        try Self(
            evidence: evidence,
            requiredScopeAuthority: .verifiedVehicleIdentity,
            requiredEvidenceAuthority: .verifiedVehicleMeasurement
        )
    }

    /// Trusted durable decode boundary for verified measurement checkpoints.
    ///
    /// Generic `JSONDecoder` output intentionally remains inert even inside the
    /// package. Persistence integration that intentionally owns verified restore
    /// must enter through this package-only boundary and receive a wrapper that
    /// cannot be constructed by public callers from arbitrary decoded values.
    package static func trustedVerifiedPersistenceDecode(
        from data: Data
    ) throws -> TrustedCompletedRidePeakPowerCheckpoint {
        let checkpoint = try JSONDecoder().decode(Self.self, from: data)
        guard checkpoint.identityAuthority == .verifiedVehicleIdentity,
              checkpoint.evidenceAuthority == .verifiedVehicleMeasurement else {
            throw CompletedRidePeakPowerEvidenceError.authorityMismatch
        }
        return TrustedCompletedRidePeakPowerCheckpoint(checkpoint: checkpoint)
    }
    #else
    fileprivate static func verifiedVehicleMeasurements(
        from evidence: CompletedRidePeakPowerEvidence
    ) throws -> Self {
        try Self(
            evidence: evidence,
            requiredScopeAuthority: .verifiedVehicleIdentity,
            requiredEvidenceAuthority: .verifiedVehicleMeasurement
        )
    }
    #endif

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        do {
            let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
            guard schemaVersion == Self.currentSchemaVersion else {
                throw CompletedRidePeakPowerEvidenceError.unsupportedCheckpointSchema(schemaVersion)
            }

            let identityRaw = try container.decode(String.self, forKey: .identityAuthority)
            let evidenceRaw = try container.decode(String.self, forKey: .evidenceAuthority)
            guard let identityAuthority = ObservedPowerEnvelopeScopeAuthority(rawValue: identityRaw),
                  let evidenceAuthority = ObservedPowerEnvelopeEvidenceAuthority(rawValue: evidenceRaw) else {
                throw CompletedRidePeakPowerEvidenceError.invalidEvidence
            }

            let sessionID = try container.decode(UUID.self, forKey: .sessionID)
            let rideContinuity = try container.decode(RideSessionContinuity.self, forKey: .rideContinuity)
            let beganAfterKnownObservationGap = try container.decode(
                Bool.self,
                forKey: .beganAfterKnownObservationGap
            )
            let vehicleIdentityKey = try container.decode(String.self, forKey: .vehicleIdentityKey)
            let confirmedModeKey = try container.decodeIfPresent(String.self, forKey: .confirmedModeKey)
            let powerWatts = try container.decode(Double.self, forKey: .powerWatts)
            let acceptedMeasurementCount = try container.decode(Int.self, forKey: .acceptedMeasurementCount)
            let peakCandidateMeasurementCount = try container.decode(
                Int.self,
                forKey: .peakCandidateMeasurementCount
            )
            let qualityRejectedMeasurementCount = try container.decode(
                Int.self,
                forKey: .qualityRejectedMeasurementCount
            )
            let knownInterruptionCount = try container.decode(Int.self, forKey: .knownInterruptionCount)
            let observationContinuity = try container.decode(
                PeakPowerObservationContinuity.self,
                forKey: .observationContinuity
            )

            try CompletedRidePeakPowerEvidence.validateFields(
                rideContinuity: rideContinuity,
                beganAfterKnownObservationGap: beganAfterKnownObservationGap,
                vehicleIdentityKey: vehicleIdentityKey,
                confirmedModeKey: confirmedModeKey,
                identityAuthority: identityAuthority,
                evidenceAuthority: evidenceAuthority,
                powerWatts: powerWatts,
                acceptedMeasurementCount: acceptedMeasurementCount,
                peakCandidateMeasurementCount: peakCandidateMeasurementCount,
                qualityRejectedMeasurementCount: qualityRejectedMeasurementCount,
                knownInterruptionCount: knownInterruptionCount,
                observationContinuity: observationContinuity
            )

            self.schemaVersion = schemaVersion
            self.sessionID = sessionID
            self.rideContinuity = rideContinuity
            self.beganAfterKnownObservationGap = beganAfterKnownObservationGap
            self.vehicleIdentityKey = vehicleIdentityKey
            self.confirmedModeKey = confirmedModeKey
            self.identityAuthority = identityAuthority
            self.evidenceAuthority = evidenceAuthority
            self.powerWatts = powerWatts
            self.acceptedMeasurementCount = acceptedMeasurementCount
            self.peakCandidateMeasurementCount = peakCandidateMeasurementCount
            self.qualityRejectedMeasurementCount = qualityRejectedMeasurementCount
            self.knownInterruptionCount = knownInterruptionCount
            self.observationContinuity = observationContinuity
        } catch let error as CompletedRidePeakPowerEvidenceError {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Completed ride peak-power checkpoint is structurally invalid: \(error)."
                )
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(sessionID, forKey: .sessionID)
        try container.encode(rideContinuity, forKey: .rideContinuity)
        try container.encode(beganAfterKnownObservationGap, forKey: .beganAfterKnownObservationGap)
        try container.encode(vehicleIdentityKey, forKey: .vehicleIdentityKey)
        try container.encodeIfPresent(confirmedModeKey, forKey: .confirmedModeKey)
        try container.encode(identityAuthority.rawValue, forKey: .identityAuthority)
        try container.encode(evidenceAuthority.rawValue, forKey: .evidenceAuthority)
        try container.encode(powerWatts, forKey: .powerWatts)
        try container.encode(acceptedMeasurementCount, forKey: .acceptedMeasurementCount)
        try container.encode(peakCandidateMeasurementCount, forKey: .peakCandidateMeasurementCount)
        try container.encode(qualityRejectedMeasurementCount, forKey: .qualityRejectedMeasurementCount)
        try container.encode(knownInterruptionCount, forKey: .knownInterruptionCount)
        try container.encode(observationContinuity, forKey: .observationContinuity)
    }

    public func restoredSimulatorQA(
        completedRide: CompletedRideEvidence,
        expectedScope: ObservedPowerEnvelopeScope
    ) throws -> CompletedRidePeakPowerEvidence {
        try restoredEvidence(
            completedRide: completedRide,
            expectedScope: expectedScope,
            requiredScopeAuthority: .simulatorQA,
            requiredEvidenceAuthority: .simulatorQA
        )
    }

    #if SWIFT_PACKAGE
    /// A generic decoded checkpoint is intentionally never sufficient to regain
    /// verified measurement authority. Callers that own the package persistence
    /// boundary must use `trustedVerifiedPersistenceDecode(from:)` and restore
    /// through the returned trusted wrapper instead.
    package func restoredVerifiedVehicleMeasurement(
        completedRide: CompletedRideEvidence,
        expectedScope: ObservedPowerEnvelopeScope
    ) throws -> CompletedRidePeakPowerEvidence {
        _ = completedRide
        _ = expectedScope
        throw CompletedRidePeakPowerEvidenceError.untrustedCheckpointOrigin
    }
    #else
    fileprivate func restoredVerifiedVehicleMeasurement(
        completedRide: CompletedRideEvidence,
        expectedScope: ObservedPowerEnvelopeScope
    ) throws -> CompletedRidePeakPowerEvidence {
        _ = completedRide
        _ = expectedScope
        throw CompletedRidePeakPowerEvidenceError.untrustedCheckpointOrigin
    }
    #endif

    fileprivate func restoredEvidence(
        completedRide: CompletedRideEvidence,
        expectedScope: ObservedPowerEnvelopeScope,
        requiredScopeAuthority: ObservedPowerEnvelopeScopeAuthority,
        requiredEvidenceAuthority: ObservedPowerEnvelopeEvidenceAuthority
    ) throws -> CompletedRidePeakPowerEvidence {
        guard expectedScope.identityAuthority == requiredScopeAuthority,
              identityAuthority == requiredScopeAuthority,
              evidenceAuthority == requiredEvidenceAuthority else {
            throw CompletedRidePeakPowerEvidenceError.authorityMismatch
        }
        guard expectedScope.vehicleIdentityKey == vehicleIdentityKey,
              expectedScope.confirmedModeKey == confirmedModeKey else {
            throw CompletedRidePeakPowerEvidenceError.scopeMismatch
        }
        guard completedRide.sessionID == sessionID else {
            throw CompletedRidePeakPowerEvidenceError.sessionMismatch
        }
        guard completedRide.continuity == rideContinuity else {
            throw CompletedRidePeakPowerEvidenceError.continuityMismatch
        }

        return try CompletedRidePeakPowerEvidence(
            sessionID: sessionID,
            rideContinuity: rideContinuity,
            beganAfterKnownObservationGap: beganAfterKnownObservationGap,
            vehicleIdentityKey: vehicleIdentityKey,
            confirmedModeKey: confirmedModeKey,
            identityAuthority: requiredScopeAuthority,
            evidenceAuthority: requiredEvidenceAuthority,
            powerWatts: powerWatts,
            acceptedMeasurementCount: acceptedMeasurementCount,
            peakCandidateMeasurementCount: peakCandidateMeasurementCount,
            qualityRejectedMeasurementCount: qualityRejectedMeasurementCount,
            knownInterruptionCount: knownInterruptionCount,
            observationContinuity: observationContinuity
        )
    }
}

#if SWIFT_PACKAGE
/// Package-sealed proof that verified checkpoint bytes entered through the
/// explicit trusted persistence decode boundary rather than ordinary Codable.
///
/// This is a software provenance boundary, not hostile-storage attestation and
/// not physical ES80 proof. It prevents generic decoded values from being
/// upgraded merely because their labels match a trusted vehicle scope.
package struct TrustedCompletedRidePeakPowerCheckpoint: Sendable {
    fileprivate let checkpoint: CompletedRidePeakPowerCheckpoint

    fileprivate init(checkpoint: CompletedRidePeakPowerCheckpoint) {
        self.checkpoint = checkpoint
    }

    package func restoredVerifiedVehicleMeasurement(
        completedRide: CompletedRideEvidence,
        expectedScope: ObservedPowerEnvelopeScope
    ) throws -> CompletedRidePeakPowerEvidence {
        try checkpoint.restoredEvidence(
            completedRide: completedRide,
            expectedScope: expectedScope,
            requiredScopeAuthority: .verifiedVehicleIdentity,
            requiredEvidenceAuthority: .verifiedVehicleMeasurement
        )
    }
}
#endif
