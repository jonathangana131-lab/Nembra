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
    case invalidEvidence
}

/// Durable accepted peak-power evidence bound to one immutable completed ride.
///
/// Process-local receipt sequence and uptime are deliberately stripped. They are
/// ordering evidence inside one acquisition process, and the current accepted
/// power observation does not carry a mechanically bound source-generation ID
/// that would make those clocks meaningful after relaunch. Durable history keeps
/// only the accepted observed maximum, exact vehicle/mode scope identity,
/// authority, evidence-loss counts, and ride identity/continuity.
///
/// This remains an *observed* peak over retained coverage. It is not a rated
/// motor/controller maximum, learned full-power ceiling, throttle signal, or
/// proof of the unobserved continuous-time physical maximum.
public struct CompletedRidePeakPowerEvidence: Codable, Equatable, Sendable {
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

    private init(
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
        guard !vehicleIdentityKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CompletedRidePeakPowerEvidenceError.invalidEvidence
        }
        if let confirmedModeKey,
           confirmedModeKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw CompletedRidePeakPowerEvidenceError.invalidEvidence
        }

        guard Self.authorityPairIsValid(
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

    private enum CodingKeys: String, CodingKey {
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

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        do {
            let identityRaw = try container.decode(String.self, forKey: .identityAuthority)
            let evidenceRaw = try container.decode(String.self, forKey: .evidenceAuthority)
            guard let identityAuthority = ObservedPowerEnvelopeScopeAuthority(rawValue: identityRaw),
                  let evidenceAuthority = ObservedPowerEnvelopeEvidenceAuthority(rawValue: evidenceRaw) else {
                throw CompletedRidePeakPowerEvidenceError.invalidEvidence
            }

            try self.init(
                sessionID: container.decode(UUID.self, forKey: .sessionID),
                rideContinuity: container.decode(RideSessionContinuity.self, forKey: .rideContinuity),
                beganAfterKnownObservationGap: container.decode(
                    Bool.self,
                    forKey: .beganAfterKnownObservationGap
                ),
                vehicleIdentityKey: container.decode(String.self, forKey: .vehicleIdentityKey),
                confirmedModeKey: container.decodeIfPresent(String.self, forKey: .confirmedModeKey),
                identityAuthority: identityAuthority,
                evidenceAuthority: evidenceAuthority,
                powerWatts: container.decode(Double.self, forKey: .powerWatts),
                acceptedMeasurementCount: container.decode(Int.self, forKey: .acceptedMeasurementCount),
                peakCandidateMeasurementCount: container.decode(
                    Int.self,
                    forKey: .peakCandidateMeasurementCount
                ),
                qualityRejectedMeasurementCount: container.decode(
                    Int.self,
                    forKey: .qualityRejectedMeasurementCount
                ),
                knownInterruptionCount: container.decode(Int.self, forKey: .knownInterruptionCount),
                observationContinuity: container.decode(
                    PeakPowerObservationContinuity.self,
                    forKey: .observationContinuity
                )
            )
        } catch let error as CompletedRidePeakPowerEvidenceError {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Completed ride peak-power evidence is structurally invalid: \(error)."
                )
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
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

    private static func authorityPairIsValid(
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
