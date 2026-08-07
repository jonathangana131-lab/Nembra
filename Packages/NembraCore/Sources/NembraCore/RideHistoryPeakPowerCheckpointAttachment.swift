import Foundation

public enum RideHistoryPeakPowerCheckpointCommitResult: Equatable, Sendable {
    case inserted
    case alreadyPresent
}

/// Durable key for one completed ride and one exact observed-power scope.
///
/// Mode is part of identity because one ride may legitimately contain multiple
/// confirmed-mode power envelopes. Authority is also part of identity so
/// Simulator-QA state can never overwrite verified-vehicle checkpoint bytes.
public struct RideHistoryPeakPowerCheckpointRecordID: Codable, Equatable, Hashable, Sendable {
    public let sessionID: UUID
    public let vehicleIdentityKey: String
    public let confirmedModeKey: String?
    public let identityAuthority: ObservedPowerEnvelopeScopeAuthority
    public let evidenceAuthority: ObservedPowerEnvelopeEvidenceAuthority

    fileprivate init(checkpoint: CompletedRidePeakPowerCheckpoint) {
        sessionID = checkpoint.sessionID
        vehicleIdentityKey = checkpoint.vehicleIdentityKey
        confirmedModeKey = checkpoint.confirmedModeKey
        identityAuthority = checkpoint.identityAuthority
        evidenceAuthority = checkpoint.evidenceAuthority
    }

    private enum CodingKeys: String, CodingKey {
        case sessionID
        case vehicleIdentityKey
        case confirmedModeKey
        case identityAuthority
        case evidenceAuthority
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let vehicleIdentityKey = try container.decode(String.self, forKey: .vehicleIdentityKey)
        let confirmedModeKey = try container.decodeIfPresent(String.self, forKey: .confirmedModeKey)
        let identityRaw = try container.decode(String.self, forKey: .identityAuthority)
        let evidenceRaw = try container.decode(String.self, forKey: .evidenceAuthority)

        guard !vehicleIdentityKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              confirmedModeKey.map({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ?? true,
              let identityAuthority = ObservedPowerEnvelopeScopeAuthority(rawValue: identityRaw),
              let evidenceAuthority = ObservedPowerEnvelopeEvidenceAuthority(rawValue: evidenceRaw),
              Self.authorityPairIsValid(
                identityAuthority: identityAuthority,
                evidenceAuthority: evidenceAuthority
              ) else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Invalid ride-history peak-power checkpoint identity."
                )
            )
        }

        sessionID = try container.decode(UUID.self, forKey: .sessionID)
        self.vehicleIdentityKey = vehicleIdentityKey
        self.confirmedModeKey = confirmedModeKey
        self.identityAuthority = identityAuthority
        self.evidenceAuthority = evidenceAuthority
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sessionID, forKey: .sessionID)
        try container.encode(vehicleIdentityKey, forKey: .vehicleIdentityKey)
        try container.encodeIfPresent(confirmedModeKey, forKey: .confirmedModeKey)
        try container.encode(identityAuthority.rawValue, forKey: .identityAuthority)
        try container.encode(evidenceAuthority.rawValue, forKey: .evidenceAuthority)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(sessionID)
        hasher.combine(vehicleIdentityKey)
        hasher.combine(confirmedModeKey)
        hasher.combine(identityAuthority.rawValue)
        hasher.combine(evidenceAuthority.rawValue)
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

public enum RideHistoryPeakPowerCheckpointStoreError: Error, Equatable, Sendable {
    case recordConflict(RideHistoryPeakPowerCheckpointRecordID)
}

/// Immutable raw persisted sidecar. `checkpoint` is intentionally not promoted
/// to `CompletedRidePeakPowerEvidence` here: verified authority must be restored
/// later through a separately trusted exact scope.
public struct RideHistoryPeakPowerCheckpointRecord: Codable, Equatable, Sendable {
    public let checkpoint: CompletedRidePeakPowerCheckpoint

    public init(checkpoint: CompletedRidePeakPowerCheckpoint) {
        self.checkpoint = checkpoint
    }

    public var recordID: RideHistoryPeakPowerCheckpointRecordID {
        RideHistoryPeakPowerCheckpointRecordID(checkpoint: checkpoint)
    }

    public var sessionID: UUID { checkpoint.sessionID }
}

public protocol RideHistoryPeakPowerCheckpointStore: Sendable {
    func commit(
        _ record: RideHistoryPeakPowerCheckpointRecord
    ) async throws -> RideHistoryPeakPowerCheckpointCommitResult

    func record(
        id: RideHistoryPeakPowerCheckpointRecordID
    ) async throws -> RideHistoryPeakPowerCheckpointRecord?

    func records(
        sessionID: UUID
    ) async throws -> [RideHistoryPeakPowerCheckpointRecord]
}

public enum RideHistoryPeakPowerCheckpointJoinError: Error, Equatable, Sendable {
    case completedRideMismatch(RideHistoryPeakPowerCheckpointRecordID)
}

/// Freshly validated association between base ride history and one inert
/// scope-specific checkpoint. This is deliberately not Codable and deliberately
/// does not expose an authority-bearing restored peak-power value.
public struct RideHistoryPeakPowerJoinedCheckpoint: Equatable, Sendable {
    public let historyRecord: RideHistoryRecord
    public let peakPowerRecord: RideHistoryPeakPowerCheckpointRecord

    public init(
        historyRecord: RideHistoryRecord,
        peakPowerRecord: RideHistoryPeakPowerCheckpointRecord
    ) throws {
        guard peakPowerRecord.checkpoint.sessionID == historyRecord.sessionID,
              peakPowerRecord.checkpoint.rideContinuity == historyRecord.evidence.continuity else {
            throw RideHistoryPeakPowerCheckpointJoinError.completedRideMismatch(
                peakPowerRecord.recordID
            )
        }
        self.historyRecord = historyRecord
        self.peakPowerRecord = peakPowerRecord
    }

    public var recordID: RideHistoryPeakPowerCheckpointRecordID {
        peakPowerRecord.recordID
    }
}

public enum RideHistoryPeakPowerCheckpointCommitCoordinatorError: Error, Equatable, Sendable {
    case missingCompletedRide(UUID)
    case completedRideMismatch(RideHistoryPeakPowerCheckpointRecordID)
    case authorityMismatch
    case durableVerificationFailed(RideHistoryPeakPowerCheckpointRecordID)
    case storeReturnedForeignSession(
        expected: UUID,
        actual: RideHistoryPeakPowerCheckpointRecordID
    )
    case duplicateRecordIdentity(RideHistoryPeakPowerCheckpointRecordID)
}

/// Persists immutable scope-specific peak-power checkpoint bytes only after the
/// authoritative completed ride is already durable.
///
/// This actor intentionally has no verified restore API. A future reader must
/// supply an independently re-established trusted exact scope before a verified
/// checkpoint can become authority-bearing domain evidence again.
public actor RideHistoryPeakPowerCheckpointCommitCoordinator {
    private let historyStore: any RideHistoryStore
    private let peakPowerStore: any RideHistoryPeakPowerCheckpointStore

    public init(
        historyStore: any RideHistoryStore,
        peakPowerStore: any RideHistoryPeakPowerCheckpointStore
    ) {
        self.historyStore = historyStore
        self.peakPowerStore = peakPowerStore
    }

    @discardableResult
    public func commit(
        _ evidence: CompletedRidePeakPowerEvidence
    ) async throws -> RideHistoryPeakPowerCheckpointCommitResult {
        guard let historyRecord = try await historyStore.record(sessionID: evidence.sessionID) else {
            throw RideHistoryPeakPowerCheckpointCommitCoordinatorError.missingCompletedRide(
                evidence.sessionID
            )
        }

        do {
            try evidence.validate(against: historyRecord.evidence)
        } catch {
            throw RideHistoryPeakPowerCheckpointCommitCoordinatorError.completedRideMismatch(
                RideHistoryPeakPowerCheckpointRecordID(
                    checkpoint: try checkpoint(from: evidence)
                )
            )
        }

        let checkpoint = try checkpoint(from: evidence)
        let record = RideHistoryPeakPowerCheckpointRecord(checkpoint: checkpoint)
        let result = try await peakPowerStore.commit(record)
        guard try await peakPowerStore.record(id: record.recordID) == record else {
            throw RideHistoryPeakPowerCheckpointCommitCoordinatorError.durableVerificationFailed(
                record.recordID
            )
        }
        return result
    }

    /// Returns raw inert checkpoints only after revalidating their base ride
    /// identity/continuity. No whole-ride max or verified-authority reconstruction
    /// occurs here.
    public func joinedCheckpoints(
        sessionID: UUID
    ) async throws -> [RideHistoryPeakPowerJoinedCheckpoint] {
        let historyRecord = try await historyStore.record(sessionID: sessionID)
        let records = try await peakPowerStore.records(sessionID: sessionID)

        if historyRecord == nil {
            guard records.isEmpty else {
                throw RideHistoryPeakPowerCheckpointCommitCoordinatorError.missingCompletedRide(
                    sessionID
                )
            }
            return []
        }
        guard let historyRecord else { return [] }

        var seen: Set<RideHistoryPeakPowerCheckpointRecordID> = []
        var joined: [RideHistoryPeakPowerJoinedCheckpoint] = []
        joined.reserveCapacity(records.count)

        for record in records {
            guard record.sessionID == sessionID else {
                throw RideHistoryPeakPowerCheckpointCommitCoordinatorError.storeReturnedForeignSession(
                    expected: sessionID,
                    actual: record.recordID
                )
            }
            guard seen.insert(record.recordID).inserted else {
                throw RideHistoryPeakPowerCheckpointCommitCoordinatorError.duplicateRecordIdentity(
                    record.recordID
                )
            }

            do {
                joined.append(
                    try RideHistoryPeakPowerJoinedCheckpoint(
                        historyRecord: historyRecord,
                        peakPowerRecord: record
                    )
                )
            } catch {
                throw RideHistoryPeakPowerCheckpointCommitCoordinatorError.completedRideMismatch(
                    record.recordID
                )
            }
        }

        return joined
    }

    private func checkpoint(
        from evidence: CompletedRidePeakPowerEvidence
    ) throws -> CompletedRidePeakPowerCheckpoint {
        switch (evidence.identityAuthority, evidence.evidenceAuthority) {
        case (.simulatorQA, .simulatorQA):
            return try .simulatorQA(from: evidence)
        case (.verifiedVehicleIdentity, .verifiedVehicleMeasurement):
            return try .verifiedVehicleMeasurements(from: evidence)
        default:
            throw RideHistoryPeakPowerCheckpointCommitCoordinatorError.authorityMismatch
        }
    }
}
