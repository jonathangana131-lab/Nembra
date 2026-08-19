import Foundation
import Testing
@testable import NembraCore

@Suite("Durable local-day ride ledger")
struct DailyRideLedgerTests {
    private let sessionA = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
    private let sessionB = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!

    private func calendar(_ zone: String = "America/Los_Angeles") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    private func metric(_ value: Double?, _ disposition: DailyRideMetricDisposition) throws -> DailyRideMetricEvidence {
        try DailyRideMetricEvidence(value: value, disposition: disposition)
    }

    private func segment(
        sessionID: UUID,
        sequence: UInt64,
        start: Date,
        end: Date,
        localDay: RideLocalDay,
        distance: DailyRideMetricEvidence,
        duration: DailyRideMetricEvidence,
        continuity: RideSessionContinuity = .uninterruptedProcess
    ) throws -> AcceptedRideSegment {
        try AcceptedRideSegment(
            id: AcceptedRideSegmentID(sessionID: sessionID, sequence: sequence),
            localDay: localDay,
            beganAtDate: start,
            endedAtDate: end,
            distanceMeters: distance,
            durationSeconds: duration,
            distanceSource: distance.value == nil ? nil : .gpsRoute,
            continuity: continuity,
            evidenceRevision: "ride-distance-reconciliation-v1"
        )
    }

    @Test("multiple power-session rides sum into one durable Today total")
    func multipleRidesSumAcrossPowerCycles() throws {
        let day = try RideLocalDay(containing: date("2026-08-18T18:00:00Z"), calendar: calendar())
        let first = try segment(
            sessionID: sessionA,
            sequence: 0,
            start: date("2026-08-18T17:00:00Z"),
            end: date("2026-08-18T17:10:00Z"),
            localDay: day,
            distance: metric(1_250, .complete),
            duration: metric(600, .complete)
        )
        let second = try segment(
            sessionID: sessionB,
            sequence: 0,
            start: date("2026-08-18T20:00:00Z"),
            end: date("2026-08-18T20:20:00Z"),
            localDay: day,
            distance: metric(2_750, .complete),
            duration: metric(1_200, .complete)
        )

        let result = try DailyRideLedgerProjection.todayAndCurrentRide(
            segments: [first, second],
            today: day,
            currentRideSessionID: sessionB
        )
        #expect(result.today.rideCount == 2)
        #expect(result.today.distanceMeters.value == 4_000)
        #expect(result.today.durationSeconds.value == 1_800)
        #expect(result.currentRide?.distanceMeters.value == 2_750)
        #expect(result.currentRide?.durationSeconds.value == 1_200)
    }

    @Test("duplicate replay is idempotent while conflicting replay fails closed")
    func duplicateReplay() throws {
        let day = try RideLocalDay(containing: date("2026-08-18T18:00:00Z"), calendar: calendar())
        let accepted = try segment(
            sessionID: sessionA,
            sequence: 4,
            start: date("2026-08-18T18:00:00Z"),
            end: date("2026-08-18T18:01:00Z"),
            localDay: day,
            distance: metric(200, .complete),
            duration: metric(60, .complete)
        )
        let replayed = try DailyRideLedgerProjection.todayAndCurrentRide(
            segments: [accepted, accepted],
            today: day,
            currentRideSessionID: nil
        )
        #expect(replayed.today.segmentCount == 1)
        #expect(replayed.today.distanceMeters.value == 200)

        let conflicting = try segment(
            sessionID: sessionA,
            sequence: 4,
            start: accepted.beganAtDate,
            end: accepted.endedAtDate,
            localDay: day,
            distance: metric(201, .complete),
            duration: metric(60, .complete)
        )
        #expect(throws: DailyRideLedgerError.segmentConflict(accepted.id)) {
            _ = try DailyRideLedgerProjection.todayAndCurrentRide(
                segments: [accepted, conflicting],
                today: day,
                currentRideSessionID: nil
            )
        }
    }

    @Test("midnight requires explicit day-aligned segments instead of proportional invention")
    func midnightBoundary() throws {
        let cal = calendar()
        let before = date("2026-08-19T06:59:30Z")
        let boundary = date("2026-08-19T07:00:00Z")
        let after = date("2026-08-19T07:00:30Z")
        let firstDay = try RideLocalDay(containing: before, calendar: cal)
        let secondDay = try RideLocalDay(containing: after, calendar: cal)

        #expect(throws: DailyRideLedgerError.invalidSegment) {
            _ = try segment(
                sessionID: sessionA,
                sequence: 0,
                start: before,
                end: after,
                localDay: firstDay,
                distance: metric(300, .complete),
                duration: metric(60, .complete)
            )
        }

        let first = try segment(
            sessionID: sessionA,
            sequence: 0,
            start: before,
            end: boundary,
            localDay: firstDay,
            distance: metric(120, .complete),
            duration: metric(30, .complete)
        )
        let second = try segment(
            sessionID: sessionA,
            sequence: 1,
            start: boundary,
            end: after,
            localDay: secondDay,
            distance: metric(180, .complete),
            duration: metric(30, .complete)
        )
        let firstSummary = try DailyRideLedgerProjection.todayAndCurrentRide(
            segments: [first, second], today: firstDay, currentRideSessionID: sessionA
        )
        let secondSummary = try DailyRideLedgerProjection.todayAndCurrentRide(
            segments: [first, second], today: secondDay, currentRideSessionID: sessionA
        )
        #expect(firstSummary.today.distanceMeters.value == 120)
        #expect(secondSummary.today.distanceMeters.value == 180)
        #expect(secondSummary.currentRide?.distanceMeters.value == 300)
    }

    @Test("captured time-zone day identity does not retroactively move accepted mileage")
    func timeZoneChangeIsFrozen() throws {
        let instant = date("2026-08-18T08:30:00Z")
        let losAngelesDay = try RideLocalDay(containing: instant, calendar: calendar("America/Los_Angeles"))
        let newYorkDay = try RideLocalDay(containing: instant, calendar: calendar("America/New_York"))
        #expect(losAngelesDay != newYorkDay)

        let acceptedInLosAngeles = try segment(
            sessionID: sessionA,
            sequence: 0,
            start: instant,
            end: instant.addingTimeInterval(30),
            localDay: losAngelesDay,
            distance: metric(100, .complete),
            duration: metric(30, .complete)
        )
        let viewedAfterTravel = try DailyRideLedgerProjection.todayAndCurrentRide(
            segments: [acceptedInLosAngeles],
            today: newYorkDay,
            currentRideSessionID: sessionA
        )
        #expect(viewedAfterTravel.today.distanceMeters.availability == .noEvidence)
        #expect(viewedAfterTravel.currentRide?.distanceMeters.value == 100)
    }

    @Test("DST days retain their true 23 or 25 hour local intervals")
    func daylightSavingBoundaries() throws {
        let cal = calendar("America/Los_Angeles")
        let spring = try RideLocalDay(containing: date("2026-03-08T20:00:00Z"), calendar: cal)
        let fall = try RideLocalDay(containing: date("2026-11-01T20:00:00Z"), calendar: cal)
        #expect(spring.endDate.timeIntervalSince(spring.startDate) == 23 * 3_600)
        #expect(fall.endDate.timeIntervalSince(fall.startDate) == 25 * 3_600)
    }

    @Test("partial and unavailable segments never become a fake complete total")
    func partialAndUnavailableTruth() throws {
        let day = try RideLocalDay(containing: date("2026-08-18T18:00:00Z"), calendar: calendar())
        let known = try segment(
            sessionID: sessionA,
            sequence: 0,
            start: date("2026-08-18T18:00:00Z"),
            end: date("2026-08-18T18:01:00Z"),
            localDay: day,
            distance: metric(180, .knownPartial),
            duration: metric(60, .complete),
            continuity: .recoveredCheckpoint
        )
        let unavailable = try segment(
            sessionID: sessionB,
            sequence: 0,
            start: date("2026-08-18T19:00:00Z"),
            end: date("2026-08-18T19:01:00Z"),
            localDay: day,
            distance: metric(nil, .unavailable),
            duration: metric(nil, .conflicting)
        )
        let result = try DailyRideLedgerProjection.todayAndCurrentRide(
            segments: [known, unavailable], today: day, currentRideSessionID: nil
        )
        #expect(result.today.distanceMeters.value == 180)
        #expect(result.today.distanceMeters.availability == .partial)
        #expect(result.today.durationSeconds.value == 60)
        #expect(result.today.durationSeconds.availability == .partial)
        #expect(result.today.containsRecoveredRide)
    }

    @Test("metric decoding and segment Codable revalidate authority invariants")
    func codableValidation() throws {
        let day = try RideLocalDay(containing: date("2026-08-18T18:00:00Z"), calendar: calendar())
        let accepted = try segment(
            sessionID: sessionA,
            sequence: 0,
            start: date("2026-08-18T18:00:00Z"),
            end: date("2026-08-18T18:01:00Z"),
            localDay: day,
            distance: metric(100, .complete),
            duration: metric(60, .complete)
        )
        let data = try JSONEncoder().encode(accepted)
        #expect(try JSONDecoder().decode(AcceptedRideSegment.self, from: data) == accepted)

        let invalid = Data(#"{"disposition":"complete"}"#.utf8)
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(DailyRideMetricEvidence.self, from: invalid)
        }
    }
}
