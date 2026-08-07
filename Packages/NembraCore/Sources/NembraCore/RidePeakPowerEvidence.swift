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
/// This value is intentionally **not Decodable**. Arbitrary durable bytes first
/// remain a non-authoritative wire representation. Public Codable import can only
/// construct Simulator-QA checkpoints; verified durable bytes require the
/// package-sealed verified persistence conversion before they can regain authority.
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
/// Public Codable import is deliberately Simulator-QA only. Verified disk bytes
/// are decoded into a non-authoritative wire DTO, then converted through the
/// package-sealed verified persistence boundary. This prevents authority labels in
/// arbitrary JSON from constructing a verified checkpoint at all.
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

    /// Non-authoritative disk shape. Decoding this wire does not create any
    /// trusted measurement evidence; package verified persistence must explicitly
    /// convert it using the required verified authority pair.
    private struct StoredCheckpointWire: Codable, Equatable, Sendable {
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
        stored wire: StoredCheckpointWire,
        requiredScopeAuthority: ObservedPowerEnvelopeScopeAuthority,
        requiredEvidenceAuthority: ObservedPowerEnvelopeEvidenceAuthority
    ) throws {
        guard wire.schemaVersion == Self.currentSchemaVersion else {
            throw CompletedRidePeakPowerEvidenceError.unsupportedCheckpointSchema(wire.schemaVersion)
        }
        guard let identityAuthority = ObservedPowerEnvelopeScopeAuthority(rawValue: wire.identityAuthority),
              let evidenceAuthority = ObservedPowerEnvelopeEvidenceAuthority(rawValue: wire.evidenceAuthority) else {
            throw CompletedRidePeakPowerEvidenceError.invalidEvidence
        }
        guard identityAuthority == requiredScopeAuthority,
              evidenceAuthority == requiredEvidenceAuthority else {
            throw CompletedRidePeakPowerEvidenceError.authorityMismatch
        }

        try CompletedRidePeakPowerEvidence.validateFields(
            rideContinuity: wire.rideContinuity,
            beganAfterKnownObservationGap: wire.beganAfterKnownObservationGap,
            vehicleIdentityKey: wire.vehicleIdentityKey,
            confirmedModeKey: wire.confirmedModeKey,
            identityAuthority: identityAuthority,
            evidenceAuthority: evidenceAuthority,
            powerWatts: wire.powerWatts,
            acceptedMeasurementCount: wire.acceptedMeasurementCount,
            peakCandidateMeasurementCount: wire.peakCandidateMeasurementCount,
            qualityRejectedMeasurementCount: wire.qualityRejectedMeasurementCount,
            knownInterruptionCount: wire.knownInterruptionCount,
            observationContinuity: wire.observationContinuity
        )

        schemaVersion = wire.schemaVersion
        sessionID = wire.sessionID
        rideContinuity = wire.rideContinuity
        beganAfterKnownObservationGap = wire.beganAfterKnownObservationGap
        vehicleIdentityKey = wire.vehicleIdentityKey
        confirmedModeKey = wire.confirmedModeKey
        self.identityAuthority = identityAuthority
        self.evidenceAuthority = evidenceAuthority
        powerWatts = wire.powerWatts
        acceptedMeasurementCount = wire.acceptedMeasurementCount
        peakCandidateMeasurementCount = wire.peakCandidateMeasurementCount
        qualityRejectedMeasurementCount = wire.qualityRejectedMeasurementCount
        knownInterruptionCount = wire.knownInterruptionCount
        observationContinuity = wire.observationContinuity
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

    /// Trusted verified load path. Durable bytes remain a non-authoritative wire
    /// until this package-only conversion validates the exact verified authority
    /// pair and all structural evidence invariants.
    package static func trustedVerifiedPersistenceDecode(
        from data: Data
    ) throws -> Self {
        let wire = try JSONDecoder().decode(StoredCheckpointWire.self, from: data)
        return try Self(
            stored: wire,
            requiredScopeAuthority: .verifiedVehicleIdentity,
            requiredEvidenceAuthority: .verifiedVehicleMeasurement
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
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let wire = StoredCheckpointWire(
                schemaVersion: try container.decode(Int.self, forKey: .schemaVersion),
                sessionID: try container.decode(UUID.self, forKey: .sessionID),
                rideContinuity: try container.decode(RideSessionContinuity.self, forKey: .rideContinuity),
                beganAfterKnownObservationGap: try container.decode(
                    Bool.self,
                    forKey: .beganAfterKnownObservationGap
                ),
                vehicleIdentityKey: try container.decode(String.self, forKey: .vehicleIdentityKey),
                confirmedModeKey: try container.decodeIfPresent(String.self, forKey: .confirmedModeKey),
                identityAuthority: try container.decode(String.self, forKey: .identityAuthority),
                evidenceAuthority: try container.decode(String.self, forKey: .evidenceAuthority),
                powerWatts: try container.decode(Double.self, forKey: .powerWatts),
                acceptedMeasurementCount: try container.decode(
                    Int.self,
                    forKey: .acceptedMeasurementCount
                ),
                peakCandidateMeasurementCount: try container.decode(
                    Int.self,
                    forKey: .peakCandidateMeasurementCount
                ),
                qualityRejectedMeasurementCount: try container.decode(
                    Int.self,
                    forKey: .qualityRejectedMeasurementCount
                ),
                knownInterruptionCount: try container.decode(Int.self, forKey: .knownInterruptionCount),
                observationContinuity: try container.decode(
                    PeakPowerObservationContinuity.self,
                    forKey: .observationContinuity
                )
            )

            self = try Self(
                stored: wire,
                requiredScopeAuthority: .simulatorQA,
                requiredEvidenceAuthority: .simulatorQA
            )
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
