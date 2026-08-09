import Foundation
import Testing

@testable import NembraCore

@Suite("Ride history duration archive attachment")
struct RideHistoryDurationAttachmentTests {
    private let sessionID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

    private actor HistoryStore: RideHistoryStore {
        private var records: [UUID: RideHistoryRecord]

        init(_ records: [RideHistoryRecord] = []) {
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

    private actor DurationStore: RideHistoryDurationStore {
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
            suppressReads ? nil : records[sessionID]
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

    private func authoritativeDuration(
        for ride: CompletedRideEvidence,
        nanoseconds: UInt64? = 120_000_000_000,
        coverage: RideSessionDurationCoverage = .complete,
        segments: Int = 1
    ) throws -> CompletedRideDurationEvidence {
        try CompletedRideDurationEvidence(
            completedRide: ride,
            duration: RideSessionDurationEvidenceSnapshot(
                sessionID: ride.sessionID,
                observedDurationNanoseconds: nanoseconds,
                coverage: coverage,
                observationSegmentCount: segments
            )
        )
    }

    @Test("authoritative duration commits one-way as archive and reads remain non-authoritative")
    func oneWayCommitAndAttachment() async throws {
        let ride = try completedRide()
        let history = RideHistoryRecord(evidence: ride)
        let evidence = try authoritativeDuration(for: ride)
        let coordinator = RideHistoryDurationCommitCoordinator(
            historyStore: HistoryStore([history]),
            durationStore: DurationStore()
        )

        #expect(try await coordinator.commit(evidence) == .inserted)
        #expect(try await coordinator.commit(evidence) == .alreadyPresent)

        let attachment = try await coordinator.attachment(sessionID: sessionID)
        #expect(attachment?.historyRecord == history)
        #expect(attachment?.durationRecord.archive == evidence.persistenceArchive)
        #expect(attachment?.durationRecord.archive.observedDurationNanoseconds == 120_000_000_000)
    }

    @Test("caller-authored archive is persistable data but cannot masquerade as authoritative evidence")
    func importedArchiveStaysArchive() async throws {
        let ride = try completedRide()
        let history = RideHistoryRecord(evidence: ride)
        let imported = try CompletedRideDurationEvidenceArchive(
            sessionID: sessionID,
            rideContinuity: ride.continuity,
            observedDurationNanoseconds: 999_000_000_000,
            coverage: .complete,
            observationSegmentCount: 1
        )
        let encoded = try JSONEncoder().encode(RideHistoryDurationRecord(archive: imported))
        let decoded = try JSONDecoder().decode(RideHistoryDurationRecord.self, from: encoded)
        let store = DurationStore()
        _ = try await store.commit(decoded)

        let coordinator = RideHistoryDurationCommitCoordinator(
            historyStore: HistoryStore([history]),
            durationStore: store
        )
        let attachment = try await coordinator.attachment(sessionID: sessionID)

        #expect(attachment?.durationRecord.archive == imported)
        #expect(attachment?.durationRecord.archive.observedDurationNanoseconds == 999_000_000_000)
        // There is deliberately no archive -> CompletedRideDurationEvidence API.
        // Persisted bytes remain structurally validated history only.
    }

    @Test("missing base history and orphaned archive fail closed")
    func missingBaseFailsClosed() async throws {
        let ride = try completedRide()
        let evidence = try authoritativeDuration(for: ride)
        let durationStore = DurationStore()
        let coordinator = RideHistoryDurationCommitCoordinator(
            historyStore: HistoryStore(),
            durationStore: durationStore
        )

        await #expect(throws: RideHistoryDurationCommitCoordinatorError.missingCompletedRide(sessionID)) {
            _ = try await coordinator.commit(evidence)
        }

        _ = try await durationStore.commit(
            RideHistoryDurationRecord(authoritativeEvidence: evidence)
        )
        await #expect(throws: RideHistoryDurationCommitCoordinatorError.missingCompletedRide(sessionID)) {
            _ = try await coordinator.attachment(sessionID: sessionID)
        }
    }

    @Test("base history without duration remains ordinary unavailability")
    func missingAttachmentIsUnavailable() async throws {
        let ride = try completedRide()
        let coordinator = RideHistoryDurationCommitCoordinator(
            historyStore: HistoryStore([RideHistoryRecord(evidence: ride)]),
            durationStore: DurationStore()
        )
        #expect(try await coordinator.attachment(sessionID: sessionID) == nil)
    }

    @Test("same session cannot replace immutable duration archive")
    func conflictingReplacementRejected() async throws {
        let ride = try completedRide()
        let coordinator = RideHistoryDurationCommitCoordinator(
            historyStore: HistoryStore([RideHistoryRecord(evidence: ride)]),
            durationStore: DurationStore()
        )
        _ = try await coordinator.commit(
            try authoritativeDuration(for: ride, nanoseconds: 120_000_000_000)
        )
        await #expect(throws: RideHistoryDurationStoreError.sessionConflict(sessionID)) {
            _ = try await coordinator.commit(
                try authoritativeDuration(for: ride, nanoseconds: 121_000_000_000)
            )
        }
    }

    @Test("continuity mismatch cannot join archive by UUID alone")
    func continuityMismatchRejected() async throws {
        let base = try completedRide(continuity: .uninterruptedProcess)
        let recoveredArchive = try CompletedRideDurationEvidenceArchive(
            sessionID: sessionID,
            rideContinuity: .recoveredCheckpoint,
            observedDurationNanoseconds: 30_000_000_000,
            coverage: .partial,
            observationSegmentCount: 2
        )
        let store = DurationStore()
        _ = try await store.commit(RideHistoryDurationRecord(archive: recoveredArchive))
        let coordinator = RideHistoryDurationCommitCoordinator(
            historyStore: HistoryStore([RideHistoryRecord(evidence: base)]),
            durationStore: store
        )

        await #expect(throws: RideHistoryDurationCommitCoordinatorError.completedRideMismatch(sessionID)) {
            _ = try await coordinator.attachment(sessionID: sessionID)
        }
    }

    @Test("commit success requires exact durable archive read-back")
    func durableReadBackRequired() async throws {
        let ride = try completedRide()
        let coordinator = RideHistoryDurationCommitCoordinator(
            historyStore: HistoryStore([RideHistoryRecord(evidence: ride)]),
            durationStore: DurationStore(suppressReads: true)
        )
        await #expect(throws: RideHistoryDurationCommitCoordinatorError.durableVerificationFailed(sessionID)) {
            _ = try await coordinator.commit(try authoritativeDuration(for: ride))
        }
    }

    @Test("unavailable archive remains distinct from legitimately observed zero")
    func unavailableAndZeroRemainDistinct() throws {
        let ride = try completedRide()
        let unavailable = RideHistoryDurationRecord(
            authoritativeEvidence: try authoritativeDuration(
                for: ride,
                nanoseconds: nil,
                coverage: .unknown,
                segments: 0
            )
        )
        let zero = RideHistoryDurationRecord(
            authoritativeEvidence: try authoritativeDuration(
                for: ride,
                nanoseconds: 0,
                coverage: .complete,
                segments: 1
            )
        )
        #expect(unavailable != zero)
        #expect(unavailable.archive.observedDurationNanoseconds == nil)
        #expect(zero.archive.observedDurationNanoseconds == 0)
    }
}
