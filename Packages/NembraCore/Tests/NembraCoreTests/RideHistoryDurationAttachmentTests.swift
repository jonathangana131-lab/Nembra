import Foundation
import Testing

@testable import NembraCore

@Suite("Ride history duration attachment")
struct RideHistoryDurationAttachmentTests {
    private let sessionID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

    private actor InMemoryRideHistoryStore: RideHistoryStore {
        private var records: [UUID: RideHistoryRecord]

        init(records: [RideHistoryRecord] = []) {
            self.records = Dictionary(uniqueKeysWithValues: records.map { ($0.sessionID, $0) })
        }

        func commit(_ record: RideHistoryRecord) async throws -> RideHistoryCommitResult {
            if let existing = records[record.sessionID] {
                guard existing == record else {
                    throw RideHistoryStoreError.sessionConflict(record.sessionID)
                }
                return .alreadyPresent
            }
            records[record.sessionID] = record
            return .inserted
        }

        func record(sessionID: UUID) async throws -> RideHistoryRecord? {
            records[sessionID]
        }
    }

    private actor InMemoryDurationStore: RideHistoryDurationStore {
        private var records: [UUID: RideHistoryDurationRecord] = [:]
        private let suppressReads: Bool

        init(suppressReads: Bool = false) {
            self.suppressReads = suppressReads
        }

        func commit(_ record: RideHistoryDurationRecord) async throws -> RideHistoryDurationCommitResult {
            if let existing = records[record.sessionID] {
                guard existing == record else {
                    throw RideHistoryDurationStoreError.sessionConflict(record.sessionID)
                }
                return .alreadyPresent
            }
            records[record.sessionID] = record
            return .inserted
        }

        func record(sessionID: UUID) async throws -> RideHistoryDurationRecord? {
            guard !suppressReads else { return nil }
            return records[sessionID]
        }
    }

    private func completedRide(
        continuity: RideSessionContinuity = .uninterruptedProcess
    ) throws -> CompletedRideEvidence {
        try CompletedRideEvidence(
            sessionID: sessionID,
            beganAtDate: Date(timeIntervalSinceReferenceDate: 1_000),
            confirmedAtDate: Date(timeIntervalSinceReferenceDate: 1_010),
            endedAtDate: Date(timeIntervalSinceReferenceDate: 1_200),
            startingOdometerKilometers: 10,
            endingOdometerKilometers: 11,
            qualityScreenedGPSDistanceMeters: 1_500,
            continuity: continuity
        )
    }

    private func duration(
        completedRide: CompletedRideEvidence,
        nanoseconds: UInt64? = 120_000_000_000,
        coverage: RideSessionDurationCoverage = .complete,
        observationSegmentCount: Int = 1
    ) throws -> CompletedRideDurationEvidence {
        let snapshot = RideSessionDurationEvidenceSnapshot(
            sessionID: completedRide.sessionID,
            observedDurationNanoseconds: nanoseconds,
            coverage: coverage,
            observationSegmentCount: observationSegmentCount
        )
        return try CompletedRideDurationEvidence(
            completedRide: completedRide,
            duration: snapshot
        )
    }

    @Test("duration attaches idempotently only after base history exists")
    func commitAndJoin() async throws {
        let ride = try completedRide()
        let history = RideHistoryRecord(evidence: ride)
        let durationEvidence = try duration(completedRide: ride)
        let durationStore = InMemoryDurationStore()
        let coordinator = RideHistoryDurationCommitCoordinator(
            historyStore: InMemoryRideHistoryStore(records: [history]),
            durationStore: durationStore
        )

        #expect(try await coordinator.commit(durationEvidence) == .inserted)
        #expect(try await coordinator.commit(durationEvidence) == .alreadyPresent)

        let joined = try await coordinator.joinedRecord(sessionID: sessionID)
        #expect(joined?.historyRecord == history)
        #expect(joined?.durationRecord.evidence == durationEvidence)
        #expect(joined?.sessionID == sessionID)
    }

    @Test("missing base history fails closed")
    func missingBaseRideRejected() async throws {
        let ride = try completedRide()
        let durationEvidence = try duration(completedRide: ride)
        let coordinator = RideHistoryDurationCommitCoordinator(
            historyStore: InMemoryRideHistoryStore(),
            durationStore: InMemoryDurationStore()
        )

        await #expect(throws: RideHistoryDurationCommitCoordinatorError.missingCompletedRide(sessionID)) {
            _ = try await coordinator.commit(durationEvidence)
        }
    }

    @Test("base history without a duration attachment is ordinary unavailability")
    func missingDurationAttachmentIsUnavailable() async throws {
        let ride = try completedRide()
        let coordinator = RideHistoryDurationCommitCoordinator(
            historyStore: InMemoryRideHistoryStore(records: [RideHistoryRecord(evidence: ride)]),
            durationStore: InMemoryDurationStore()
        )

        #expect(try await coordinator.joinedRecord(sessionID: sessionID) == nil)
    }

    @Test("orphaned duration attachment without base history fails closed")
    func orphanedDurationAttachmentRejected() async throws {
        let ride = try completedRide()
        let durationStore = InMemoryDurationStore()
        _ = try await durationStore.commit(RideHistoryDurationRecord(evidence: duration(completedRide: ride)))
        let coordinator = RideHistoryDurationCommitCoordinator(
            historyStore: InMemoryRideHistoryStore(),
            durationStore: durationStore
        )

        await #expect(throws: RideHistoryDurationCommitCoordinatorError.missingCompletedRide(sessionID)) {
            _ = try await coordinator.joinedRecord(sessionID: sessionID)
        }
    }

    @Test("same session with different ride continuity cannot join")
    func continuityMismatchRejected() async throws {
        let baseRide = try completedRide(continuity: .uninterruptedProcess)
        let recoveredRide = try completedRide(continuity: .recoveredCheckpoint)
        let recoveredDuration = try duration(
            completedRide: recoveredRide,
            nanoseconds: 30_000_000_000,
            coverage: .partial,
            observationSegmentCount: 1
        )
        let coordinator = RideHistoryDurationCommitCoordinator(
            historyStore: InMemoryRideHistoryStore(records: [RideHistoryRecord(evidence: baseRide)]),
            durationStore: InMemoryDurationStore()
        )

        await #expect(throws: RideHistoryDurationCommitCoordinatorError.completedRideMismatch(sessionID)) {
            _ = try await coordinator.commit(recoveredDuration)
        }
    }

    @Test("duration store cannot silently replace immutable evidence")
    func conflictingReplacementRejected() async throws {
        let ride = try completedRide()
        let coordinator = RideHistoryDurationCommitCoordinator(
            historyStore: InMemoryRideHistoryStore(records: [RideHistoryRecord(evidence: ride)]),
            durationStore: InMemoryDurationStore()
        )

        _ = try await coordinator.commit(duration(completedRide: ride, nanoseconds: 120_000_000_000))

        await #expect(throws: RideHistoryDurationStoreError.sessionConflict(sessionID)) {
            _ = try await coordinator.commit(duration(completedRide: ride, nanoseconds: 121_000_000_000))
        }
    }

    @Test("commit requires exact durable read-back equivalence")
    func durableReadBackRequired() async throws {
        let ride = try completedRide()
        let coordinator = RideHistoryDurationCommitCoordinator(
            historyStore: InMemoryRideHistoryStore(records: [RideHistoryRecord(evidence: ride)]),
            durationStore: InMemoryDurationStore(suppressReads: true)
        )

        await #expect(throws: RideHistoryDurationCommitCoordinatorError.durableVerificationFailed(sessionID)) {
            _ = try await coordinator.commit(duration(completedRide: ride))
        }
    }

    @Test("joined record independently revalidates history identity")
    func joinedRecordValidatesContinuity() throws {
        let baseRide = try completedRide(continuity: .uninterruptedProcess)
        let recoveredRide = try completedRide(continuity: .recoveredCheckpoint)
        let recoveredDuration = try duration(
            completedRide: recoveredRide,
            nanoseconds: 1,
            coverage: .partial,
            observationSegmentCount: 1
        )

        #expect(throws: RideHistoryDurationJoinError.completedRideMismatch(sessionID)) {
            try RideHistoryDurationJoinedRecord(
                historyRecord: RideHistoryRecord(evidence: baseRide),
                durationRecord: RideHistoryDurationRecord(evidence: recoveredDuration)
            )
        }
    }

    @Test("unavailable and observed zero remain distinct durable attachments")
    func unavailableAndObservedZeroStayDistinct() throws {
        let ride = try completedRide()
        let unavailable = try duration(
            completedRide: ride,
            nanoseconds: nil,
            coverage: .unknown,
            observationSegmentCount: 0
        )
        let observedZero = try duration(
            completedRide: ride,
            nanoseconds: 0,
            coverage: .complete,
            observationSegmentCount: 1
        )

        let unavailableData = try JSONEncoder().encode(RideHistoryDurationRecord(evidence: unavailable))
        let zeroData = try JSONEncoder().encode(RideHistoryDurationRecord(evidence: observedZero))
        let decodedUnavailable = try JSONDecoder().decode(RideHistoryDurationRecord.self, from: unavailableData)
        let decodedZero = try JSONDecoder().decode(RideHistoryDurationRecord.self, from: zeroData)

        #expect(decodedUnavailable.evidence.observedDurationNanoseconds == nil)
        #expect(decodedUnavailable.evidence.coverage == .unknown)
        #expect(decodedZero.evidence.observedDurationNanoseconds == 0)
        #expect(decodedZero.evidence.coverage == .complete)
        #expect(decodedUnavailable != decodedZero)
    }
}
