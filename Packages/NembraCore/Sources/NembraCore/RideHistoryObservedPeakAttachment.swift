import Foundation

public enum RideHistoryObservedPeakCommitResult: Equatable, Sendable {
    case inserted
    case alreadyPresent
}

public enum RideHistoryObservedPeakStoreError: Error, Equatable, Sendable {
    case sessionConflict(UUID)
}

/// Supplemental immutable history record. Base completed-ride history remains
/// unchanged, so app persistence can adopt this attachment independently.
public struct RideHistoryObservedPeakRecord: Codable, Equatable, Sendable {
    public let evidence: RideObservedPeakHistoryEvidence

    public init(evidence: RideObservedPeakHistoryEvidence) {
        self.evidence = evidence
    }

    public var sessionID: UUID { evidence.sessionID }
}

public protocol RideHistoryObservedPeakStore: Sendable {
    func commit(_ record: RideHistoryObservedPeakRecord) async throws -> RideHistoryObservedPeakCommitResult
    func record(sessionID: UUID) async throws -> RideHistoryObservedPeakRecord?
}

public enum RideHistoryObservedPeakJoinError: Error, Equatable, Sendable {
    case completedRideMismatch(UUID)
}

/// Runtime-only trusted join. Construction revalidates the supplemental evidence
/// against the exact immutable completed ride rather than trusting UUID alone.
public struct RideHistoryObservedPeakJoinedRecord: Equatable, Sendable {
    public let historyRecord: RideHistoryRecord
    public let observedPeakRecord: RideHistoryObservedPeakRecord

#if SWIFT_PACKAGE
    package init(
        historyRecord: RideHistoryRecord,
        observedPeakRecord: RideHistoryObservedPeakRecord
    ) throws {
        try Self.validate(historyRecord: historyRecord, observedPeakRecord: observedPeakRecord)
        self.historyRecord = historyRecord
        self.observedPeakRecord = observedPeakRecord
    }
#else
    fileprivate init(
        historyRecord: RideHistoryRecord,
        observedPeakRecord: RideHistoryObservedPeakRecord
    ) throws {
        try Self.validate(historyRecord: historyRecord, observedPeakRecord: observedPeakRecord)
        self.historyRecord = historyRecord
        self.observedPeakRecord = observedPeakRecord
    }
#endif

    public var sessionID: UUID { historyRecord.sessionID }

    public func assessment() throws -> RideObservedPeakHistoryAssessment {
        try observedPeakRecord.evidence.assessment()
    }

    private static func validate(
        historyRecord: RideHistoryRecord,
        observedPeakRecord: RideHistoryObservedPeakRecord
    ) throws {
        do {
            try observedPeakRecord.evidence.validate(against: historyRecord.evidence)
        } catch {
            throw RideHistoryObservedPeakJoinError.completedRideMismatch(historyRecord.sessionID)
        }
    }
}

public enum RideHistoryObservedPeakCommitCoordinatorError: Error, Equatable, Sendable {
    case missingCompletedRide(UUID)
    case completedRideMismatch(UUID)
    case durableVerificationFailed(UUID)
}

/// Safely attaches observed-peak quality provenance after base history is durable.
/// Commit requires exact read-back. Missing attachment is ordinary unavailability;
/// an orphan attachment without its completed ride is durable inconsistency.
public actor RideHistoryObservedPeakCommitCoordinator {
    private let historyStore: any RideHistoryStore
    private let observedPeakStore: any RideHistoryObservedPeakStore

    public init(
        historyStore: any RideHistoryStore,
        observedPeakStore: any RideHistoryObservedPeakStore
    ) {
        self.historyStore = historyStore
        self.observedPeakStore = observedPeakStore
    }

    @discardableResult
    public func commit(
        _ evidence: RideObservedPeakHistoryEvidence
    ) async throws -> RideHistoryObservedPeakCommitResult {
        guard let historyRecord = try await historyStore.record(sessionID: evidence.sessionID) else {
            throw RideHistoryObservedPeakCommitCoordinatorError.missingCompletedRide(evidence.sessionID)
        }

        do {
            try evidence.validate(against: historyRecord.evidence)
        } catch {
            throw RideHistoryObservedPeakCommitCoordinatorError.completedRideMismatch(evidence.sessionID)
        }

        let record = RideHistoryObservedPeakRecord(evidence: evidence)
        let result = try await observedPeakStore.commit(record)
        guard try await observedPeakStore.record(sessionID: record.sessionID) == record else {
            throw RideHistoryObservedPeakCommitCoordinatorError.durableVerificationFailed(record.sessionID)
        }
        return result
    }

    public func joinedRecord(
        sessionID: UUID
    ) async throws -> RideHistoryObservedPeakJoinedRecord? {
        let historyRecord = try await historyStore.record(sessionID: sessionID)
        let observedPeakRecord = try await observedPeakStore.record(sessionID: sessionID)

        switch (historyRecord, observedPeakRecord) {
        case (nil, nil), (.some, nil):
            return nil
        case (nil, .some):
            throw RideHistoryObservedPeakCommitCoordinatorError.missingCompletedRide(sessionID)
        case let (.some(historyRecord), .some(observedPeakRecord)):
            do {
                return try RideHistoryObservedPeakJoinedRecord(
                    historyRecord: historyRecord,
                    observedPeakRecord: observedPeakRecord
                )
            } catch {
                throw RideHistoryObservedPeakCommitCoordinatorError.completedRideMismatch(sessionID)
            }
        }
    }
}
