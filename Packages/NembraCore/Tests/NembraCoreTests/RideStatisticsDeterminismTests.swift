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
        distanceMeters: Double
    ) throws -> RideStatisticsRide {
        try RideStatisticsRide(
            sessionID: id,
            attributedDate: date,
            distanceMeters: distanceMeters,
            distanceDisposition: .included
        )
    }

    @Test("equal longest distances are independent of history fetch order")
    func equalLongestDistancesAreOrderIndependent() throws {
        let calendar = calendar()
        let referenceDate = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let earlierDate = referenceDate.addingTimeInterval(-120)
        let laterDate = referenceDate.addingTimeInterval(-60)

        let expectedID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let sameTimeHigherID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let laterLowerID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

        let expected = try ride(
            id: expectedID,
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
            [later, sameTime, expected],
            [expected, later, sameTime],
            [sameTime, expected, later]
        ]

        for rides in inputOrders {
            let summary = try RideStatisticsAggregator.summarize(
                period: .allTime,
                rides: rides,
                referenceDate: referenceDate,
                calendar: calendar
            )

            #expect(summary.longestRideDistanceMeters == 2_000)
            #expect(summary.longestRideSessionID == expectedID)
            #expect(summary.totalDistanceMeters == 6_000)
        }
    }

    @Test("greater distance still outranks deterministic tie fields")
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
}
