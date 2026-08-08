import Foundation
import Testing
@testable import NembraCore

@Suite("Ride statistics period isolation")
struct RideStatisticsPeriodIsolationTests {
    private func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        calendar().date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func calendarUnrepresentableFiniteDate() -> Date {
        // Far beyond ICU calendar conversion range while remaining a finite Date.
        Date(timeIntervalSinceReferenceDate: 1_000_000_000_000_000)
    }

    private func ride(
        id: UUID = UUID(),
        at date: Date,
        distanceMeters: Double = 1_000
    ) throws -> RideStatisticsRide {
        try RideStatisticsRide(
            sessionID: id,
            attributedDate: date,
            distanceMeters: distanceMeters,
            distanceDisposition: .included
        )
    }

    @Test("calendar-unrepresentable history outside a selected period cannot poison that period")
    func unrelatedUnrepresentableHistoryDoesNotPoisonSelectedPeriod() throws {
        let reference = date(2026, 8, 7)
        let currentRide = try ride(at: reference, distanceMeters: 1_200)
        let extremeDate = calendarUnrepresentableFiniteDate()

        #expect(extremeDate.timeIntervalSinceReferenceDate.isFinite)
        #expect(calendar().dateInterval(of: .day, for: extremeDate)?.contains(extremeDate) != true)

        let unrelatedHistory = try ride(at: extremeDate, distanceMeters: 9_000)
        let summary = try RideStatisticsAggregator.summarize(
            period: .today,
            rides: [currentRide, unrelatedHistory],
            referenceDate: reference,
            calendar: calendar()
        )

        #expect(summary.rideCount == 1)
        #expect(summary.ridingDayCount == 1)
        #expect(summary.distanceAvailability == .complete)
        #expect(summary.totalDistanceMeters == 1_200)
        #expect(summary.longestRideSessionID == currentRide.sessionID)
    }

    @Test("conflicting duplicate history entirely outside a selected period cannot poison that period")
    func unrelatedDuplicateConflictDoesNotPoisonSelectedPeriod() throws {
        let reference = date(2026, 8, 7)
        let currentRide = try ride(at: reference, distanceMeters: 1_200)
        let historicalSessionID = UUID()
        let historicalDate = date(2026, 7, 1)
        let conflictingHistory = [
            try ride(id: historicalSessionID, at: historicalDate, distanceMeters: 1_000),
            try ride(id: historicalSessionID, at: historicalDate, distanceMeters: 2_000)
        ]

        let summary = try RideStatisticsAggregator.summarize(
            period: .today,
            rides: [currentRide] + conflictingHistory,
            referenceDate: reference,
            calendar: calendar()
        )

        #expect(summary.rideCount == 1)
        #expect(summary.distanceAvailability == .complete)
        #expect(summary.totalDistanceMeters == 1_200)
    }

    @Test("conflicting duplicate that touches selected period still fails closed")
    func selectedDuplicateConflictFailsClosed() throws {
        let reference = date(2026, 8, 7)
        let sessionID = UUID()
        let selectedRide = try ride(
            id: sessionID,
            at: reference,
            distanceMeters: 1_200
        )
        let conflictingHistoricalCopy = try ride(
            id: sessionID,
            at: date(2026, 7, 1),
            distanceMeters: 1_200
        )

        #expect(throws: RideStatisticsError.sessionConflict(sessionID)) {
            _ = try RideStatisticsAggregator.summarize(
                period: .today,
                rides: [selectedRide, conflictingHistoricalCopy],
                referenceDate: reference,
                calendar: calendar()
            )
        }
    }

    @Test("calendar-unrepresentable history still fails closed when selected")
    func selectedUnrepresentableHistoryFailsClosed() throws {
        let reference = date(2026, 8, 7)
        let malformedForCalendar = try ride(
            at: calendarUnrepresentableFiniteDate(),
            distanceMeters: 1_000
        )

        #expect(throws: RideStatisticsError.invalidRide) {
            _ = try RideStatisticsAggregator.summarize(
                period: .allTime,
                rides: [malformedForCalendar],
                referenceDate: reference,
                calendar: calendar()
            )
        }
    }

    @Test("all-time summary does not require calendar representation of an unused finite reference date")
    func allTimeIgnoresUnusedCalendarReferenceRepresentation() throws {
        let currentRide = try ride(at: date(2026, 8, 7), distanceMeters: 1_500)
        let extremeReference = calendarUnrepresentableFiniteDate()

        #expect(extremeReference.timeIntervalSinceReferenceDate.isFinite)
        #expect(calendar().dateInterval(of: .day, for: extremeReference)?.contains(extremeReference) != true)

        let summary = try RideStatisticsAggregator.summarize(
            period: .allTime,
            rides: [currentRide],
            referenceDate: extremeReference,
            calendar: calendar()
        )

        #expect(summary.rideCount == 1)
        #expect(summary.ridingDayCount == 1)
        #expect(summary.distanceAvailability == .complete)
        #expect(summary.totalDistanceMeters == 1_500)
    }

    @Test("calendar-bounded periods still reject an unrepresentable reference date")
    func calendarBoundedPeriodRejectsUnrepresentableReference() throws {
        #expect(throws: RideStatisticsError.invalidReferenceDate) {
            _ = try RideStatisticsAggregator.summarize(
                period: .today,
                rides: [],
                referenceDate: calendarUnrepresentableFiniteDate(),
                calendar: calendar()
            )
        }
    }
}
