import Foundation
import Testing
@testable import NembraCore

private enum RecordingRideHistoryError: Error, Equatable {
    case injectedFailure
}

private actor RecordingRideHistoryStore: RideHistoryStore {
    private var records: [UUID: RideHistoryRecord] = [:]
    private(set) var commitCalls = 0
    private(set) var insertions = 0
    private var failNextCommitFlag = false
    private var hideNextReadFlag = false

    init(initial: RideHistoryRecord? = nil) {
        if let initial {
            records[initial.sessionID] = initial
        }
    }

    func commit(_ record: RideHistoryRecord) async throws -> RideHistoryCommitResult {
        commitCalls += 1
        if failNextCommitFlag {
            failNextCommitFlag = false
            throw RecordingRideHistoryError.injectedFailure
        }
        if let existing = records[record.sessionID] {
            guard existing == record else {
                throw RideHistoryStoreError.sessionConflict(record.sessionID)
            }
            return .alreadyPresent
        }
        records[record.sessionID] = record
        insertions += 1
        return .inserted
    }

    func record(sessionID: UUID) async throws -> RideHistoryRecord? {
        if hideNextReadFlag {
            hideNextReadFlag = false
            return nil
        }
        return records[sessionID]
    }

    func failNextCommit() {
        failNextCommitFlag = true
    }

    func hideNextRead() {
        hideNextReadFlag = true
    }
}

private enum RecordingCompletionJournalError: Error, Equatable {
    case injectedFailure
}

private actor CompletionJournalStore: RideCheckpointStore {
    private(set) var value: RideDurableCheckpoint?
    private(set) var clearCalls = 0
    private var failNextClearFlag = false

    init(value: RideDurableCheckpoint?) {
        self.value = value
    }

    func save(_ checkpoint: RideDurableCheckpoint) async throws {
        value = checkpoint
    }

    func load() async throws -> RideDurableCheckpoint? {
        value
    }

    func clear() async throws {
        clearCalls += 1
        if failNextClearFlag {
            failNextClearFlag = false
            throw RecordingCompletionJournalError.injectedFailure
        }
        value = nil
    }

    func failNextClear() {
        failNextClearFlag = true
    }
}

@Suite("Completed ride history handoff")
struct RideHistoryCommitTests {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)
    private let sessionID = UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!

    private func policy() throws -> RideDetectionPolicy {
        try RideDetectionPolicy(
            candidateSpeedKilometersPerHour: 1,
            confirmationSpeedKilometersPerHour: 4,
            confirmationDurationNanoseconds: 0,
            confirmationOdometerDeltaKilometers: 0.05,
            confirmationGPSDistanceMeters: 8,
            endingDurationNanoseconds: 5_000,
            maximumSpeedSampleAgeNanoseconds: 1_000
        )
    }

    private func cadence() throws -> RideCheckpointCadence {
        try RideCheckpointCadence(minimumIntervalNanoseconds: 10_000)
    }

    private func evidence(
        id: UUID? = nil,
        endingODO: Double = 101,
        gpsMeters: Double = 900
    ) throws -> CompletedRideEvidence {
        try CompletedRideEvidence(
            sessionID: id ?? sessionID,
            beganAtDate: epoch,
            confirmedAtDate: epoch.addingTimeInterval(1),
            endedAtDate: epoch.addingTimeInterval(120),
            startingOdometerKilometers: 100,
            endingOdometerKilometers: endingODO,
            qualityScreenedGPSDistanceMeters: gpsMeters,
            continuity: .uninterruptedProcess
        )
    }

    private func recovery(
        journal: CompletionJournalStore,
        makeSessionID: @escaping @Sendable () -> UUID = { UUID() }
    ) async throws -> RideCheckpointCoordinator {
        try await RideCheckpointCoordinator.restoring(
            policy: try policy(),
            store: journal,
            cadence: try cadence(),
            recoveredAtUptimeNanoseconds: 50_000,
            recoveredAtDate: epoch.addingTimeInterval(130),
            makeSessionID: makeSessionID
        )
    }

    @Test("pending completion commits to history then clears recovery journal")
    func insertsThenAcknowledges() async throws {
        let completed = try evidence()
        let journal = CompletionJournalStore(value: .completedPendingCommit(completed))
        let recovery = try await recovery(journal: journal)
        let history = RecordingRideHistoryStore()
        let committer = RideHistoryCommitCoordinator(
            recoveryCoordinator: recovery,
            historyStore: history
        )

        #expect(try await committer.commitPendingRide() == .inserted)
        #expect(await history.insertions == 1)
        #expect(try await history.record(sessionID: sessionID) == RideHistoryRecord(evidence: completed))
        #expect(await recovery.pendingCompletedRideEvidence() == nil)
        #expect(await journal.value == nil)
    }

    @Test("equivalent pre-existing session is idempotent and may finish journal acknowledgement")
    func alreadyPresentEquivalentIsSafe() async throws {
        let completed = try evidence()
        let record = RideHistoryRecord(evidence: completed)
        let journal = CompletionJournalStore(value: .completedPendingCommit(completed))
        let recovery = try await recovery(journal: journal)
        let history = RecordingRideHistoryStore(initial: record)
        let committer = RideHistoryCommitCoordinator(recoveryCoordinator: recovery, historyStore: history)

        #expect(try await committer.commitPendingRide() == .alreadyPresent)
        #expect(await history.insertions == 0)
        #expect(await journal.value == nil)
    }

    @Test("same session with different durable evidence is never overwritten")
    func conflictingSessionBlocksAcknowledgement() async throws {
        let pending = try evidence(endingODO: 101)
        let conflicting = RideHistoryRecord(evidence: try evidence(endingODO: 102))
        let journal = CompletionJournalStore(value: .completedPendingCommit(pending))
        let recovery = try await recovery(journal: journal)
        let history = RecordingRideHistoryStore(initial: conflicting)
        let committer = RideHistoryCommitCoordinator(recoveryCoordinator: recovery, historyStore: history)

        await #expect(throws: RideHistoryStoreError.sessionConflict(sessionID)) {
            _ = try await committer.commitPendingRide()
        }
        #expect(await recovery.pendingCompletedRideEvidence() == pending)
        #expect(await journal.value == .completedPendingCommit(pending))
        #expect(try await history.record(sessionID: sessionID) == conflicting)
    }

    @Test("history write failure cannot clear recovery evidence")
    func writeFailurePreservesPending() async throws {
        let pending = try evidence()
        let journal = CompletionJournalStore(value: .completedPendingCommit(pending))
        let recovery = try await recovery(journal: journal)
        let history = RecordingRideHistoryStore()
        await history.failNextCommit()
        let committer = RideHistoryCommitCoordinator(recoveryCoordinator: recovery, historyStore: history)

        await #expect(throws: RecordingRideHistoryError.injectedFailure) {
            _ = try await committer.commitPendingRide()
        }
        #expect(await recovery.pendingCompletedRideEvidence() == pending)
        #expect(await journal.value == .completedPendingCommit(pending))
    }

    @Test("history must read back exact record before recovery journal is acknowledged")
    func readbackVerificationFailurePreservesPending() async throws {
        let pending = try evidence()
        let journal = CompletionJournalStore(value: .completedPendingCommit(pending))
        let recovery = try await recovery(journal: journal)
        let history = RecordingRideHistoryStore()
        await history.hideNextRead()
        let committer = RideHistoryCommitCoordinator(recoveryCoordinator: recovery, historyStore: history)

        await #expect(throws: RideHistoryCommitCoordinatorError.durableVerificationFailed(sessionID)) {
            _ = try await committer.commitPendingRide()
        }
        #expect(await history.insertions == 1)
        #expect(await recovery.pendingCompletedRideEvidence() == pending)
        #expect(await journal.value == .completedPendingCommit(pending))

        #expect(try await committer.commitPendingRide() == .alreadyPresent)
        #expect(await history.insertions == 1)
        #expect(await journal.value == nil)
    }

    @Test("clear failure after successful history commit retries idempotently without duplicate ride")
    func clearFailureRetriesWithoutDuplicate() async throws {
        let pending = try evidence()
        let journal = CompletionJournalStore(value: .completedPendingCommit(pending))
        await journal.failNextClear()
        let recovery = try await recovery(journal: journal)
        let history = RecordingRideHistoryStore()
        let committer = RideHistoryCommitCoordinator(recoveryCoordinator: recovery, historyStore: history)

        await #expect(throws: RecordingCompletionJournalError.injectedFailure) {
            _ = try await committer.commitPendingRide()
        }
        #expect(await history.insertions == 1)
        #expect(await recovery.pendingCompletedRideEvidence() == pending)
        #expect(await journal.value == .completedPendingCommit(pending))

        #expect(try await committer.commitPendingRide() == .alreadyPresent)
        #expect(await history.insertions == 1)
        #expect(await history.commitCalls == 2)
        #expect(await journal.value == nil)
    }

    @Test("committer refuses to run when no completed recovery handoff exists")
    func noPendingRideRejected() async throws {
        let journal = CompletionJournalStore(value: nil)
        let recovery = try await recovery(journal: journal)
        let history = RecordingRideHistoryStore()
        let committer = RideHistoryCommitCoordinator(recoveryCoordinator: recovery, historyStore: history)

        await #expect(throws: RideHistoryCommitCoordinatorError.noPendingCompletedRide) {
            _ = try await committer.commitPendingRide()
        }
        #expect(await history.commitCalls == 0)
    }
}
