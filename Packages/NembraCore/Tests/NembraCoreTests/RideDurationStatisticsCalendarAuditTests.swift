import Foundation
import Testing
@testable import NembraCore

@Suite("Ride duration calendar audit")
struct RideDurationStatisticsCalendarAuditTests {
    private func calendar(_ timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    private func completedRide(
        id: UUID = UUID(),
        at date: Date
    ) throws -> CompletedRideEvidence {
        try CompletedRideEvidence(
            sessionID: id,
            beganAtDate: date,
            confirmedAtDate: date,
            endedAtDate: date,
            startingOdometerKilometers: nil,
            endingOdometerKilometers: nil,
            qualityScreenedGPSDistanceMeters: 0,
            continuity: .uninterruptedProcess
        )
    }

    private func statisticsRide(
        at date: Date,
        duration: UInt64 = 1
    ) throws -> RideDurationStatisticsRide {
        let completed = try completedRide(at: date)
        let evidence = try CompletedRideDurationEvidence(
            completedRide: completed,
            duration: RideSessionDurationEvidenceSnapshot(
                sessionID: completed.sessionID,
                observedDurationNanoseconds: duration,
                coverage: .complete,
                observationSegmentCount: 1
            )
        )
        return try RideDurationStatisticsRide(
            completedRide: completed,
            durationEvidence: evidence,
            calendarAttribution: .rideBegan
        )
    }

    @Test("today boundary stays half-open across spring DST")
    func springDSTDayBoundary() throws {
        let timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let calendar = calendar(timeZone)
        let reference = calendar.date(
            from: DateComponents(year: 2026, month: 3, day: 8, hour: 12)
        )!
        let interval = calendar.dateInterval(of: .day, for: reference)!

        #expect(interval.duration == 23 * 3_600)

        let atStart = try statisticsRide(at: interval.start)
        let beforeEnd = try statisticsRide(
            at: interval.end.addingTimeInterval(-0.001)
        )
        let atEnd = try statisticsRide(at: interval.end)
        let summary = try RideDurationStatisticsAggregator.summarize(
            period: .today,
            rides: [atStart, beforeEnd, atEnd],
            referenceDate: reference,
            calendar: calendar
        )

        #expect(summary.rideCount == 2)
        #expect(summary.totalObservedDurationNanoseconds == 2)
    }

    @Test("week month and year use caller calendar intervals")
    func largerCalendarBuckets() throws {
        let timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let calendar = calendar(timeZone)
        let reference = calendar.date(
            from: DateComponents(year: 2026, month: 8, day: 7, hour: 12)
        )!

        for period in [RideStatisticsPeriod.week, .month, .year] {
            let component: Calendar.Component
            switch period {
            case .week:
                component = .weekOfYear
            case .month:
                component = .month
            case .year:
                component = .year
            default:
                fatalError("Unexpected test period")
            }

            let interval = calendar.dateInterval(of: component, for: reference)!
            let rides = [
                try statisticsRide(at: interval.start),
                try statisticsRide(at: interval.end.addingTimeInterval(-0.001)),
                try statisticsRide(at: interval.end)
            ]
            let summary = try RideDurationStatisticsAggregator.summarize(
                period: period,
                rides: rides,
                referenceDate: reference,
                calendar: calendar
            )

            #expect(summary.rideCount == 2)
            #expect(summary.totalObservedDurationNanoseconds == 2)
        }
    }
}
