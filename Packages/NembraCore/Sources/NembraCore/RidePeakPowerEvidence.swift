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
}

/// Trusted accepted peak-power evidence bound to one immutable completed ride.
///
/// This value is intentionally **not Decodable**. Arbitrary durable bytes must
/// first cross a checkpoint authority boundary. Public checkpoint decoding is
/// deliberately Simulator-QA-only; verified durable bytes can cross back into
/// physical authority only through package-owned restore code with an independently
/// trusted exact ride and verified scope.
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
/// The public Codable surface is deliberately **Simulator-QA only**. Authority
/// labels supplied by arbitrary decoded bytes cannot mint a verified checkpoint
/// object. Verified durable bytes first decode into a private non-authoritative
/// wire value and cross into trusted evidence only inside the package-owned
/// restore operation, which also requires the exact trusted completed ride and
/// verified scope. This is a compile-time/product authority boundary, not a
/// cryptographic authenticity claim about storage bytes.
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

    /// Non-authoritative persistence DTO. Decoding this value proves only that
    /// bytes have the expected shape; it does not confer Simulator or physical
    /// evidence authority by itself.
    private struct StoredWire: Codable, Equatable, Sendable {
        let schemaVersion: Int
        let sessionID: UUID
        let rideContinuity: RideSessionContinuity
        let beganAfterKnownObservationGap: Bool
        let vehicleIdentityKey: String
        let confirmedModeKey: String?
        let identityAuthority: String
        let evidenceAuthority: String
        let powerWatts: Double
        let acceptedMeasurementCount: Int
        let peakCandidateMeasurementCount: Int
        let qualityRejectedMeasurementCount: Int
        let knownInterruptionCount: Int
        let observationContinuity: PeakPowerObservationContinuity

        init(checkpoint: CompletedRidePeakPowerCheckpoint) {
            schemaVersion = checkpoint.schemaVersion
            sessionID = checkpoint.sessionID
            rideContinuity = checkpoint.rideContinuity
            beganAfterKnownObservationGap = checkpoint.beganAfterKnownObservationGap
            vehicleIdentityKey = checkpoint.vehicleIdentityKey
            confirmedModeKey = checkpoint.confirmedModeKey
            identityAuthority = checkpoint.identityAuthority.rawValue
            evidenceAuthority = checkpoint.evidenceAuthority.rawValue
            powerWatts = checkpoint.powerWatts
            acceptedMeasurementCount = checkpoint.acceptedMeasurementCount
            peakCandidateMeasurementCount = checkpoint.peakCandidateMeasurementCount
            qualityRejectedMeasurementCount = checkpoint.qualityRejectedMeasurementCount
            knownInterruptionCount = checkpoint.knownInterruptionCount
            observationContinuity = checkpoint.observationContinuity
        }
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

    private init(
        storedWire: StoredWire,
        requiredScopeAuthority: ObservedPowerEnvelopeScopeAuthority,
        requiredEvidenceAuthority: ObservedPowerEnvelopeEvidenceAuthority
    ) throws {
        guard storedWire.schemaVersion == Self.currentSchemaVersion else {
            throw CompletedRidePeakPowerEvidenceError.unsupportedCheckpointSchema(storedWire.schemaVersion)
        }
        guard let identityAuthority = ObservedPowerEnvelopeScopeAuthority(
            rawValue: storedWire.identityAuthority
        ),
        let evidenceAuthority = ObservedPowerEnvelopeEvidenceAuthority(
            rawValue: storedWire.evidenceAuthority
        ) else {
            throw CompletedRidePeakPowerEvidenceError.invalidEvidence
        }
        guard identityAuthority == requiredScopeAuthority,
              evidenceAuthority == requiredEvidenceAuthority else {
            throw CompletedRidePeakPowerEvidenceError.authorityMismatch
        }

        try CompletedRidePeakPowerEvidence.validateFields(
            rideContinuity: storedWire.rideContinuity,
            beganAfterKnownObservationGap: storedWire.beganAfterKnownObservationGap,
            vehicleIdentityKey: storedWire.vehicleIdentityKey,
            confirmedModeKey: storedWire.confirmedModeKey,
            identityAuthority: identityAuthority,
            evidenceAuthority: evidenceAuthority,
            powerWatts: storedWire.powerWatts,
            acceptedMeasurementCount: storedWire.acceptedMeasurementCount,
            peakCandidateMeasurementCount: storedWire.peakCandidateMeasurementCount,
            qualityRejectedMeasurementCount: storedWire.qualityRejectedMeasurementCount,
            knownInterruptionCount: storedWire.knownInterruptionCount,
            observationContinuity: storedWire.observationContinuity
        )

        schemaVersion = storedWire.schemaVersion
        sessionID = storedWire.sessionID
        rideContinuity = storedWire.rideContinuity
        beganAfterKnownObservationGap = storedWire.beganAfterKnownObservationGap
        vehicleIdentityKey = storedWire.vehicleIdentityKey
        confirmedModeKey = storedWire.confirmedModeKey
        self.identityAuthority = identityAuthority
        self.evidenceAuthority = evidenceAuthority
        powerWatts = storedWire.powerWatts
        acceptedMeasurementCount = storedWire.acceptedMeasurementCount
        peakCandidateMeasurementCount = storedWire.peakCandidateMeasurementCount
        qualityRejectedMeasurementCount = storedWire.qualityRejectedMeasurementCount
        knownInterruptionCount = storedWire.knownInterruptionCount
        observationContinuity = storedWire.observationContinuity
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

    /// Trusted durable verified restore boundary. The input bytes first become a
    /// non-authoritative wire value; verified authority is conferred only after
    /// structural validation and exact independently trusted ride/scope checks.
    package static func restoreVerifiedVehicleMeasurement(
        fromPersistedData data: Data,
        completedRide: CompletedRideEvidence,
        expectedScope: ObservedPowerEnvelopeScope
    ) throws -> CompletedRidePeakPowerEvidence {
        let storedWire = try JSONDecoder().decode(StoredWire.self, from: data)
        let checkpoint = try Self(
            storedWire: storedWire,
            requiredScopeAuthority: .verifiedVehicleIdentity,
            requiredEvidenceAuthority: .verifiedVehicleMeasurement
        )
        return try checkpoint.restoredVerifiedVehicleMeasurement(
            completedRide: completedRide,
            expectedScope: expectedScope
        )
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
        do {
            let storedWire = try StoredWire(from: decoder)
            try self.init(
                storedWire: storedWire,
                requiredScopeAuthority: .simulatorQA,
                requiredEvidenceAuthority: .simulatorQA
            )
        } catch let error as CompletedRidePeakPowerEvidenceError {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Completed ride peak-power checkpoint is not a valid public Simulator-QA checkpoint: \(error)."
                )
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        try StoredWire(checkpoint: self).encode(to: encoder)
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
    package func restoredVerifiedVehicleMeasurement(
        completedRide: CompletedRideEvidence,
        expectedScope: ObservedPowerEnvelopeScope
    ) throws -> CompletedRidePeakPowerEvidence {
        try restoredEvidence(
            completedRide: completedRide,
            expectedScope: expectedScope,
            requiredScopeAuthority: .verifiedVehicleIdentity,
            requiredEvidenceAuthority: .verifiedVehicleMeasurement
        )
    }
    #else
    fileprivate func restoredVerifiedVehicleMeasurement(
        completedRide: CompletedRideEvidence,
        expectedScope: ObservedPowerEnvelopeScope
    ) throws -> CompletedRidePeakPowerEvidence {
        try restoredEvidence(
            completedRide: completedRide,
            expectedScope: expectedScope,
            requiredScopeAuthority: .verifiedVehicleIdentity,
            requiredEvidenceAuthority: .verifiedVehicleMeasurement
        )
    }
    #endif

    private func restoredEvidence(
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
