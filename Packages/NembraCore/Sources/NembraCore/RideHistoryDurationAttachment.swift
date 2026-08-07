import Foundation

public enum RideHistoryDurationCommitResult: Equatable, Sendable {
    case inserted
    case alreadyPresent
}

public enum RideHistoryDurationStoreError: Error, Equatable, Sendable {
    case sessionConflict(UUID)
}

/// Immutable supplemental duration evidence for one completed history entry.
///
/// Nembra's existing `RideHistoryRecord` deliberately owns the original completed-ride
/// evidence. Duration is kept additive so an app persistence layer can adopt monotonic
/// elapsed-time truth without rewriting or inferring from wall-clock dates.
public struct RideHistoryDurationRecord: Codable, Equatable, Sendable {
    public let evidence: CompletedRideDurationEvidence

    public init(evidence: CompletedRideDurationEvidence) {
        self.evidence = evidence
    }

    public var sessionID: UUID { evidence.sessionID }
}

/// Storage contract for supplemental completed-ride duration truth.
///
/// Implementations must be immutable by session identity: replaying an equivalent record
/// returns `alreadyPresent`; the same session UUID with different evidence fails with
/// `RideHistoryDurationStoreError.sessionConflict` rather than overwriting history.
public protocol RideHistoryDurationStore: Sendable {
    func commit(_ record: RideHistoryDurationRecord) async throws -> RideHistoryDurationCommitResult
    func record(sessionID: UUID) async throws -> RideHistoryDurationRecord?
}

public enum RideHistoryDurationJoinError: Error, Equatable, Sendable {
    case completedRideMismatch(UUID)
}

/// A validated runtime join between base completed-ride history and its duration attachment.
///
/// The join is intentionally not `Codable`: durable storage remains two independently valid
/// records. Every consumer must re-establish their session/continuity relationship before
/// presenting or aggregating duration, preventing a matching UUID with mismatched continuity
/// from silently becoming ride truth.
public struct RideHistoryDurationJoinedRecord: Equatable, Sendable {
    public let historyRecord: RideHistoryRecord
    public let durationRecord: RideHistoryDurationRecord

    public init(
        historyRecord: RideHistoryRecord,
        durationRecord: RideHistoryDurationRecord
    ) throws {
        do {
            try durationRecord.evidence.validate(against: historyRecord.evidence)
        } catch {
            throw RideHistoryDurationJoinError.completedRideMismatch(historyRecord.sessionID)
        }

        self.historyRecord = historyRecord
        self.durationRecord = durationRecord
    }

    public var sessionID: UUID { historyRecord.sessionID }
}

public enum RideHistoryDurationCommitCoordinatorError: Error, Equatable, Sendable {
    case missingCompletedRide(UUID)
    case completedRideMismatch(UUID)
    case durableVerificationFailed(UUID)
}

/// Safely attaches accepted monotonic duration evidence to an already-durable ride.
///
/// The base ride must exist first. The duration evidence is validated against that exact
/// completed ride, committed idempotently, and read back for exact durable equivalence before
/// success is reported. No wall-clock subtraction, display timer, or inferred missing interval
/// participates in this path.
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

        let record = RideHistoryDurationRecord(evidence: evidence)
        let result = try await durationStore.commit(record)

        guard try await durationStore.record(sessionID: record.sessionID) == record else {
            throw RideHistoryDurationCommitCoordinatorError.durableVerificationFailed(record.sessionID)
        }

        return result
    }

    /// Returns duration only through a freshly validated history join.
    ///
    /// A missing base record or missing attachment is simply unavailable. Structurally present
    /// but mismatched evidence fails closed instead of being presented under the ride UUID.
    public func joinedRecord(
        sessionID: UUID
    ) async throws -> RideHistoryDurationJoinedRecord? {
        guard let historyRecord = try await historyStore.record(sessionID: sessionID),
              let durationRecord = try await durationStore.record(sessionID: sessionID) else {
            return nil
        }

        do {
            return try RideHistoryDurationJoinedRecord(
                historyRecord: historyRecord,
                durationRecord: durationRecord
            )
        } catch {
            throw RideHistoryDurationCommitCoordinatorError.completedRideMismatch(sessionID)
        }
    }
}
