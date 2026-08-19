import Foundation
import Testing
@testable import NembraCore

@Suite("Accepted daily segment accumulator")
struct DailyRideSegmentAccumulatorTests {
    private let sessionID = UUID(uuidString: "DAD10000-0000-0000-0000-000000000001")!

    private func calendar(
        _ zone: String = "America/Los_Angeles",
        identifier: Calendar.Identifier = .gregorian
    ) -> Calendar {
        var calendar = Calendar(identifier: identifier)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    private func metric(
        _ value: Double?,
        _ disposition: DailyRideMetricDisposition
    ) throws -> DailyRideMetricEvidence {
        try DailyRideMetricEvidence(value: value, disposition: disposition)
    }

    private func checkpoint(
        sequence: UInt64,
        uptime: UInt64,
        at wallDate: Date,
        calendar: Calendar? = nil,
        distance: Double? = 0,
        distanceDisposition: DailyRideMetricDisposition = .complete,
        duration: Double? = 0,
        durationDisposition: DailyRideMetricDisposition = .complete,
        source: RideDistanceSource? = .gpsRoute,
        continuity: RideSessionContinuity = .uninterruptedProcess,
        sessionID: UUID? = nil
    ) throws -> AcceptedDailyRideCheckpoint {
        let selectedCalendar = calendar ?? self.calendar()
        return try AcceptedDailyRideCheckpoint(
            sessionID: sessionID ?? self.sessionID,
            sequence: sequence,
            uptimeNanoseconds: uptime,
            wallDate: wallDate,
            localDay: RideLocalDay(containing: wallDate, calendar: selectedCalendar),
            cumulativeDistanceMeters: metric(distance, distanceDisposition),
            cumulativeDurationSeconds: metric(duration, durationDisposition),
            distanceSource: distance == nil ? nil : source,
            continuity: continuity
        )
    }

    @discardableResult
    private func persist(
        _ checkpoint: AcceptedDailyRideCheckpoint,
        into accumulator: inout DailyRideSegmentAccumulator
    ) throws -> DailyRideSegmentCommitProposal {
        let proposal = try accumulator.prepare(checkpoint)
        accumulator = proposal.accumulatorAfterPersistence
        return proposal
    }

    @Test("a non-exact midnight crossing closes both days without splitting the cumulative delta")
    func midnightDoesNotInventAllocation() throws {
        let before = try checkpoint(
            sequence: 0,
            uptime: 100,
            at: date("2026-08-19T06:59:30Z"),
            distance: 100,
            duration: 10
        )
        let after = try checkpoint(
            sequence: 1,
            uptime: 200,
            at: date("2026-08-19T07:00:30Z"),
            distance: 300,
            duration: 70
        )
        var accumulator = DailyRideSegmentAccumulator(sessionID: sessionID)
        try persist(before, into: &accumulator)

        let boundary = try persist(after, into: &accumulator)
        #expect(boundary.disposition == .unobservedIdentityBoundary)
        #expect(boundary.segmentsToPersist.count == 2)
        #expect(boundary.segmentsToPersist.map(\.id.sequence) == [0, 1])
        #expect(boundary.segmentsToPersist[0].localDay == before.localDay)
        #expect(boundary.segmentsToPersist[0].endedAtDate == before.localDay.endDate)
        #expect(boundary.segmentsToPersist[1].localDay == after.localDay)
        #expect(boundary.segmentsToPersist[1].beganAtDate == after.localDay.startDate)
        #expect(boundary.segmentsToPersist.allSatisfy {
            $0.distanceMeters.disposition == .unavailable && $0.distanceMeters.value == nil
        })
        #expect(boundary.segmentsToPersist.allSatisfy {
            $0.durationSeconds.disposition == .unavailable && $0.durationSeconds.value == nil
        })

        let later = try checkpoint(
            sequence: 2,
            uptime: 300,
            at: date("2026-08-19T07:01:30Z"),
            distance: 400,
            duration: 130
        )
        let resumed = try persist(later, into: &accumulator)
        #expect(resumed.segmentsToPersist.map(\.id.sequence) == [2])
        #expect(resumed.segmentsToPersist[0].distanceMeters.value == 100)
        #expect(resumed.segmentsToPersist[0].durationSeconds.value == 60)
    }

    @Test("exact checkpoints respect both 23-hour and 25-hour DST day boundaries")
    func daylightSavingDayLengths() throws {
        let la = calendar()
        let cases: [(before: String, boundary: String, expectedHours: Double)] = [
            ("2026-03-09T06:59:30Z", "2026-03-09T07:00:00Z", 23),
            ("2026-11-02T07:59:30Z", "2026-11-02T08:00:00Z", 25)
        ]

        for (index, value) in cases.enumerated() {
            let caseSession = UUID(
                uuidString: index == 0
                    ? "DAD10000-0000-0000-0000-000000000023"
                    : "DAD10000-0000-0000-0000-000000000025"
            )!
            let beforeDate = date(value.before)
            let boundaryDate = date(value.boundary)
            let first = try checkpoint(
                sequence: 0,
                uptime: 100,
                at: beforeDate,
                calendar: la,
                distance: 10,
                duration: 10,
                sessionID: caseSession
            )
            let exact = try checkpoint(
                sequence: 1,
                uptime: 200,
                at: boundaryDate,
                calendar: la,
                distance: 40,
                duration: 40,
                sessionID: caseSession
            )
            var accumulator = DailyRideSegmentAccumulator(sessionID: caseSession)
            try persist(first, into: &accumulator)
            let proposal = try persist(exact, into: &accumulator)

            #expect(first.localDay.endDate.timeIntervalSince(first.localDay.startDate)
                == value.expectedHours * 3_600)
            #expect(proposal.disposition == .exactLocalDayBoundary)
            #expect(proposal.segmentsToPersist.count == 1)
            #expect(proposal.segmentsToPersist[0].localDay == first.localDay)
            #expect(proposal.segmentsToPersist[0].endedAtDate == boundaryDate)
            #expect(proposal.segmentsToPersist[0].distanceMeters.value == 30)
            #expect(proposal.segmentsToPersist[0].durationSeconds.value == 30)
        }
    }

    @Test("a time-zone identity change closes ownership even when UTC day intervals match")
    func timeZoneIdentityChangeWithSameDayStart() throws {
        let instant = date("2026-01-15T18:00:00Z")
        let losAngeles = calendar("America/Los_Angeles")
        let vancouver = calendar("America/Vancouver")
        let first = try checkpoint(
            sequence: 0,
            uptime: 100,
            at: instant,
            calendar: losAngeles,
            distance: 100,
            duration: 10
        )
        let changed = try checkpoint(
            sequence: 1,
            uptime: 200,
            at: instant.addingTimeInterval(60),
            calendar: vancouver,
            distance: 200,
            duration: 70
        )
        #expect(first.localDay.startDate == changed.localDay.startDate)
        #expect(first.localDay.endDate == changed.localDay.endDate)
        #expect(first.localDay != changed.localDay)

        var accumulator = DailyRideSegmentAccumulator(sessionID: sessionID)
        try persist(first, into: &accumulator)
        let proposal = try persist(changed, into: &accumulator)
        #expect(proposal.disposition == .unobservedIdentityBoundary)
        #expect(proposal.segmentsToPersist.count == 2)
        #expect(proposal.segmentsToPersist[0].beganAtDate == instant)
        #expect(proposal.segmentsToPersist[0].endedAtDate == changed.wallDate)
        #expect(proposal.segmentsToPersist[1].beganAtDate == changed.wallDate)
        #expect(proposal.segmentsToPersist[1].endedAtDate == changed.wallDate)
        #expect(proposal.segmentsToPersist.allSatisfy {
            $0.distanceMeters.disposition == .unavailable
        })
    }

    @Test("a calendar identity change also closes the active day owner")
    func calendarIdentityChange() throws {
        let instant = date("2026-08-18T18:00:00Z")
        let gregorian = calendar(identifier: .gregorian)
        let iso8601 = calendar(identifier: .iso8601)
        let first = try checkpoint(
            sequence: 0,
            uptime: 100,
            at: instant,
            calendar: gregorian,
            distance: 100,
            duration: 10
        )
        let changed = try checkpoint(
            sequence: 1,
            uptime: 200,
            at: instant.addingTimeInterval(60),
            calendar: iso8601,
            distance: 200,
            duration: 70
        )
        #expect(first.localDay.startDate == changed.localDay.startDate)
        #expect(first.localDay.calendarIdentifier != changed.localDay.calendarIdentifier)

        var accumulator = DailyRideSegmentAccumulator(sessionID: sessionID)
        try persist(first, into: &accumulator)
        let proposal = try persist(changed, into: &accumulator)
        #expect(proposal.disposition == .unobservedIdentityBoundary)
        #expect(proposal.segmentsToPersist.count == 2)
        #expect(proposal.segmentsToPersist.allSatisfy {
            $0.distanceMeters.disposition == .unavailable
        })
    }

    @Test("disconnect and recovery continuity preserve accepted cumulative deltas")
    func disconnectReconnect() throws {
        let start = date("2026-08-18T18:00:00Z")
        var accumulator = DailyRideSegmentAccumulator(sessionID: sessionID)
        try persist(
            checkpoint(sequence: 0, uptime: 100, at: start, distance: 0, duration: 0),
            into: &accumulator
        )
        let connected = try persist(
            checkpoint(
                sequence: 1,
                uptime: 200,
                at: start.addingTimeInterval(60),
                distance: 500,
                duration: 60
            ),
            into: &accumulator
        )
        let recovered = try persist(
            checkpoint(
                sequence: 2,
                uptime: 300,
                at: start.addingTimeInterval(180),
                distance: 900,
                duration: 120,
                continuity: .recoveredCheckpoint
            ),
            into: &accumulator
        )

        #expect(connected.segmentsToPersist[0].distanceMeters.value == 500)
        #expect(recovered.segmentsToPersist[0].distanceMeters.value == 400)
        #expect(recovered.segmentsToPersist[0].durationSeconds.value == 60)
        #expect(recovered.segmentsToPersist[0].continuity == .recoveredCheckpoint)
        let summary = try DailyRideLedgerProjection.todayAndCurrentRide(
            segments: connected.segmentsToPersist + recovered.segmentsToPersist,
            today: recovered.checkpoint.localDay,
            currentRideSessionID: sessionID
        )
        #expect(summary.today.distanceMeters.value == 900)
        #expect(summary.today.containsRecoveredRide)
    }

    @Test("restoration makes replay idempotent and continues stable segment IDs")
    func relaunchReplayAndContinuation() throws {
        let start = date("2026-08-18T18:00:00Z")
        let first = try checkpoint(sequence: 4, uptime: 100, at: start, distance: 0, duration: 0)
        let second = try checkpoint(
            sequence: 8,
            uptime: 200,
            at: start.addingTimeInterval(60),
            distance: 100,
            duration: 60
        )
        var accumulator = DailyRideSegmentAccumulator(sessionID: sessionID)
        try persist(first, into: &accumulator)
        try persist(second, into: &accumulator)

        let restored = try JSONDecoder().decode(
            DailyRideSegmentAccumulator.self,
            from: JSONEncoder().encode(accumulator)
        )
        let replay = try restored.prepare(second)
        #expect(replay.disposition == .idempotentReplay)
        #expect(replay.segmentsToPersist.isEmpty)
        #expect(replay.accumulatorAfterPersistence == restored)

        let third = try checkpoint(
            sequence: 9,
            uptime: 300,
            at: start.addingTimeInterval(120),
            distance: 250,
            duration: 120
        )
        let continued = try restored.prepare(third)
        #expect(continued.segmentsToPersist.map(\.id.sequence) == [1])
        #expect(continued.segmentsToPersist[0].distanceMeters.value == 150)
    }

    @Test("duplicate receipts are idempotent while conflicts and nonmonotonic order fail closed")
    func replayAndOrderingFailures() throws {
        let start = date("2026-08-18T18:00:00Z")
        let first = try checkpoint(sequence: 10, uptime: 100, at: start, distance: 0, duration: 0)
        let last = try checkpoint(
            sequence: 20,
            uptime: 200,
            at: start.addingTimeInterval(60),
            distance: 100,
            duration: 60
        )
        var accumulator = DailyRideSegmentAccumulator(sessionID: sessionID)
        try persist(first, into: &accumulator)
        try persist(last, into: &accumulator)

        #expect(try accumulator.prepare(first).disposition == .idempotentReplay)
        let conflict = try checkpoint(
            sequence: 10,
            uptime: 100,
            at: start,
            distance: 1,
            duration: 0
        )
        #expect(throws: DailyRideSegmentAccumulatorError.conflictingReplay(sequence: 10)) {
            _ = try accumulator.prepare(conflict)
        }
        let missingEarlierSequence = try checkpoint(
            sequence: 15,
            uptime: 300,
            at: start.addingTimeInterval(120),
            distance: 150,
            duration: 120
        )
        #expect(throws: DailyRideSegmentAccumulatorError.nonmonotonicSequence(
            previous: 20,
            incoming: 15
        )) {
            _ = try accumulator.prepare(missingEarlierSequence)
        }
        let staleUptime = try checkpoint(
            sequence: 21,
            uptime: 200,
            at: start.addingTimeInterval(120),
            distance: 150,
            duration: 120
        )
        #expect(throws: DailyRideSegmentAccumulatorError.nonmonotonicUptime(
            previous: 200,
            incoming: 200
        )) {
            _ = try accumulator.prepare(staleUptime)
        }
    }

    @Test("a failed persistence attempt is not acknowledged and retries identical IDs")
    func persistenceFailureIsNotAcknowledged() throws {
        let start = date("2026-08-18T18:00:00Z")
        let first = try checkpoint(sequence: 0, uptime: 100, at: start, distance: 0, duration: 0)
        let second = try checkpoint(
            sequence: 1,
            uptime: 200,
            at: start.addingTimeInterval(60),
            distance: 100,
            duration: 60
        )
        var accumulator = DailyRideSegmentAccumulator(sessionID: sessionID)
        try persist(first, into: &accumulator)

        let failedAttempt = try accumulator.prepare(second)
        #expect(accumulator.lastAcknowledgedCheckpoint == first)
        #expect(accumulator.nextSegmentSequence == 0)
        let retry = try accumulator.prepare(second)
        #expect(retry == failedAttempt)
        #expect(retry.segmentsToPersist.map(\.id.sequence) == [0])

        accumulator = retry.accumulatorAfterPersistence
        let replayAfterCommit = try accumulator.prepare(second)
        #expect(replayAfterCommit.disposition == .idempotentReplay)
        #expect(replayAfterCommit.segmentsToPersist.isEmpty)
    }

    @Test("missing distance remains unavailable and later evidence resumes without backfill")
    func missingDistanceDoesNotBackfill() throws {
        let start = date("2026-08-18T18:00:00Z")
        var accumulator = DailyRideSegmentAccumulator(sessionID: sessionID)
        try persist(
            checkpoint(
                sequence: 0,
                uptime: 100,
                at: start,
                distance: nil,
                distanceDisposition: .unavailable,
                duration: 0,
                source: nil
            ),
            into: &accumulator
        )
        let unavailable = try persist(
            checkpoint(
                sequence: 1,
                uptime: 200,
                at: start.addingTimeInterval(60),
                distance: 100,
                duration: 60
            ),
            into: &accumulator
        )
        let known = try persist(
            checkpoint(
                sequence: 2,
                uptime: 300,
                at: start.addingTimeInterval(120),
                distance: 150,
                duration: 120
            ),
            into: &accumulator
        )

        #expect(unavailable.segmentsToPersist[0].distanceMeters.disposition == .unavailable)
        #expect(unavailable.segmentsToPersist[0].distanceMeters.value == nil)
        #expect(known.segmentsToPersist[0].distanceMeters.value == 50)
        let summary = try DailyRideLedgerProjection.todayAndCurrentRide(
            segments: unavailable.segmentsToPersist + known.segmentsToPersist,
            today: known.checkpoint.localDay,
            currentRideSessionID: sessionID
        )
        #expect(summary.today.distanceMeters.value == 50)
        #expect(summary.today.distanceMeters.availability == .partial)
    }

    @Test("wall-clock regression with monotonic uptime loses placement, not session order")
    func wallClockRegression() throws {
        let firstDate = date("2026-08-18T18:00:00Z")
        var accumulator = DailyRideSegmentAccumulator(sessionID: sessionID)
        try persist(
            checkpoint(sequence: 0, uptime: 100, at: firstDate, distance: 0, duration: 0),
            into: &accumulator
        )
        let regressed = try persist(
            checkpoint(
                sequence: 1,
                uptime: 200,
                at: firstDate.addingTimeInterval(-60),
                distance: 100,
                duration: 60
            ),
            into: &accumulator
        )
        #expect(regressed.disposition == .wallClockRegression)
        #expect(regressed.segmentsToPersist.count == 1)
        #expect(regressed.segmentsToPersist[0].beganAtDate
            == regressed.segmentsToPersist[0].endedAtDate)
        #expect(regressed.segmentsToPersist[0].distanceMeters.disposition == .unavailable)

        let resumed = try persist(
            checkpoint(
                sequence: 2,
                uptime: 300,
                at: firstDate.addingTimeInterval(60),
                distance: 150,
                duration: 120
            ),
            into: &accumulator
        )
        #expect(resumed.segmentsToPersist[0].distanceMeters.value == 50)
        let summary = try DailyRideLedgerProjection.todayAndCurrentRide(
            segments: regressed.segmentsToPersist + resumed.segmentsToPersist,
            today: resumed.checkpoint.localDay,
            currentRideSessionID: sessionID
        )
        #expect(summary.today.distanceMeters.value == 50)
        #expect(summary.today.distanceMeters.availability == .partial)
    }

    @Test("cumulative metric regression is rejected before state or segments advance")
    func cumulativeRegressionFailsClosed() throws {
        let start = date("2026-08-18T18:00:00Z")
        var accumulator = DailyRideSegmentAccumulator(sessionID: sessionID)
        try persist(
            checkpoint(sequence: 0, uptime: 100, at: start, distance: 100, duration: 60),
            into: &accumulator
        )
        let regressedDistance = try checkpoint(
            sequence: 1,
            uptime: 200,
            at: start.addingTimeInterval(60),
            distance: 99,
            duration: 120
        )
        #expect(throws: DailyRideSegmentAccumulatorError.cumulativeDistanceRegressed(sequence: 1)) {
            _ = try accumulator.prepare(regressedDistance)
        }
        #expect(accumulator.nextSegmentSequence == 0)
        #expect(accumulator.lastAcknowledgedCheckpoint?.sequence == 0)
    }
}
