import Foundation
import NembraCore
import Observation
import SwiftData

@Model
final class StoredDailyRideSegment {
    @Attribute(.unique) var storageID: String
    var sessionID: UUID
    var sequence: Int64
    var localDayStartDate: Date
    var payload: Data

    init(
        storageID: String,
        sessionID: UUID,
        sequence: Int64,
        localDayStartDate: Date,
        payload: Data
    ) {
        self.storageID = storageID
        self.sessionID = sessionID
        self.sequence = sequence
        self.localDayStartDate = localDayStartDate
        self.payload = payload
    }
}

/// The accumulator and its emitted segments share one SwiftData transaction.
/// A row exists only after the exact checkpoint receipt has been acknowledged.
@Model
final class StoredDailyRideAccumulatorState {
    @Attribute(.unique) var sessionID: UUID
    var payload: Data

    init(sessionID: UUID, payload: Data) {
        self.sessionID = sessionID
        self.payload = payload
    }
}

enum DailyRidePersistenceError: Error, Equatable, Sendable {
    case sequenceOutOfRange(NembraCore.AcceptedRideSegmentID)
    case corruptSegment(String)
    case segmentConflict(NembraCore.AcceptedRideSegmentID)
    case corruptAccumulator(UUID)
    case accumulatorConflict(UUID)
    case durableVerificationFailed(String)
    case injectedAtomicFailure
}

enum DailyRideSegmentCommitResult: Equatable, Sendable {
    case inserted
    case alreadyPresent
}

enum DailyRideCheckpointCommitResult: Equatable, Sendable {
    case inserted(segmentCount: Int)
    case alreadyPresent
}

/// Internal deterministic fault seam for atomic rollback tests. Production
/// callers always use the default `nil` value.
enum DailyRideAtomicCommitFault: Equatable, Sendable {
    case beforeSave
}

/// Exact, idempotent storage for accepted day-aligned ride segments.
///
/// The unique key is evidence identity, never date or display order. Equivalent
/// replay is a no-op; the same identity with changed payload fails closed so a
/// reconnect/relaunch cannot silently double-count or rewrite Today's total.
@ModelActor
actor SwiftDataDailyRideSegmentStore {
    /// Atomically acknowledges one accepted checkpoint and every immutable
    /// segment it emits. The proposal is recomputed from the durable predecessor
    /// before any mutation, so a stale/conflicting writer cannot advance state.
    /// A crash after save but before the caller swaps its in-memory accumulator
    /// is an idempotent replay: exact rows and state return `.alreadyPresent`.
    func commit(
        _ proposal: NembraCore.DailyRideSegmentCommitProposal,
        fault: DailyRideAtomicCommitFault? = nil
    ) async throws -> DailyRideCheckpointCommitResult {
        for segment in proposal.segmentsToPersist {
            guard segment.id.sequence <= UInt64(Int64.max) else {
                throw DailyRidePersistenceError.sequenceOutOfRange(segment.id)
            }
        }

        let sessionID = proposal.checkpoint.sessionID
        let existingRow = try storedAccumulator(sessionID: sessionID)
        let existingAccumulator = try existingRow.map {
            try decodeAccumulator($0, expectedSessionID: sessionID)
        }

        if existingAccumulator == proposal.accumulatorAfterPersistence {
            for segment in proposal.segmentsToPersist {
                guard let row = try storedSegment(storageID: Self.storageID(for: segment.id)),
                      try decode(row, expectedID: segment.id) == segment else {
                    throw DailyRidePersistenceError.durableVerificationFailed(
                        Self.storageID(for: segment.id)
                    )
                }
            }
            return .alreadyPresent
        }

        let predecessor = existingAccumulator
            ?? NembraCore.DailyRideSegmentAccumulator(sessionID: sessionID)
        let expectedProposal: NembraCore.DailyRideSegmentCommitProposal
        do {
            expectedProposal = try predecessor.prepare(proposal.checkpoint)
        } catch {
            throw DailyRidePersistenceError.accumulatorConflict(sessionID)
        }
        guard expectedProposal == proposal else {
            throw DailyRidePersistenceError.accumulatorConflict(sessionID)
        }

        do {
            for segment in proposal.segmentsToPersist {
                let storageID = Self.storageID(for: segment.id)
                if let row = try storedSegment(storageID: storageID) {
                    guard try decode(row, expectedID: segment.id) == segment else {
                        throw DailyRidePersistenceError.segmentConflict(segment.id)
                    }
                    continue
                }
                modelContext.insert(
                    StoredDailyRideSegment(
                        storageID: storageID,
                        sessionID: segment.id.sessionID,
                        sequence: Int64(segment.id.sequence),
                        localDayStartDate: segment.localDay.startDate,
                        payload: try JSONEncoder().encode(segment)
                    )
                )
            }

            let accumulatorPayload = try JSONEncoder().encode(
                proposal.accumulatorAfterPersistence
            )
            if let existingRow {
                existingRow.payload = accumulatorPayload
            } else {
                modelContext.insert(
                    StoredDailyRideAccumulatorState(
                        sessionID: sessionID,
                        payload: accumulatorPayload
                    )
                )
            }

            if fault == .beforeSave {
                throw DailyRidePersistenceError.injectedAtomicFailure
            }
            try modelContext.save()
        } catch {
            // This covers every post-insert/pre-save failure as well as the save
            // itself. No pending row may leak into a later transaction.
            modelContext.rollback()
            throw error
        }

        guard let verifiedRow = try storedAccumulator(sessionID: sessionID),
              try decodeAccumulator(verifiedRow, expectedSessionID: sessionID)
                == proposal.accumulatorAfterPersistence else {
            throw DailyRidePersistenceError.durableVerificationFailed(
                "accumulator|\(sessionID.uuidString)"
            )
        }
        for segment in proposal.segmentsToPersist {
            let storageID = Self.storageID(for: segment.id)
            guard let row = try storedSegment(storageID: storageID),
                  try decode(row, expectedID: segment.id) == segment else {
                throw DailyRidePersistenceError.durableVerificationFailed(storageID)
            }
        }
        return .inserted(segmentCount: proposal.segmentsToPersist.count)
    }

    func commit(
        _ segment: NembraCore.AcceptedRideSegment
    ) async throws -> DailyRideSegmentCommitResult {
        guard segment.id.sequence <= UInt64(Int64.max) else {
            throw DailyRidePersistenceError.sequenceOutOfRange(segment.id)
        }
        let storageID = Self.storageID(for: segment.id)
        if let existing = try storedSegment(storageID: storageID) {
            let decoded = try decode(existing, expectedID: segment.id)
            guard decoded == segment else {
                throw DailyRidePersistenceError.segmentConflict(segment.id)
            }
            return .alreadyPresent
        }

        let payload = try JSONEncoder().encode(segment)
        modelContext.insert(
            StoredDailyRideSegment(
                storageID: storageID,
                sessionID: segment.id.sessionID,
                sequence: Int64(segment.id.sequence),
                localDayStartDate: segment.localDay.startDate,
                payload: payload
            )
        )
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }

        guard let verified = try storedSegment(storageID: storageID),
              try decode(verified, expectedID: segment.id) == segment else {
            throw DailyRidePersistenceError.durableVerificationFailed(storageID)
        }
        return .inserted
    }

    func segments() throws -> [NembraCore.AcceptedRideSegment] {
        let rows = try modelContext.fetch(FetchDescriptor<StoredDailyRideSegment>())
        return try rows
            .map { row in
                guard row.sequence >= 0 else {
                    throw DailyRidePersistenceError.corruptSegment(row.storageID)
                }
                let id = NembraCore.AcceptedRideSegmentID(
                    sessionID: row.sessionID,
                    sequence: UInt64(row.sequence)
                )
                return try decode(row, expectedID: id)
            }
            .sorted(by: Self.segmentOrder)
    }

    func segments(localDay: NembraCore.RideLocalDay) throws -> [NembraCore.AcceptedRideSegment] {
        let start = localDay.startDate
        let rows = try modelContext.fetch(
            FetchDescriptor<StoredDailyRideSegment>(
                predicate: #Predicate { row in row.localDayStartDate == start }
            )
        )
        let decoded = try rows.compactMap { row -> NembraCore.AcceptedRideSegment? in
            guard row.sequence >= 0 else {
                throw DailyRidePersistenceError.corruptSegment(row.storageID)
            }
            let id = NembraCore.AcceptedRideSegmentID(
                sessionID: row.sessionID,
                sequence: UInt64(row.sequence)
            )
            let segment = try decode(row, expectedID: id)
            // UTC day starts are not a complete local-day identity. Different
            // frozen calendar/time-zone identities can legitimately share the
            // same instant, so the indexed date narrows the fetch while exact
            // `RideLocalDay` equality performs the authoritative selection.
            guard segment.localDay == localDay else { return nil }
            return segment
        }
        return decoded.sorted(by: Self.segmentOrder)
    }

    func accumulator(
        sessionID: UUID
    ) throws -> NembraCore.DailyRideSegmentAccumulator? {
        guard let row = try storedAccumulator(sessionID: sessionID) else { return nil }
        return try decodeAccumulator(row, expectedSessionID: sessionID)
    }

    func delete(sessionID: UUID) throws {
        let key = sessionID
        let rows = try modelContext.fetch(
            FetchDescriptor<StoredDailyRideSegment>(
                predicate: #Predicate { row in row.sessionID == key }
            )
        )
        for row in rows { modelContext.delete(row) }
        if let accumulatorRow = try storedAccumulator(sessionID: sessionID) {
            modelContext.delete(accumulatorRow)
        }
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private func storedSegment(storageID: String) throws -> StoredDailyRideSegment? {
        let key = storageID
        var descriptor = FetchDescriptor<StoredDailyRideSegment>(
            predicate: #Predicate { row in row.storageID == key }
        )
        descriptor.fetchLimit = 2
        let matches = try modelContext.fetch(descriptor)
        guard matches.count <= 1 else {
            throw DailyRidePersistenceError.corruptSegment(storageID)
        }
        return matches.first
    }

    private func storedAccumulator(
        sessionID: UUID
    ) throws -> StoredDailyRideAccumulatorState? {
        let key = sessionID
        var descriptor = FetchDescriptor<StoredDailyRideAccumulatorState>(
            predicate: #Predicate { row in row.sessionID == key }
        )
        descriptor.fetchLimit = 2
        let matches = try modelContext.fetch(descriptor)
        guard matches.count <= 1 else {
            throw DailyRidePersistenceError.corruptAccumulator(sessionID)
        }
        return matches.first
    }

    private func decode(
        _ row: StoredDailyRideSegment,
        expectedID: NembraCore.AcceptedRideSegmentID
    ) throws -> NembraCore.AcceptedRideSegment {
        do {
            let segment = try JSONDecoder().decode(
                NembraCore.AcceptedRideSegment.self,
                from: row.payload
            )
            guard row.storageID == Self.storageID(for: expectedID),
                  row.sessionID == expectedID.sessionID,
                  row.sequence == Int64(expectedID.sequence),
                  row.localDayStartDate == segment.localDay.startDate,
                  segment.id == expectedID else {
                throw DailyRidePersistenceError.corruptSegment(row.storageID)
            }
            return segment
        } catch let error as DailyRidePersistenceError {
            throw error
        } catch {
            throw DailyRidePersistenceError.corruptSegment(row.storageID)
        }
    }

    private func decodeAccumulator(
        _ row: StoredDailyRideAccumulatorState,
        expectedSessionID: UUID
    ) throws -> NembraCore.DailyRideSegmentAccumulator {
        do {
            let accumulator = try JSONDecoder().decode(
                NembraCore.DailyRideSegmentAccumulator.self,
                from: row.payload
            )
            guard row.sessionID == expectedSessionID,
                  accumulator.sessionID == expectedSessionID else {
                throw DailyRidePersistenceError.corruptAccumulator(expectedSessionID)
            }
            return accumulator
        } catch let error as DailyRidePersistenceError {
            throw error
        } catch {
            throw DailyRidePersistenceError.corruptAccumulator(expectedSessionID)
        }
    }

    private static func storageID(for id: NembraCore.AcceptedRideSegmentID) -> String {
        "\(id.sessionID.uuidString)|\(id.sequence)"
    }

    private static func segmentOrder(
        _ lhs: NembraCore.AcceptedRideSegment,
        _ rhs: NembraCore.AcceptedRideSegment
    ) -> Bool {
        if lhs.beganAtDate != rhs.beganAtDate { return lhs.beganAtDate < rhs.beganAtDate }
        if lhs.id.sessionID != rhs.id.sessionID {
            return lhs.id.sessionID.uuidString < rhs.id.sessionID.uuidString
        }
        return lhs.id.sequence < rhs.id.sequence
    }
}

enum DailyRidePresentationStatus: Equatable, Sendable {
    case idle
    case loading
    case ready
    case unavailable
    case failed
}

/// Read-only portrait/cockpit projection. UI never owns or increments Today.
@MainActor
@Observable
final class DailyRidePresentationStore {
    private(set) var status: DailyRidePresentationStatus
    private(set) var todayAndCurrent: NembraCore.TodayAndCurrentRideSummary?
    private(set) var recentDays: [NembraCore.DailyRideSummary] = []
    private(set) var lastErrorMessage: String?

    @ObservationIgnored private let store: SwiftDataDailyRideSegmentStore?
    @ObservationIgnored private let startupError: String?

    init(
        store: SwiftDataDailyRideSegmentStore?,
        startupError: String? = nil
    ) {
        self.store = store
        self.startupError = startupError
        status = store == nil ? .unavailable : .idle
        lastErrorMessage = startupError
    }

    func markPersistenceFailure() {
        status = .failed
        lastErrorMessage = "Accepted ride progress could not be saved safely. Automatic ride recording is paused."
    }

    func refresh(
        now: Date = .now,
        calendar: Calendar = .current,
        currentRideSessionID: UUID?
    ) async {
        guard let store else {
            status = .unavailable
            lastErrorMessage = startupError ?? "Daily ride storage is unavailable."
            todayAndCurrent = nil
            recentDays = []
            return
        }

        status = .loading
        do {
            let segments = try await store.segments()
            let today = try NembraCore.RideLocalDay(containing: now, calendar: calendar)
            todayAndCurrent = try NembraCore.DailyRideLedgerProjection.todayAndCurrentRide(
                segments: segments,
                today: today,
                currentRideSessionID: currentRideSessionID
            )

            let days = Set(segments.map(\.localDay)).sorted { $0.startDate > $1.startDate }
            recentDays = try days.prefix(90).map { day in
                try NembraCore.DailyRideLedgerProjection.todayAndCurrentRide(
                    segments: segments,
                    today: day,
                    currentRideSessionID: nil
                ).today
            }
            status = .ready
            lastErrorMessage = nil
        } catch {
            status = .failed
            todayAndCurrent = nil
            recentDays = []
            lastErrorMessage = "Accepted daily ride evidence could not be verified safely."
        }
    }
}
