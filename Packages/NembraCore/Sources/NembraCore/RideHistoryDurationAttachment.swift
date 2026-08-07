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
/// records. Construction is sealed so app code cannot manufacture a trusted join from arbitrary
/// matching records; production consumers receive one only after a core coordinator re-establishes
/// the session/continuity relationship from its stores.
public struct RideHistoryDurationJoinedRecord: Equatable, Sendable {
    public let historyRecord: RideHistoryRecord
    public let durationRecord: RideHistoryDurationRecord

#if SWIFT_PACKAGE
    /// Package tests and trusted NembraCore adapters may construct a joined fixture directly.
    /// Normal package clients cannot bypass the history coordinator because this remains
    /// package-scoped.
    package init(
        historyRecord: RideHistoryRecord,
        durationRecord: RideHistoryDurationRecord
    ) throws {
        try Self.validate(
            historyRecord: historyRecord,
            durationRecord: durationRecord
        )
        self.historyRecord = historyRecord
        self.durationRecord = durationRecord
    }
#else
    /// These core files are also compiled directly into Nembra.app rather than linked as a
    /// package product. Keep construction file-owned in that build so same-module app/UI code
    /// cannot mint a trusted join directly.
    fileprivate init(
        historyRecord: RideHistoryRecord,
        durationRecord: RideHistoryDurationRecord
    ) throws {
        try Self.validate(
            historyRecord: historyRecord,
            durationRecord: durationRecord
        )
        self.historyRecord = historyRecord
        self.durationRecord = durationRecord
    }
#endif

    public var sessionID: UUID { historyRecord.sessionID }

    private static func validate(
        historyRecord: RideHistoryRecord,
        durationRecord: RideHistoryDurationRecord
    ) throws {
        do {
            try durationRecord.evidence.validate(against: historyRecord.evidence)
        } catch {
            throw RideHistoryDurationJoinError.completedRideMismatch(historyRecord.sessionID)
        }
    }
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
    /// A missing attachment is simply unavailable when its base history exists (or when neither
    /// record exists). A duration attachment without its required base completed ride is a durable
    /// inconsistency and fails closed instead of being hidden as ordinary unavailability.
    public func joinedRecord(
        sessionID: UUID
    ) async throws -> RideHistoryDurationJoinedRecord? {
        let historyRecord = try await historyStore.record(sessionID: sessionID)
        let durationRecord = try await durationStore.record(sessionID: sessionID)

        switch (historyRecord, durationRecord) {
        case (nil, nil), (.some, nil):
            return nil
        case (nil, .some):
            throw RideHistoryDurationCommitCoordinatorError.missingCompletedRide(sessionID)
        case let (.some(historyRecord), .some(durationRecord)):
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
}
