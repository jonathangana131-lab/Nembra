import Foundation

public enum RideHistoryDurationCommitResult: Equatable, Sendable {
    case inserted
    case alreadyPresent
}

public enum RideHistoryDurationStoreError: Error, Equatable, Sendable {
    case sessionConflict(UUID)
}

/// Durable supplemental duration fields for one completed history entry.
///
/// This record intentionally stores only `CompletedRideDurationEvidenceArchive`,
/// never authoritative `CompletedRideDurationEvidence`. Decoding persisted bytes
/// therefore reconstructs structurally validated history data without granting
/// process-local monotonic-duration authority.
public struct RideHistoryDurationRecord: Codable, Equatable, Sendable {
    public let archive: CompletedRideDurationEvidenceArchive

    public init(archive: CompletedRideDurationEvidenceArchive) {
        self.archive = archive
    }

    public init(authoritativeEvidence evidence: CompletedRideDurationEvidence) {
        self.archive = evidence.persistenceArchive
    }

    public var sessionID: UUID { archive.sessionID }
}

/// Storage contract for supplemental completed-ride duration history.
///
/// Implementations must be immutable by session identity. Replaying an equivalent
/// archive returns `alreadyPresent`; the same session UUID with different archive
/// fields fails rather than overwriting history.
public protocol RideHistoryDurationStore: Sendable {
    func commit(_ record: RideHistoryDurationRecord) async throws -> RideHistoryDurationCommitResult
    func record(sessionID: UUID) async throws -> RideHistoryDurationRecord?
}

public enum RideHistoryDurationAttachmentError: Error, Equatable, Sendable {
    case completedRideMismatch(UUID)
}

/// Validated persisted-history association between one immutable completed ride
/// and one non-authoritative duration archive.
///
/// The attachment is deliberately not Codable and deliberately exposes no API that
/// promotes its archive back into `CompletedRideDurationEvidence`. It proves only
/// that the stored fields belong to the same immutable ride identity/continuity.
/// A future trusted restore boundary must independently re-establish production
/// duration authority before Statistics or other authoritative consumers may use it.
public struct RideHistoryDurationAttachment: Equatable, Sendable {
    public let historyRecord: RideHistoryRecord
    public let durationRecord: RideHistoryDurationRecord

#if SWIFT_PACKAGE
    package init(
        historyRecord: RideHistoryRecord,
        durationRecord: RideHistoryDurationRecord
    ) throws {
        try Self.validate(historyRecord: historyRecord, durationRecord: durationRecord)
        self.historyRecord = historyRecord
        self.durationRecord = durationRecord
    }
#else
    fileprivate init(
        historyRecord: RideHistoryRecord,
        durationRecord: RideHistoryDurationRecord
    ) throws {
        try Self.validate(historyRecord: historyRecord, durationRecord: durationRecord)
        self.historyRecord = historyRecord
        self.durationRecord = durationRecord
    }
#endif

    public var sessionID: UUID { historyRecord.sessionID }

    private static func validate(
        historyRecord: RideHistoryRecord,
        durationRecord: RideHistoryDurationRecord
    ) throws {
        let archive = durationRecord.archive
        guard archive.sessionID == historyRecord.sessionID,
              archive.rideContinuity == historyRecord.evidence.continuity else {
            throw RideHistoryDurationAttachmentError.completedRideMismatch(historyRecord.sessionID)
        }
    }
}

public enum RideHistoryDurationCommitCoordinatorError: Error, Equatable, Sendable {
    case missingCompletedRide(UUID)
    case completedRideMismatch(UUID)
    case durableVerificationFailed(UUID)
}

/// One-way commit boundary from accepted monotonic duration evidence to durable
/// non-authoritative archive history.
///
/// The base ride must already exist. The incoming authoritative evidence is first
/// validated against that exact completed ride, converted one-way to its archive,
/// committed idempotently, and read back for exact durable equivalence. Reads return
/// only `RideHistoryDurationAttachment`; this coordinator intentionally contains no
/// archive-to-authority restore path.
public actor RideHistoryDurationCommitCoordinator {
    private let historyStore: any RideHistoryStore
    private let durationStore: any RideHistoryDurationStore

    public init(
        historyStore: any RideHistoryStore,
        durationStore: any RideHistoryDurationStore
    ) {
        self.historyStore = historyStore
        self.durationStore = durationStore
    }

    @discardableResult
    public func commit(
        _ evidence: CompletedRideDurationEvidence
    ) async throws -> RideHistoryDurationCommitResult {
        guard let historyRecord = try await historyStore.record(sessionID: evidence.sessionID) else {
            throw RideHistoryDurationCommitCoordinatorError.missingCompletedRide(evidence.sessionID)
        }

        do {
            try evidence.validate(against: historyRecord.evidence)
        } catch {
            throw RideHistoryDurationCommitCoordinatorError.completedRideMismatch(evidence.sessionID)
        }

        let record = RideHistoryDurationRecord(authoritativeEvidence: evidence)
        let result = try await durationStore.commit(record)

        guard try await durationStore.record(sessionID: record.sessionID) == record else {
            throw RideHistoryDurationCommitCoordinatorError.durableVerificationFailed(record.sessionID)
        }

        return result
    }

    /// Returns a validated persisted-data association only. The duration remains an
    /// archive and does not regain `CompletedRideDurationEvidence` authority.
    public func attachment(
        sessionID: UUID
    ) async throws -> RideHistoryDurationAttachment? {
        let historyRecord = try await historyStore.record(sessionID: sessionID)
        let durationRecord = try await durationStore.record(sessionID: sessionID)

        switch (historyRecord, durationRecord) {
        case (nil, nil), (.some, nil):
            return nil
        case (nil, .some):
            throw RideHistoryDurationCommitCoordinatorError.missingCompletedRide(sessionID)
        case let (.some(historyRecord), .some(durationRecord)):
            do {
                return try RideHistoryDurationAttachment(
                    historyRecord: historyRecord,
                    durationRecord: durationRecord
                )
            } catch {
                throw RideHistoryDurationCommitCoordinatorError.completedRideMismatch(sessionID)
            }
        }
    }
}
