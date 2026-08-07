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

        func commit(_ record: RideHistoryRecord) throws -> RideHistoryCommitResult {
            if let existing = records[record.sessionID] {
                guard existing == record else {
                    throw RideHistoryStoreError.sessionConflict(record.sessionID)
                }
                return .alreadyPresent
            }
            records[record.sessionID] = record
            return .inserted
        }

        func record(sessionID: UUID) -> RideHistoryRecord? {
            records[sessionID]
        }
    }

    private actor InMemoryDurationStore: RideHistoryDurationStore {
        private var records: [UUID: RideHistoryDurationRecord] = [:]
        private let suppressReads: Bool

        init(suppressReads: Bool = false) {
            self.suppressReads = suppressReads
        }

        func commit(
            _ record: RideHistoryDurationRecord
        ) throws -> RideHistoryDurationCommitResult {
            if let existing = records[record.sessionID] {
                guard existing == record else {
                    throw RideHistoryDurationStoreError.sessionConflict(record.sessionID)
                }
                return .alreadyPresent
            }
            records[record.sessionID] = record
            return .inserted
        }

        func record(sessionID: UUID) -> RideHistoryDurationRecord? {
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

        do {
            _ = try await coordinator.commit(durationEvidence)
            Issue.record("Expected missing completed ride to reject duration attachment")
        } catch let error as RideHistoryDurationCommitCoordinatorError {
            #expect(error == .missingCompletedRide(sessionID))
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
            historyStore: InMemoryRideHistoryStore(
                records: [RideHistoryRecord(evidence: baseRide)]
            ),
            durationStore: InMemoryDurationStore()
        )

        do {
            _ = try await coordinator.commit(recoveredDuration)
            Issue.record("Expected continuity-mismatched duration to fail")
        } catch let error as RideHistoryDurationCommitCoordinatorError {
            #expect(error == .completedRideMismatch(sessionID))
        }
    }

    @Test("duration store cannot silently replace immutable evidence")
    func conflictingReplacementRejected() async throws {
        let ride = try completedRide()
        let coordinator = RideHistoryDurationCommitCoordinator(
            historyStore: InMemoryRideHistoryStore(
                records: [RideHistoryRecord(evidence: ride)]
            ),
            durationStore: InMemoryDurationStore()
        )

        _ = try await coordinator.commit(
            duration(completedRide: ride, nanoseconds: 120_000_000_000)
        )

        do {
            _ = try await coordinator.commit(
                duration(completedRide: ride, nanoseconds: 121_000_000_000)
            )
            Issue.record("Expected conflicting immutable duration to fail")
        } catch let error as RideHistoryDurationStoreError {
            #expect(error == .sessionConflict(sessionID))
        }
    }

    @Test("commit requires exact durable read-back equivalence")
    func durableReadBackRequired() async throws {
        let ride = try completedRide()
        let coordinator = RideHistoryDurationCommitCoordinator(
            historyStore: InMemoryRideHistoryStore(
                records: [RideHistoryRecord(evidence: ride)]
            ),
            durationStore: InMemoryDurationStore(suppressReads: true)
        )

        do {
            _ = try await coordinator.commit(duration(completedRide: ride))
            Issue.record("Expected missing durable read-back to fail")
        } catch let error as RideHistoryDurationCommitCoordinatorError {
            #expect(error == .durableVerificationFailed(sessionID))
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

        let unavailableData = try JSONEncoder().encode(
            RideHistoryDurationRecord(evidence: unavailable)
        )
        let zeroData = try JSONEncoder().encode(
            RideHistoryDurationRecord(evidence: observedZero)
        )
        let decodedUnavailable = try JSONDecoder().decode(
            RideHistoryDurationRecord.self,
            from: unavailableData
        )
        let decodedZero = try JSONDecoder().decode(
            RideHistoryDurationRecord.self,
            from: zeroData
        )

        #expect(decodedUnavailable.evidence.observedDurationNanoseconds == nil)
        #expect(decodedUnavailable.evidence.coverage == .unknown)
        #expect(decodedZero.evidence.observedDurationNanoseconds == 0)
        #expect(decodedZero.evidence.coverage == .complete)
        #expect(decodedUnavailable != decodedZero)
    }
}
