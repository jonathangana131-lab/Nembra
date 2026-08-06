import Foundation
import Testing
@testable import NembraCore

@Suite("Ride statistics distance availability")
struct RideStatisticsDistanceAvailabilityTests {
    private func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func ride(
        id: UUID = UUID(),
        date: Date,
        distance: Double?,
        disposition: RideStatisticsDistanceDisposition
    ) throws -> RideStatisticsRide {
        try RideStatisticsRide(
            sessionID: id,
            attributedDate: date,
            distanceMeters: distance,
            distanceDisposition: disposition
        )
    }

    @Test("empty period has no rides rather than a fabricated complete zero")
    func noRides() throws {
        let calendar = calendar()
        let reference = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let summary = try RideStatisticsAggregator.summarize(
            period: .today,
            rides: [],
            referenceDate: reference,
            calendar: calendar
        )
        #expect(summary.distanceAvailability == .noRides)
        #expect(summary.totalDistanceMeters == nil)
    }

    @Test("rides with no trustworthy distance are unavailable")
    func unavailable() throws {
        let calendar = calendar()
        let reference = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let rides = [
            try ride(
                date: reference,
                distance: nil,
                disposition: .excludedInsufficientEvidence
            ),
            try ride(
                date: reference,
                distance: 1_200,
                disposition: .excludedIncompleteCoverage
            )
        ]
        let summary = try RideStatisticsAggregator.summarize(
            period: .today,
            rides: rides,
            referenceDate: reference,
            calendar: calendar
        )
        #expect(summary.distanceAvailability == .unavailable)
        #expect(summary.totalDistanceMeters == nil)
    }

    @Test("mixed trustworthy and excluded rides produce a known subtotal")
    func partial() throws {
        let calendar = calendar()
        let reference = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let rides = [
            try ride(
                date: reference,
                distance: 1_500,
                disposition: .included
            ),
            try ride(
                date: reference,
                distance: 9_000,
                disposition: .excludedConflict
            )
        ]
        let summary = try RideStatisticsAggregator.summarize(
            period: .today,
            rides: rides,
            referenceDate: reference,
            calendar: calendar
        )
        #expect(summary.distanceAvailability == .partial)
        #expect(summary.totalDistanceMeters == 1_500)
    }

    @Test("every ride contributing trustworthy distance is complete for the supplied collection")
    func complete() throws {
        let calendar = calendar()
        let reference = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let rides = [
            try ride(
                date: reference,
                distance: 0,
                disposition: .included
            ),
            try ride(
                date: reference,
                distance: 2_500,
                disposition: .included
            )
        ]
        let summary = try RideStatisticsAggregator.summarize(
            period: .today,
            rides: rides,
            referenceDate: reference,
            calendar: calendar
        )
        #expect(summary.distanceAvailability == .complete)
        #expect(summary.totalDistanceMeters == 2_500)
    }
}
