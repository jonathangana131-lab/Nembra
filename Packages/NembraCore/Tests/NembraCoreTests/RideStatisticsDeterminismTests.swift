import Foundation
import Testing
@testable import NembraCore

@Suite("Ride statistics determinism")
struct RideStatisticsDeterminismTests {
    private func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    private func ride(
        id: UUID,
        date: Date,
        distanceMeters: Double,
        disposition: RideStatisticsDistanceDisposition = .included
    ) throws -> RideStatisticsRide {
        try RideStatisticsRide(
            sessionID: id,
            attributedDate: date,
            distanceMeters: distanceMeters,
            distanceDisposition: disposition
        )
    }

    @Test("equal longest distances are independent of history order and date preference")
    func equalLongestDistancesAreOrderIndependent() throws {
        let calendar = calendar()
        let referenceDate = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let earlierDate = referenceDate.addingTimeInterval(-120)
        let laterDate = referenceDate.addingTimeInterval(-60)

        let earlierID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let sameTimeHigherID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let laterLowerID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

        let earlier = try ride(
            id: earlierID,
            date: earlierDate,
            distanceMeters: 2_000
        )
        let sameTime = try ride(
            id: sameTimeHigherID,
            date: earlierDate,
            distanceMeters: 2_000
        )
        let later = try ride(
            id: laterLowerID,
            date: laterDate,
            distanceMeters: 2_000
        )

        let inputOrders = [
            [later, sameTime, earlier],
            [earlier, later, sameTime],
            [sameTime, earlier, later]
        ]

        for rides in inputOrders {
            let summary = try RideStatisticsAggregator.summarize(
                period: .allTime,
                rides: rides,
                referenceDate: referenceDate,
                calendar: calendar
            )

            #expect(summary.longestRideDistanceMeters == 2_000)
            #expect(summary.longestRideSessionID == laterLowerID)
            #expect(summary.totalDistanceMeters == 6_000)
        }
    }

    @Test("greater distance still outranks deterministic identity tie break")
    func greaterDistanceStillWins() throws {
        let calendar = calendar()
        let referenceDate = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let earlierID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        let fartherID = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!

        let earlierShorter = try ride(
            id: earlierID,
            date: referenceDate.addingTimeInterval(-600),
            distanceMeters: 1_999
        )
        let laterFarther = try ride(
            id: fartherID,
            date: referenceDate.addingTimeInterval(-60),
            distanceMeters: 2_000
        )

        let summary = try RideStatisticsAggregator.summarize(
            period: .allTime,
            rides: [earlierShorter, laterFarther],
            referenceDate: referenceDate,
            calendar: calendar
        )

        #expect(summary.longestRideDistanceMeters == 2_000)
        #expect(summary.longestRideSessionID == fartherID)
    }

    @Test("floating point totals are independent of history fetch order")
    func floatingPointTotalsAreOrderIndependent() throws {
        let calendar = calendar()
        let referenceDate = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let first = try ride(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            date: referenceDate.addingTimeInterval(-180),
            distanceMeters: 1
        )
        let second = try ride(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            date: referenceDate.addingTimeInterval(-120),
            distanceMeters: 1
        )
        let huge = try ride(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            date: referenceDate.addingTimeInterval(-60),
            distanceMeters: 9_007_199_254_740_992
        )

        let chronological = try RideStatisticsAggregator.summarize(
            period: .allTime,
            rides: [first, second, huge],
            referenceDate: referenceDate,
            calendar: calendar
        )
        let reversed = try RideStatisticsAggregator.summarize(
            period: .allTime,
            rides: [huge, second, first],
            referenceDate: referenceDate,
            calendar: calendar
        )

        #expect(chronological == reversed)
        #expect(chronological.totalDistanceMeters == 9_007_199_254_740_994)
    }

    @Test("compensated totals preserve small trustworthy rides after a huge earlier ride")
    func compensatedTotalPreservesSmallDistances() throws {
        let calendar = calendar()
        let referenceDate = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let huge = try ride(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            date: referenceDate.addingTimeInterval(-180),
            distanceMeters: 9_007_199_254_740_992
        )
        let firstSmall = try ride(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            date: referenceDate.addingTimeInterval(-120),
            distanceMeters: 1
        )
        let secondSmall = try ride(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            date: referenceDate.addingTimeInterval(-60),
            distanceMeters: 1
        )

        let summary = try RideStatisticsAggregator.summarize(
            period: .allTime,
            rides: [huge, firstSmall, secondSmall],
            referenceDate: referenceDate,
            calendar: calendar
        )

        #expect(summary.totalDistanceMeters == 9_007_199_254_740_994)
    }

    @Test("excluded extreme distance never contaminates the compensated subtotal")
    func excludedExtremeDistanceDoesNotContaminateSubtotal() throws {
        let calendar = calendar()
        let referenceDate = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let trustworthy = try ride(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            date: referenceDate.addingTimeInterval(-120),
            distanceMeters: 1_000
        )
        let excluded = try ride(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            date: referenceDate.addingTimeInterval(-60),
            distanceMeters: Double.greatestFiniteMagnitude,
            disposition: .excludedConflict
        )

        let summary = try RideStatisticsAggregator.summarize(
            period: .allTime,
            rides: [excluded, trustworthy],
            referenceDate: referenceDate,
            calendar: calendar
        )

        #expect(summary.trustworthyDistanceRideCount == 1)
        #expect(summary.excludedDistanceRideCount == 1)
        #expect(summary.distanceAvailability == .partial)
        #expect(summary.totalDistanceMeters == 1_000)
        #expect(summary.longestRideDistanceMeters == 1_000)
        #expect(summary.longestRideSessionID == trustworthy.sessionID)
    }

    @Test("finite reference dates outside the calendar range fail closed")
    func calendarClampedReferenceDateFailsClosed() throws {
        let calendar = calendar()
        let unrepresentable = Date(timeIntervalSinceReferenceDate: 1e20)

        #expect(throws: RideStatisticsError.invalidReferenceDate) {
            _ = try RideStatisticsAggregator.summarize(
                period: .today,
                rides: [],
                referenceDate: unrepresentable,
                calendar: calendar
            )
        }
    }

    @Test("finite ride dates outside the calendar range cannot fabricate an all-time riding day")
    func calendarClampedRideDateFailsClosed() throws {
        let calendar = calendar()
        let referenceDate = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let unrepresentableRide = try ride(
            id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            date: Date(timeIntervalSinceReferenceDate: 1e20),
            distanceMeters: 1_000
        )

        #expect(throws: RideStatisticsError.invalidRide) {
            _ = try RideStatisticsAggregator.summarize(
                period: .allTime,
                rides: [unrepresentableRide],
                referenceDate: referenceDate,
                calendar: calendar
            )
        }
    }

    @Test("day periods exclude their exact next-midnight boundary")
    func dayPeriodsExcludeExactEndBoundary() throws {
        var calendar = calendar()
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let referenceDate = calendar.date(
            from: DateComponents(year: 2026, month: 8, day: 6, hour: 12)
        )!
        let todayInterval = calendar.dateInterval(of: .day, for: referenceDate)!
        let yesterdayReference = calendar.date(byAdding: .day, value: -1, to: referenceDate)!
        let yesterdayInterval = calendar.dateInterval(of: .day, for: yesterdayReference)!

        let todayStart = try ride(
            id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
            date: todayInterval.start,
            distanceMeters: 1_000
        )
        let tomorrowStart = try ride(
            id: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!,
            date: todayInterval.end,
            distanceMeters: 1_000
        )

        let today = try RideStatisticsAggregator.summarize(
            period: .today,
            rides: [todayStart, tomorrowStart],
            referenceDate: referenceDate,
            calendar: calendar
        )
        let yesterday = try RideStatisticsAggregator.summarize(
            period: .yesterday,
            rides: [todayStart],
            referenceDate: referenceDate,
            calendar: calendar
        )

        #expect(yesterdayInterval.end == todayInterval.start)
        #expect(today.rideCount == 1)
        #expect(today.longestRideSessionID == todayStart.sessionID)
        #expect(yesterday.rideCount == 0)
    }

    @Test("representable Pacific dates keep calendar-day streaks across daylight saving time")
    func daylightSavingStreakRemainsCalendarBased() throws {
        var calendar = calendar()
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!

        func date(_ day: Int) -> Date {
            calendar.date(
                from: DateComponents(
                    year: 2026,
                    month: 3,
                    day: day,
                    hour: 12
                )
            )!
        }

        let rides = try [7, 8, 9].enumerated().map { index, day in
            try ride(
                id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))!,
                date: date(day),
                distanceMeters: 1_000
            )
        }

        let summary = try RideStatisticsAggregator.summarize(
            period: .allTime,
            rides: rides,
            referenceDate: date(9),
            calendar: calendar
        )

        #expect(summary.ridingDayCount == 3)
        #expect(summary.longestRidingDayStreakDays == 3)
    }
}
