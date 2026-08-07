import Foundation
import Testing
@testable import NembraCore

@Suite("Ride duration statistics period isolation")
struct RideDurationStatisticsPeriodIsolationTests {
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
        // Far beyond ICU calendar conversion range while still a finite Date.
        Date(timeIntervalSinceReferenceDate: 1_000_000_000_000_000)
    }

    private func statisticsRide(
        id: UUID = UUID(),
        at date: Date,
        durationNanoseconds: UInt64
    ) throws -> RideDurationStatisticsRide {
        let completed = try CompletedRideEvidence(
            sessionID: id,
            beganAtDate: date,
            confirmedAtDate: date,
            endedAtDate: date,
            startingOdometerKilometers: nil,
            endingOdometerKilometers: nil,
            qualityScreenedGPSDistanceMeters: 0,
            continuity: .uninterruptedProcess
        )
        let duration = try CompletedRideDurationEvidence(
            completedRide: completed,
            duration: RideSessionDurationEvidenceSnapshot(
                sessionID: completed.sessionID,
                observedDurationNanoseconds: durationNanoseconds,
                coverage: .complete,
                observationSegmentCount: 1
            )
        )
        return try RideDurationStatisticsRide(
            completedRide: completed,
            durationEvidence: duration,
            calendarAttribution: .rideBegan
        )
    }

    @Test("calendar-unrepresentable history outside a selected period cannot poison that period")
    func unrelatedUnrepresentableHistoryDoesNotPoisonSelectedPeriod() throws {
        let reference = date(2026, 8, 7)
        let currentRide = try statisticsRide(at: reference, durationNanoseconds: 20)
        let extremeDate = calendarUnrepresentableFiniteDate()

        #expect(extremeDate.timeIntervalSinceReferenceDate.isFinite)
        #expect(calendar().dateInterval(of: .day, for: extremeDate)?.contains(extremeDate) != true)

        let unrelatedHistory = try statisticsRide(
            at: extremeDate,
            durationNanoseconds: 10
        )
        let summary = try RideDurationStatisticsAggregator.summarize(
            period: .today,
            rides: [currentRide, unrelatedHistory],
            referenceDate: reference,
            calendar: calendar()
        )

        #expect(summary.rideCount == 1)
        #expect(summary.durationAvailability == .complete)
        #expect(summary.totalObservedDurationNanoseconds == 20)
    }

    @Test("conflicting duplicate history entirely outside a selected period cannot poison that period")
    func unrelatedDuplicateConflictDoesNotPoisonSelectedPeriod() throws {
        let reference = date(2026, 8, 7)
        let currentRide = try statisticsRide(at: reference, durationNanoseconds: 20)
        let historicalSessionID = UUID()
        let historicalDate = date(2026, 7, 1)
        let conflictingHistory = [
            try statisticsRide(
                id: historicalSessionID,
                at: historicalDate,
                durationNanoseconds: 10
            ),
            try statisticsRide(
                id: historicalSessionID,
                at: historicalDate,
                durationNanoseconds: 11
            )
        ]

        let summary = try RideDurationStatisticsAggregator.summarize(
            period: .today,
            rides: [currentRide] + conflictingHistory,
            referenceDate: reference,
            calendar: calendar()
        )

        #expect(summary.rideCount == 1)
        #expect(summary.durationAvailability == .complete)
        #expect(summary.totalObservedDurationNanoseconds == 20)
    }

    @Test("conflicting duplicate that touches selected period still fails closed")
    func selectedDuplicateConflictFailsClosed() throws {
        let reference = date(2026, 8, 7)
        let sessionID = UUID()
        let selectedRide = try statisticsRide(
            id: sessionID,
            at: reference,
            durationNanoseconds: 20
        )
        let conflictingHistoricalCopy = try statisticsRide(
            id: sessionID,
            at: date(2026, 7, 1),
            durationNanoseconds: 20
        )

        #expect(throws: RideDurationStatisticsError.sessionConflict(sessionID)) {
            _ = try RideDurationStatisticsAggregator.summarize(
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
        let malformedForCalendar = try statisticsRide(
            at: calendarUnrepresentableFiniteDate(),
            durationNanoseconds: 10
        )

        #expect(throws: RideDurationStatisticsError.invalidRide) {
            _ = try RideDurationStatisticsAggregator.summarize(
                period: .allTime,
                rides: [malformedForCalendar],
                referenceDate: reference,
                calendar: calendar()
            )
        }
    }

    @Test("all-time summary does not require calendar representation of an unused finite reference date")
    func allTimeIgnoresUnusedCalendarReferenceRepresentation() throws {
        let ride = try statisticsRide(
            at: date(2026, 8, 7),
            durationNanoseconds: 30
        )
        let extremeReference = calendarUnrepresentableFiniteDate()

        #expect(extremeReference.timeIntervalSinceReferenceDate.isFinite)
        #expect(calendar().dateInterval(of: .day, for: extremeReference)?.contains(extremeReference) != true)

        let summary = try RideDurationStatisticsAggregator.summarize(
            period: .allTime,
            rides: [ride],
            referenceDate: extremeReference,
            calendar: calendar()
        )

        #expect(summary.rideCount == 1)
        #expect(summary.durationAvailability == .complete)
        #expect(summary.totalObservedDurationNanoseconds == 30)
    }

    @Test("calendar-bounded periods still reject an unrepresentable reference date")
    func calendarBoundedPeriodRejectsUnrepresentableReference() throws {
        #expect(throws: RideDurationStatisticsError.invalidReferenceDate) {
            _ = try RideDurationStatisticsAggregator.summarize(
                period: .today,
                rides: [],
                referenceDate: calendarUnrepresentableFiniteDate(),
                calendar: calendar()
            )
        }
    }
}
