import Foundation

public enum RideHistoryCommitResult: Equatable, Sendable {
    case inserted
    case alreadyPresent
}

public enum RideHistoryStoreError: Error, Equatable, Sendable {
    case sessionConflict(UUID)
    case corruptedRecord(UUID)
}

/// The durable completed-ride payload owned by local ride history.
///
/// This first record intentionally preserves the raw validated completion
/// evidence rather than baking in a final reconciled distance. ODO/GPS/live
/// evidence and reconciliation can evolve without changing ride identity.
public struct RideHistoryRecord: Codable, Equatable, Sendable {
    public let evidence: CompletedRideEvidence

    public init(evidence: CompletedRideEvidence) {
        self.evidence = evidence
    }

    public var sessionID: UUID { evidence.sessionID }
}

/// Local completed-ride storage contract. Implementations must make commit
/// idempotent by session UUID: committing an equivalent record again returns
/// `alreadyPresent`; the same UUID with different durable evidence must fail
/// with `RideHistoryStoreError.sessionConflict` rather than overwrite history.
/// Corrupt on-disk evidence must be surfaced as `corruptedRecord` and preserved
/// for diagnostics instead of being silently replaced.
public protocol RideHistoryStore: Sendable {
    func commit(_ record: RideHistoryRecord) async throws -> RideHistoryCommitResult
    func record(sessionID: UUID) async throws -> RideHistoryRecord?
}

public enum RideHistoryCommitCoordinatorError: Error, Equatable, Sendable {
    case noPendingCompletedRide
    case durableVerificationFailed(UUID)
}

/// Bridges the crash-recovery journal into permanent completed-ride history.
///
/// The history store is committed first, then immediately read back and checked
/// for exact durable equivalence. Only after that verification may the recovery
/// coordinator clear `completedPendingCommit`. If clearing fails, retrying this
/// operation relies on history-store idempotency and cannot create a duplicate.
public actor RideHistoryCommitCoordinator {
    private let recoveryCoordinator: RideCheckpointCoordinator
    private let historyStore: any RideHistoryStore

    public init(
        recoveryCoordinator: RideCheckpointCoordinator,
        historyStore: any RideHistoryStore
    ) {
        self.recoveryCoordinator = recoveryCoordinator
        self.historyStore = historyStore
    }

    @discardableResult
    public func commitPendingRide() async throws -> RideHistoryCommitResult {
        guard let evidence = await recoveryCoordinator.pendingCompletedRideEvidence() else {
            throw RideHistoryCommitCoordinatorError.noPendingCompletedRide
        }

        let record = RideHistoryRecord(evidence: evidence)
        let result = try await historyStore.commit(record)

        guard try await historyStore.record(sessionID: record.sessionID) == record else {
            throw RideHistoryCommitCoordinatorError.durableVerificationFailed(record.sessionID)
        }

        try await recoveryCoordinator.acknowledgeCompletedRideCommitted(
            sessionID: record.sessionID
        )
        return result
    }
}
