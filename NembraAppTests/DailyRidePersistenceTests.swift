import Foundation
import NembraCore
import SwiftData
import XCTest
@testable import Nembra

final class DailyRidePersistenceTests: XCTestCase {
    private let sessionA = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
    private let sessionB = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!

    func testInMemoryStoreCommitsExactSegmentIdempotently() async throws {
        let container = try makeInMemoryContainer()
        let store = SwiftDataDailyRideSegmentStore(modelContainer: container)
        let segment = try acceptedSegment(sessionID: sessionA, sequence: 0, distanceMeters: 1_250)

        let inserted = try await store.commit(segment)
        let replayed = try await store.commit(segment)
        let stored = try await store.segments()
        XCTAssertEqual(inserted, .inserted)
        XCTAssertEqual(replayed, .alreadyPresent)
        XCTAssertEqual(stored, [segment])
    }

    func testAtomicCheckpointFailureRollsBackStateAndSegmentsThenRetriesExactly() async throws {
        let container = try makeInMemoryContainer()
        let store = SwiftDataDailyRideSegmentStore(modelContainer: container)
        var accumulator = DailyRideSegmentAccumulator(sessionID: sessionA)
        let anchor = try checkpoint(
            sessionID: sessionA,
            sequence: 0,
            uptime: 100,
            at: date("2026-08-18T18:00:00Z"),
            distanceMeters: 0,
            durationSeconds: 0
        )
        let anchorProposal = try accumulator.prepare(anchor)
        let anchorResult = try await store.commit(anchorProposal)
        XCTAssertEqual(anchorResult, .inserted(segmentCount: 0))
        accumulator = anchorProposal.accumulatorAfterPersistence

        let next = try checkpoint(
            sessionID: sessionA,
            sequence: 1,
            uptime: 200,
            at: date("2026-08-18T18:01:00Z"),
            distanceMeters: 250,
            durationSeconds: 60
        )
        let proposal = try accumulator.prepare(next)
        do {
            _ = try await store.commit(proposal, fault: .beforeSave)
            XCTFail("A failed atomic save must not acknowledge state or leave a segment row.")
        } catch let error as DailyRidePersistenceError {
            XCTAssertEqual(error, .injectedAtomicFailure)
        }

        let stateAfterFailure = try await store.accumulator(sessionID: sessionA)
        let segmentsAfterFailure = try await store.segments()
        XCTAssertEqual(stateAfterFailure, accumulator)
        XCTAssertTrue(segmentsAfterFailure.isEmpty)
        let retryResult = try await store.commit(proposal)
        let segmentsAfterRetry = try await store.segments()
        let stateAfterRetry = try await store.accumulator(sessionID: sessionA)
        let replayResult = try await store.commit(proposal)
        XCTAssertEqual(retryResult, .inserted(segmentCount: 1))
        XCTAssertEqual(segmentsAfterRetry, proposal.segmentsToPersist)
        XCTAssertEqual(stateAfterRetry, proposal.accumulatorAfterPersistence)
        XCTAssertEqual(replayResult, .alreadyPresent)
    }

    func testAtomicConflictAfterFirstInsertRollsBackPendingSegment() async throws {
        let container = try makeInMemoryContainer()
        let store = SwiftDataDailyRideSegmentStore(modelContainer: container)
        var accumulator = DailyRideSegmentAccumulator(sessionID: sessionA)
        let anchor = try checkpoint(
            sessionID: sessionA,
            sequence: 0,
            uptime: 100,
            at: date("2026-08-18T18:00:00Z"),
            distanceMeters: 0,
            durationSeconds: 0
        )
        let anchorProposal = try accumulator.prepare(anchor)
        _ = try await store.commit(anchorProposal)
        accumulator = anchorProposal.accumulatorAfterPersistence

        var changedCalendar = Calendar(identifier: .gregorian)
        changedCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let boundary = try checkpoint(
            sessionID: sessionA,
            sequence: 1,
            uptime: 200,
            at: date("2026-08-18T18:01:00Z"),
            distanceMeters: 250,
            durationSeconds: 60,
            calendar: changedCalendar
        )
        let proposal = try accumulator.prepare(boundary)
        XCTAssertEqual(proposal.segmentsToPersist.count, 2)

        let secondID = proposal.segmentsToPersist[1].id
        let conflict = try acceptedSegment(
            sessionID: secondID.sessionID,
            sequence: secondID.sequence,
            distanceMeters: 999
        )
        _ = try await store.commit(conflict)

        do {
            _ = try await store.commit(proposal)
            XCTFail("A later segment conflict must roll back earlier inserts in the transaction.")
        } catch let error as DailyRidePersistenceError {
            XCTAssertEqual(error, .segmentConflict(secondID))
        }

        let storedSegments = try await store.segments()
        let storedAccumulator = try await store.accumulator(sessionID: sessionA)
        XCTAssertEqual(storedSegments, [conflict])
        XCTAssertEqual(storedAccumulator, accumulator)
    }

    func testAccumulatorAndSegmentsReloadTogetherWithoutDoubleCountingReplay() async throws {
        let directory = temporaryDirectory(name: "daily-accumulator-reload")
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("DailyRideSegments.store")
        let anchor = try checkpoint(
            sessionID: sessionA,
            sequence: 0,
            uptime: 100,
            at: date("2026-08-18T18:00:00Z"),
            distanceMeters: 0,
            durationSeconds: 0
        )
        let next = try checkpoint(
            sessionID: sessionA,
            sequence: 1,
            uptime: 200,
            at: date("2026-08-18T18:01:00Z"),
            distanceMeters: 400,
            durationSeconds: 60
        )

        var committedAccumulator: DailyRideSegmentAccumulator!
        var committedSegments: [AcceptedRideSegment] = []
        do {
            let container = try RidePersistenceFactory.makeDailyRideContainer(storeURL: storeURL)
            let store = SwiftDataDailyRideSegmentStore(modelContainer: container)
            var accumulator = DailyRideSegmentAccumulator(sessionID: sessionA)
            let anchorProposal = try accumulator.prepare(anchor)
            _ = try await store.commit(anchorProposal)
            accumulator = anchorProposal.accumulatorAfterPersistence
            let nextProposal = try accumulator.prepare(next)
            _ = try await store.commit(nextProposal)
            committedAccumulator = nextProposal.accumulatorAfterPersistence
            committedSegments = nextProposal.segmentsToPersist
        }

        do {
            let container = try RidePersistenceFactory.makeDailyRideContainer(storeURL: storeURL)
            let store = SwiftDataDailyRideSegmentStore(modelContainer: container)
            let restoredValue = try await store.accumulator(sessionID: sessionA)
            let restored = try XCTUnwrap(restoredValue)
            let restoredSegments = try await store.segments()
            XCTAssertEqual(restored, committedAccumulator)
            XCTAssertEqual(restoredSegments, committedSegments)

            let replay = try restored.prepare(next)
            XCTAssertEqual(replay.disposition, .idempotentReplay)
            let replayResult = try await store.commit(replay)
            let segmentsAfterReplay = try await store.segments()
            XCTAssertEqual(replayResult, .alreadyPresent)
            XCTAssertEqual(segmentsAfterReplay, committedSegments)
        }
    }

    @MainActor
    func testTodayIncludesAllSessionsWhileCurrentRideRemainsSessionScoped() async throws {
        let container = try makeInMemoryContainer()
        let store = SwiftDataDailyRideSegmentStore(modelContainer: container)
        try await commitCheckpointPair(
            sessionID: sessionA,
            distanceMeters: 500,
            store: store,
            startOffset: 0
        )
        try await commitCheckpointPair(
            sessionID: sessionB,
            distanceMeters: 200,
            store: store,
            startOffset: 600
        )

        let presentation = DailyRidePresentationStore(store: store)
        await presentation.refresh(
            now: date("2026-08-18T20:00:00Z"),
            calendar: localCalendar(),
            currentRideSessionID: sessionB
        )
        XCTAssertEqual(presentation.todayAndCurrent?.today.distanceMeters.value, 700)
        XCTAssertEqual(presentation.todayAndCurrent?.today.rideCount, 2)
        XCTAssertEqual(presentation.todayAndCurrent?.currentRide?.sessionID, sessionB)
        XCTAssertEqual(presentation.todayAndCurrent?.currentRide?.distanceMeters.value, 200)
    }

    func testInMemoryStoreRejectsConflictingReplayWithoutRewritingEvidence() async throws {
        let container = try makeInMemoryContainer()
        let store = SwiftDataDailyRideSegmentStore(modelContainer: container)
        let accepted = try acceptedSegment(sessionID: sessionA, sequence: 7, distanceMeters: 900)
        let conflict = try acceptedSegment(sessionID: sessionA, sequence: 7, distanceMeters: 901)

        let inserted = try await store.commit(accepted)
        XCTAssertEqual(inserted, .inserted)
        do {
            _ = try await store.commit(conflict)
            XCTFail("The same evidence identity must not be overwritten with changed mileage.")
        } catch let error as DailyRidePersistenceError {
            XCTAssertEqual(error, .segmentConflict(accepted.id))
        }
        let stored = try await store.segments()
        XCTAssertEqual(stored, [accepted])
    }

    func testDiskStoreReloadsExactAcceptedSegment() async throws {
        let directory = temporaryDirectory(name: "daily-reload")
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("DailyRideSegments.store")
        let segment = try acceptedSegment(sessionID: sessionA, sequence: 2, distanceMeters: 2_400)

        do {
            let container = try RidePersistenceFactory.makeDailyRideContainer(storeURL: storeURL)
            let store = SwiftDataDailyRideSegmentStore(modelContainer: container)
            let inserted = try await store.commit(segment)
            XCTAssertEqual(inserted, .inserted)
        }

        do {
            let container = try RidePersistenceFactory.makeDailyRideContainer(storeURL: storeURL)
            let store = SwiftDataDailyRideSegmentStore(modelContainer: container)
            let stored = try await store.segments()
            let replayed = try await store.commit(segment)
            XCTAssertEqual(stored, [segment])
            XCTAssertEqual(replayed, .alreadyPresent)
        }
    }

    func testDeletingRideSessionRemovesEveryDaySegmentAndPreservesOtherSessions() async throws {
        let container = try makeInMemoryContainer()
        let store = SwiftDataDailyRideSegmentStore(modelContainer: container)
        let first = try acceptedSegment(sessionID: sessionA, sequence: 0, distanceMeters: 400)
        let second = try acceptedSegment(
            sessionID: sessionA,
            sequence: 1,
            distanceMeters: 600,
            beganAtDate: date("2026-08-18T18:20:00Z"),
            endedAtDate: date("2026-08-18T18:30:00Z")
        )
        let retained = try acceptedSegment(
            sessionID: sessionB,
            sequence: 0,
            distanceMeters: 800,
            beganAtDate: date("2026-08-18T19:00:00Z"),
            endedAtDate: date("2026-08-18T19:10:00Z")
        )

        _ = try await store.commit(first)
        _ = try await store.commit(second)
        _ = try await store.commit(retained)
        try await store.delete(sessionID: sessionA)

        let stored = try await store.segments()
        XCTAssertEqual(stored, [retained])
    }

    func testLocalDayQueryKeepsFrozenCalendarIdentityWhenUTCStartMatches() async throws {
        let container = try makeInMemoryContainer()
        let store = SwiftDataDailyRideSegmentStore(modelContainer: container)
        let instant = date("2026-08-18T18:00:00Z")

        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = TimeZone(secondsFromGMT: 0)!
        var iso8601 = Calendar(identifier: .iso8601)
        iso8601.timeZone = TimeZone(secondsFromGMT: 0)!

        let gregorianDay = try RideLocalDay(containing: instant, calendar: gregorian)
        let isoDay = try RideLocalDay(containing: instant, calendar: iso8601)
        XCTAssertEqual(gregorianDay.startDate, isoDay.startDate)
        XCTAssertNotEqual(gregorianDay, isoDay)

        let gregorianSegment = try acceptedSegment(
            sessionID: sessionA,
            sequence: 0,
            distanceMeters: 700,
            beganAtDate: instant,
            endedAtDate: instant.addingTimeInterval(60),
            calendar: gregorian
        )
        let isoSegment = try acceptedSegment(
            sessionID: sessionB,
            sequence: 0,
            distanceMeters: 900,
            beganAtDate: instant,
            endedAtDate: instant.addingTimeInterval(60),
            calendar: iso8601
        )
        _ = try await store.commit(gregorianSegment)
        _ = try await store.commit(isoSegment)

        let storedGregorian = try await store.segments(localDay: gregorianDay)
        let storedISO = try await store.segments(localDay: isoDay)
        XCTAssertEqual(storedGregorian, [gregorianSegment])
        XCTAssertEqual(storedISO, [isoSegment])
    }

    @MainActor
    func testTodayProjectionSurvivesPersistentStoreReopen() async throws {
        let directory = temporaryDirectory(name: "today-reopen")
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("DailyRideSegments.store")
        let segment = try acceptedSegment(sessionID: sessionA, sequence: 0, distanceMeters: 3_200)

        do {
            let container = try RidePersistenceFactory.makeDailyRideContainer(storeURL: storeURL)
            let store = SwiftDataDailyRideSegmentStore(modelContainer: container)
            _ = try await store.commit(segment)
        }

        let reopenedContainer = try RidePersistenceFactory.makeDailyRideContainer(storeURL: storeURL)
        let reopenedStore = SwiftDataDailyRideSegmentStore(modelContainer: reopenedContainer)
        let presentation = DailyRidePresentationStore(store: reopenedStore)
        await presentation.refresh(
            now: date("2026-08-18T20:00:00Z"),
            calendar: localCalendar(),
            currentRideSessionID: nil
        )

        XCTAssertEqual(presentation.status, .ready)
        XCTAssertEqual(presentation.todayAndCurrent?.today.rideCount, 1)
        XCTAssertEqual(presentation.todayAndCurrent?.today.distanceMeters.value, 3_200)
        XCTAssertEqual(presentation.todayAndCurrent?.today.distanceMeters.availability, .complete)
        XCTAssertNil(presentation.todayAndCurrent?.currentRide)
    }

    @MainActor
    func testPresentationKeepsKnownPartialDistanceAndMarksUnavailableDuration() async throws {
        let container = try makeInMemoryContainer()
        let store = SwiftDataDailyRideSegmentStore(modelContainer: container)
        let partial = try acceptedSegment(
            sessionID: sessionA,
            sequence: 0,
            distance: try DailyRideMetricEvidence(value: 725, disposition: .knownPartial),
            duration: try DailyRideMetricEvidence(value: nil, disposition: .unavailable)
        )
        let unavailable = try acceptedSegment(
            sessionID: sessionB,
            sequence: 0,
            distance: try DailyRideMetricEvidence(value: nil, disposition: .unavailable),
            duration: try DailyRideMetricEvidence(value: nil, disposition: .unavailable),
            beganAtDate: date("2026-08-18T19:00:00Z"),
            endedAtDate: date("2026-08-18T19:10:00Z")
        )
        _ = try await store.commit(partial)
        _ = try await store.commit(unavailable)

        let presentation = DailyRidePresentationStore(store: store)
        await presentation.refresh(
            now: date("2026-08-18T20:00:00Z"),
            calendar: localCalendar(),
            currentRideSessionID: sessionA
        )

        XCTAssertEqual(presentation.status, .ready)
        XCTAssertEqual(presentation.todayAndCurrent?.today.distanceMeters.value, 725)
        XCTAssertEqual(presentation.todayAndCurrent?.today.distanceMeters.availability, .partial)
        XCTAssertEqual(presentation.todayAndCurrent?.today.distanceMeters.excludedSegmentCount, 1)
        XCTAssertNil(presentation.todayAndCurrent?.today.durationSeconds.value)
        XCTAssertEqual(presentation.todayAndCurrent?.today.durationSeconds.availability, .unavailable)
        XCTAssertEqual(presentation.todayAndCurrent?.currentRide?.distanceMeters.value, 725)
        XCTAssertEqual(presentation.todayAndCurrent?.currentRide?.distanceMeters.availability, .partial)
    }

    func testHomeTodayMetricReadsDurableDayProjectionNotScooterSessionTrip() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repositoryRoot.appendingPathComponent("NembraApp/Features/Home/HomeView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        guard let metricStart = source.range(of: "private var tripDistanceText"),
              let nextMetric = source.range(
                of: "private var todayDistanceAccessibilityValue",
                range: metricStart.upperBound..<source.endIndex
              ) else {
            return XCTFail("Home must keep an explicit, auditable Today distance projection.")
        }
        let metricSource = String(source[metricStart.lowerBound..<nextMetric.lowerBound])

        XCTAssertTrue(metricSource.contains("daily.todayAndCurrent?.today.distanceMeters.value"))
        XCTAssertFalse(metricSource.contains("vehicle."))
        XCTAssertFalse(source.contains("vehicle.state.tripKilometers"))
    }

    private func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([
            StoredDailyRideSegment.self,
            StoredDailyRideAccumulatorState.self
        ])
        let configuration = ModelConfiguration(
            "NembraDailyRideSegmentTests-\(UUID().uuidString)",
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: nil,
            configurations: [configuration]
        )
    }

    private func acceptedSegment(
        sessionID: UUID,
        sequence: UInt64,
        distanceMeters: Double,
        beganAtDate: Date = ISO8601DateFormatter().date(from: "2026-08-18T18:00:00Z")!,
        endedAtDate: Date = ISO8601DateFormatter().date(from: "2026-08-18T18:10:00Z")!,
        calendar: Calendar? = nil
    ) throws -> AcceptedRideSegment {
        try acceptedSegment(
            sessionID: sessionID,
            sequence: sequence,
            distance: DailyRideMetricEvidence(value: distanceMeters, disposition: .complete),
            duration: DailyRideMetricEvidence(
                value: endedAtDate.timeIntervalSince(beganAtDate),
                disposition: .complete
            ),
            beganAtDate: beganAtDate,
            endedAtDate: endedAtDate,
            calendar: calendar
        )
    }

    private func checkpoint(
        sessionID: UUID,
        sequence: UInt64,
        uptime: UInt64,
        at wallDate: Date,
        distanceMeters: Double,
        durationSeconds: Double,
        calendar: Calendar? = nil
    ) throws -> AcceptedDailyRideCheckpoint {
        try AcceptedDailyRideCheckpoint(
            sessionID: sessionID,
            sequence: sequence,
            uptimeNanoseconds: uptime,
            wallDate: wallDate,
            localDay: RideLocalDay(
                containing: wallDate,
                calendar: calendar ?? localCalendar()
            ),
            cumulativeDistanceMeters: DailyRideMetricEvidence(
                value: distanceMeters,
                disposition: .complete
            ),
            cumulativeDurationSeconds: DailyRideMetricEvidence(
                value: durationSeconds,
                disposition: .complete
            ),
            distanceSource: .gpsRoute,
            continuity: .uninterruptedProcess
        )
    }

    @MainActor
    private func commitCheckpointPair(
        sessionID: UUID,
        distanceMeters: Double,
        store: SwiftDataDailyRideSegmentStore,
        startOffset: TimeInterval
    ) async throws {
        let baseDate = date("2026-08-18T18:00:00Z").addingTimeInterval(startOffset)
        var accumulator = DailyRideSegmentAccumulator(sessionID: sessionID)
        let anchor = try checkpoint(
            sessionID: sessionID,
            sequence: 0,
            uptime: UInt64(100 + startOffset),
            at: baseDate,
            distanceMeters: 0,
            durationSeconds: 0
        )
        let anchorProposal = try accumulator.prepare(anchor)
        _ = try await store.commit(anchorProposal)
        accumulator = anchorProposal.accumulatorAfterPersistence
        let next = try checkpoint(
            sessionID: sessionID,
            sequence: 1,
            uptime: UInt64(200 + startOffset),
            at: baseDate.addingTimeInterval(60),
            distanceMeters: distanceMeters,
            durationSeconds: 60
        )
        _ = try await store.commit(accumulator.prepare(next))
    }

    private func acceptedSegment(
        sessionID: UUID,
        sequence: UInt64,
        distance: DailyRideMetricEvidence,
        duration: DailyRideMetricEvidence,
        beganAtDate: Date = ISO8601DateFormatter().date(from: "2026-08-18T18:00:00Z")!,
        endedAtDate: Date = ISO8601DateFormatter().date(from: "2026-08-18T18:10:00Z")!,
        calendar: Calendar? = nil
    ) throws -> AcceptedRideSegment {
        try AcceptedRideSegment(
            id: AcceptedRideSegmentID(sessionID: sessionID, sequence: sequence),
            localDay: RideLocalDay(containing: beganAtDate, calendar: calendar ?? localCalendar()),
            beganAtDate: beganAtDate,
            endedAtDate: endedAtDate,
            distanceMeters: distance,
            durationSeconds: duration,
            distanceSource: distance.value == nil ? nil : .gpsRoute,
            continuity: .uninterruptedProcess,
            evidenceRevision: "daily-persistence-test-v1"
        )
    }

    private func localCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    private func temporaryDirectory(name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("NembraDailyRideTests-\(name)-\(UUID().uuidString)", isDirectory: true)
    }
}
