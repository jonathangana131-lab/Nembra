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

    private func statisticsRide(
        at date: Date,
        durationNanoseconds: UInt64
    ) throws -> RideDurationStatisticsRide {
        let completed = try CompletedRideEvidence(
            sessionID: UUID(),
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
        let extremeDate = Date(timeIntervalSinceReferenceDate: Double.greatestFiniteMagnitude)

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

    @Test("calendar-unrepresentable history still fails closed when selected")
    func selectedUnrepresentableHistoryFailsClosed() throws {
        let reference = date(2026, 8, 7)
        let extremeDate = Date(timeIntervalSinceReferenceDate: Double.greatestFiniteMagnitude)
        let malformedForCalendar = try statisticsRide(
            at: extremeDate,
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
}
