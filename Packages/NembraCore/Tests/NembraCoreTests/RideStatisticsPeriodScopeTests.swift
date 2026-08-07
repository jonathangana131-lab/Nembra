import Foundation
import Testing
@testable import NembraCore

@Suite("Ride statistics period-scoped reconciliation")
struct RideStatisticsPeriodScopeTests {
    private let selectedSessionID = UUID(uuidString: "A0000000-0000-0000-0000-000000000001")!
    private let historicalSessionID = UUID(uuidString: "B0000000-0000-0000-0000-000000000002")!

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int = 12
    ) -> Date {
        calendar.date(
            from: DateComponents(
                year: year,
                month: month,
                day: day,
                hour: hour
            )
        )!
    }

    private func ride(
        id: UUID,
        date: Date,
        distance: Double
    ) throws -> RideStatisticsRide {
        try RideStatisticsRide(
            sessionID: id,
            attributedDate: date,
            distanceMeters: distance,
            distanceDisposition: .included
        )
    }

    @Test("finite period ignores conflicting sessions that are wholly outside the requested window")
    func unrelatedHistoricalConflictDoesNotPoisonToday() throws {
        let reference = date(2026, 8, 6)
        let selected = try ride(
            id: selectedSessionID,
            date: date(2026, 8, 6, 9),
            distance: 1_250
        )
        let historicalA = try ride(
            id: historicalSessionID,
            date: date(2026, 7, 1),
            distance: 2_000
        )
        let historicalB = try ride(
            id: historicalSessionID,
            date: date(2026, 7, 1),
            distance: 2_500
        )

        let summary = try RideStatisticsAggregator.summarize(
            period: .today,
            rides: [historicalA, selected, historicalB],
            referenceDate: reference,
            calendar: calendar
        )

        #expect(summary.rideCount == 1)
        #expect(summary.trustworthyDistanceRideCount == 1)
        #expect(summary.excludedDistanceRideCount == 0)
        #expect(summary.distanceAvailability == .complete)
        #expect(summary.totalDistanceMeters == 1_250)
        #expect(summary.longestRideSessionID == selectedSessionID)
    }

    @Test("empty finite period is not invalidated by unrelated historical conflict")
    func unrelatedHistoricalConflictDoesNotPoisonEmptyPeriod() throws {
        let historicalA = try ride(
            id: historicalSessionID,
            date: date(2026, 7, 1),
            distance: 2_000
        )
        let historicalB = try ride(
            id: historicalSessionID,
            date: date(2026, 7, 1),
            distance: 2_500
        )

        let summary = try RideStatisticsAggregator.summarize(
            period: .today,
            rides: [historicalA, historicalB],
            referenceDate: date(2026, 8, 6),
            calendar: calendar
        )

        #expect(summary.rideCount == 0)
        #expect(summary.ridingDayCount == 0)
        #expect(summary.trustworthyDistanceRideCount == 0)
        #expect(summary.distanceAvailability == .noRides)
        #expect(summary.totalDistanceMeters == nil)
    }

    @Test("a selected session still reconciles every supplied copy across the period boundary")
    func selectedSessionConflictAcrossBoundaryFailsClosed() throws {
        let today = try ride(
            id: selectedSessionID,
            date: date(2026, 8, 6, 9),
            distance: 1_250
        )
        let conflictingYesterday = try ride(
            id: selectedSessionID,
            date: date(2026, 8, 5, 23),
            distance: 1_250
        )

        #expect(throws: RideStatisticsError.sessionConflict(selectedSessionID)) {
            _ = try RideStatisticsAggregator.summarize(
                period: .today,
                rides: [today, conflictingYesterday],
                referenceDate: date(2026, 8, 6),
                calendar: calendar
            )
        }
    }

    @Test("all-time keeps whole-history conflict detection")
    func allTimeStillRejectsHistoricalConflict() throws {
        let historicalA = try ride(
            id: historicalSessionID,
            date: date(2026, 7, 1),
            distance: 2_000
        )
        let historicalB = try ride(
            id: historicalSessionID,
            date: date(2026, 7, 1),
            distance: 2_500
        )

        #expect(throws: RideStatisticsError.sessionConflict(historicalSessionID)) {
            _ = try RideStatisticsAggregator.summarize(
                period: .allTime,
                rides: [historicalA, historicalB],
                referenceDate: date(2026, 8, 6),
                calendar: calendar
            )
        }
    }

    @Test("a finite period still rejects conflicting duplicates inside that period")
    func inPeriodConflictStillFailsClosed() throws {
        let first = try ride(
            id: selectedSessionID,
            date: date(2026, 8, 6, 9),
            distance: 1_250
        )
        let conflicting = try ride(
            id: selectedSessionID,
            date: date(2026, 8, 6, 9),
            distance: 1_500
        )

        #expect(throws: RideStatisticsError.sessionConflict(selectedSessionID)) {
            _ = try RideStatisticsAggregator.summarize(
                period: .today,
                rides: [first, conflicting],
                referenceDate: date(2026, 8, 6),
                calendar: calendar
            )
        }
    }
}
