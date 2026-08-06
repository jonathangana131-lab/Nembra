import Foundation
import Testing
@testable import NembraCore

@Suite("Ride statistics")
struct RideStatisticsTests {
    private func calendar(
        timeZone: TimeZone = TimeZone(secondsFromGMT: 0)!
    ) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int = 12,
        calendar: Calendar? = nil
    ) -> Date {
        let calendar = calendar ?? self.calendar()
        return calendar.date(
            from: DateComponents(
                year: year,
                month: month,
                day: day,
                hour: hour
            )
        )!
    }

    private func ride(
        _ attributedDate: Date,
        id: UUID = UUID(),
        distance: Double? = 1_000,
        disposition: RideStatisticsDistanceDisposition = .included
    ) throws -> RideStatisticsRide {
        try RideStatisticsRide(
            sessionID: id,
            attributedDate: attributedDate,
            distanceMeters: distance,
            distanceDisposition: disposition
        )
    }

    private func completedRide(
        id: UUID = UUID(),
        beganAtDate: Date,
        endedAtDate: Date? = nil
    ) throws -> CompletedRideEvidence {
        let end = endedAtDate ?? beganAtDate.addingTimeInterval(600)
        return try CompletedRideEvidence(
            sessionID: id,
            beganAtDate: beganAtDate,
            confirmedAtDate: beganAtDate.addingTimeInterval(5),
            endedAtDate: end,
            startingOdometerKilometers: nil,
            endingOdometerKilometers: nil,
            qualityScreenedGPSDistanceMeters: 0,
            continuity: .uninterruptedProcess
        )
    }

    private func reconciliation(
        distance: Double?,
        confidence: RideDistanceConfidence,
        status: RideDistanceReconciliationStatus
    ) -> ReconciledRideDistance {
        ReconciledRideDistance(
            finalDistanceMeters: distance,
            finalSource: distance == nil ? nil : .gpsRoute,
            finalSourceCoverage: distance == nil ? nil : .complete,
            confidence: confidence,
            status: status,
            comparisons: [],
            recoveredCoverageGapMeters: 0,
            transportGapOccurred: false
        )
    }

    @Test("invalid ride values are rejected while excluded missing distance is representable")
    func invalidRideValues() throws {
        #expect(throws: RideStatisticsError.invalidRide) {
            _ = try ride(date(2026, 8, 6), distance: nil)
        }
        #expect(throws: RideStatisticsError.invalidRide) {
            _ = try ride(date(2026, 8, 6), distance: -1)
        }
        #expect(throws: RideStatisticsError.invalidRide) {
            _ = try ride(date(2026, 8, 6), distance: .infinity)
        }

        let excluded = try ride(
            date(2026, 8, 6),
            distance: nil,
            disposition: .excludedInsufficientEvidence
        )
        #expect(excluded.distanceMeters == nil)
    }

    @Test("reconciliation bridge includes only trustworthy completed distance")
    func reconciliationBridge() throws {
        let beganAtDate = date(2026, 8, 6, 9)
        let completed = try completedRide(beganAtDate: beganAtDate)

        let complete = try RideStatisticsRide(
            completedRide: completed,
            reconciledDistance: reconciliation(
                distance: 2_400,
                confidence: .singleSource,
                status: .complete
            ),
            calendarAttribution: .rideBegan
        )
        #expect(complete.attributedDate == beganAtDate)
        #expect(complete.distanceMeters == 2_400)
        #expect(complete.distanceDisposition == .included)

        let incomplete = try RideStatisticsRide(
            completedRide: completed,
            reconciledDistance: reconciliation(
                distance: 2_300,
                confidence: .singleSource,
                status: .coverageIncomplete
            ),
            calendarAttribution: .rideBegan
        )
        #expect(incomplete.distanceDisposition == .excludedIncompleteCoverage)

        let conflicting = try RideStatisticsRide(
            completedRide: completed,
            reconciledDistance: reconciliation(
                distance: 2_500,
                confidence: .conflicting,
                status: .disagreementRequiresReview
            ),
            calendarAttribution: .rideBegan
        )
        #expect(conflicting.distanceDisposition == .excludedConflict)

        let unavailable = try RideStatisticsRide(
            completedRide: completed,
            reconciledDistance: reconciliation(
                distance: nil,
                confidence: .unavailable,
                status: .insufficientEvidence
            ),
            calendarAttribution: .rideBegan
        )
        #expect(unavailable.distanceDisposition == .excludedInsufficientEvidence)
    }

    @Test("calendar attribution is explicit for rides crossing midnight")
    func calendarAttributionIsExplicit() throws {
        let calendar = calendar()
        let began = date(2026, 8, 5, 23, calendar: calendar)
        let ended = date(2026, 8, 6, 1, calendar: calendar)
        let completed = try completedRide(
            beganAtDate: began,
            endedAtDate: ended
        )
        let distance = reconciliation(
            distance: 2_000,
            confidence: .singleSource,
            status: .complete
        )

        let byBeginning = try RideStatisticsRide(
            completedRide: completed,
            reconciledDistance: distance,
            calendarAttribution: .rideBegan
        )
        let byEnding = try RideStatisticsRide(
            completedRide: completed,
            reconciledDistance: distance,
            calendarAttribution: .rideEnded
        )

        #expect(byBeginning.attributedDate == began)
        #expect(byEnding.attributedDate == ended)

        let reference = date(2026, 8, 6, 12, calendar: calendar)
        let beginningToday = try RideStatisticsAggregator.summarize(
            period: .today,
            rides: [byBeginning],
            referenceDate: reference,
            calendar: calendar
        )
        let endingToday = try RideStatisticsAggregator.summarize(
            period: .today,
            rides: [byEnding],
            referenceDate: reference,
            calendar: calendar
        )
        #expect(beginningToday.rideCount == 0)
        #expect(endingToday.rideCount == 1)
    }

    @Test("known coverage-gap recovery remains countable without reconstructing geometry")
    func recoveredGapDistanceIsCountable() throws {
        let completed = try completedRide(beganAtDate: date(2026, 8, 6))
        let ride = try RideStatisticsRide(
            completedRide: completed,
            reconciledDistance: reconciliation(
                distance: 4_600,
                confidence: .recoverySupported,
                status: .vehicleDistanceRecoveredAcrossCoverageGap
            ),
            calendarAttribution: .rideBegan
        )
        #expect(ride.distanceDisposition == .included)
        #expect(ride.distanceMeters == 4_600)
    }

    @Test("period totals count rides but exclude untrustworthy mileage")
    func totalsKeepTruthBoundary() throws {
        let calendar = calendar()
        let reference = date(2026, 8, 6, calendar: calendar)
        let longestID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let rides = [
            try ride(date(2026, 8, 6, 9, calendar: calendar), distance: 1_200),
            try ride(
                date(2026, 8, 6, 10, calendar: calendar),
                id: longestID,
                distance: 2_000
            ),
            try ride(
                date(2026, 8, 6, 11, calendar: calendar),
                distance: 9_000,
                disposition: .excludedConflict
            ),
            try ride(date(2026, 8, 5, 12, calendar: calendar), distance: 3_000)
        ]

        let summary = try RideStatisticsAggregator.summarize(
            period: .today,
            rides: rides,
            referenceDate: reference,
            calendar: calendar
        )

        #expect(summary.rideCount == 3)
        #expect(summary.ridingDayCount == 1)
        #expect(summary.trustworthyDistanceRideCount == 2)
        #expect(summary.excludedDistanceRideCount == 1)
        #expect(summary.totalDistanceMeters == 3_200)
        #expect(summary.longestRideDistanceMeters == 2_000)
        #expect(summary.longestRideSessionID == longestID)
    }

    @Test("no trustworthy mileage remains unavailable instead of becoming fake zero")
    func unavailableDistanceStaysNil() throws {
        let calendar = calendar()
        let reference = date(2026, 8, 6, calendar: calendar)
        let rides = [
            try ride(
                reference,
                distance: 2_000,
                disposition: .excludedIncompleteCoverage
            ),
            try ride(
                reference,
                distance: nil,
                disposition: .excludedInsufficientEvidence
            )
        ]

        let summary = try RideStatisticsAggregator.summarize(
            period: .today,
            rides: rides,
            referenceDate: reference,
            calendar: calendar
        )
        #expect(summary.rideCount == 2)
        #expect(summary.trustworthyDistanceRideCount == 0)
        #expect(summary.excludedDistanceRideCount == 2)
        #expect(summary.totalDistanceMeters == nil)
        #expect(summary.longestRideDistanceMeters == nil)
    }

    @Test("a trustworthy zero-distance ride remains a real zero rather than unavailable")
    func trustworthyZeroRemainsZero() throws {
        let calendar = calendar()
        let reference = date(2026, 8, 6, calendar: calendar)
        let summary = try RideStatisticsAggregator.summarize(
            period: .today,
            rides: [try ride(reference, distance: 0)],
            referenceDate: reference,
            calendar: calendar
        )
        #expect(summary.trustworthyDistanceRideCount == 1)
        #expect(summary.totalDistanceMeters == 0)
        #expect(summary.longestRideDistanceMeters == 0)
    }

    @Test("equivalent duplicate sessions are idempotent")
    func equivalentDuplicateSessionsAreIdempotent() throws {
        let calendar = calendar()
        let reference = date(2026, 8, 6, calendar: calendar)
        let id = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let record = try ride(reference, id: id, distance: 1_500)

        let summary = try RideStatisticsAggregator.summarize(
            period: .today,
            rides: [record, record],
            referenceDate: reference,
            calendar: calendar
        )
        #expect(summary.rideCount == 1)
        #expect(summary.trustworthyDistanceRideCount == 1)
        #expect(summary.totalDistanceMeters == 1_500)
    }

    @Test("conflicting duplicate session evidence fails closed")
    func conflictingDuplicateSessionFails() throws {
        let calendar = calendar()
        let reference = date(2026, 8, 6, calendar: calendar)
        let id = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let first = try ride(reference, id: id, distance: 1_500)
        let conflicting = try ride(reference, id: id, distance: 2_000)

        #expect(throws: RideStatisticsError.sessionConflict(id)) {
            _ = try RideStatisticsAggregator.summarize(
                period: .today,
                rides: [first, conflicting],
                referenceDate: reference,
                calendar: calendar
            )
        }
    }

    @Test("calendar periods use caller-defined week and timezone semantics")
    func periodWindows() throws {
        let calendar = calendar()
        let reference = date(2026, 8, 6, calendar: calendar)
        let rides = try [
            ride(date(2026, 8, 6, calendar: calendar)),
            ride(date(2026, 8, 5, calendar: calendar)),
            ride(date(2026, 8, 3, calendar: calendar)),
            ride(date(2026, 7, 31, calendar: calendar)),
            ride(date(2025, 12, 31, calendar: calendar))
        ]

        let expected: [(RideStatisticsPeriod, Int)] = [
            (.today, 1),
            (.yesterday, 1),
            (.week, 3),
            (.month, 3),
            (.year, 4),
            (.allTime, 5)
        ]

        for pair in expected {
            let summary = try RideStatisticsAggregator.summarize(
                period: pair.0,
                rides: rides,
                referenceDate: reference,
                calendar: calendar
            )
            #expect(summary.rideCount == pair.1)
        }
    }

    @Test("riding days deduplicate multiple rides and streaks require adjacent calendar days")
    func ridingDaysAndStreak() throws {
        let calendar = calendar()
        let reference = date(2026, 8, 6, calendar: calendar)
        let rides = try [
            ride(date(2026, 8, 1, 8, calendar: calendar)),
            ride(date(2026, 8, 1, 18, calendar: calendar)),
            ride(date(2026, 8, 2, calendar: calendar)),
            ride(date(2026, 8, 3, calendar: calendar)),
            ride(date(2026, 8, 5, calendar: calendar)),
            ride(date(2026, 8, 6, calendar: calendar))
        ]

        let summary = try RideStatisticsAggregator.summarize(
            period: .allTime,
            rides: rides,
            referenceDate: reference,
            calendar: calendar
        )
        #expect(summary.rideCount == 6)
        #expect(summary.ridingDayCount == 5)
        #expect(summary.longestRidingDayStreakDays == 3)
    }

    @Test("one instant can be today in UTC and yesterday in Pacific time")
    func timezoneBoundary() throws {
        let utc = calendar()
        let pacific = calendar(timeZone: TimeZone(identifier: "America/Los_Angeles")!)
        let instant = utc.date(
            from: DateComponents(year: 2026, month: 8, day: 6, hour: 6, minute: 30)
        )!
        let reference = utc.date(
            from: DateComponents(year: 2026, month: 8, day: 6, hour: 12)
        )!
        let rides = [try ride(instant)]

        let utcToday = try RideStatisticsAggregator.summarize(
            period: .today,
            rides: rides,
            referenceDate: reference,
            calendar: utc
        )
        let pacificToday = try RideStatisticsAggregator.summarize(
            period: .today,
            rides: rides,
            referenceDate: reference,
            calendar: pacific
        )
        let pacificYesterday = try RideStatisticsAggregator.summarize(
            period: .yesterday,
            rides: rides,
            referenceDate: reference,
            calendar: pacific
        )

        #expect(utcToday.rideCount == 1)
        #expect(pacificToday.rideCount == 0)
        #expect(pacificYesterday.rideCount == 1)
    }

    @Test("overflow fails instead of publishing an infinite aggregate")
    func aggregateOverflow() throws {
        let calendar = calendar()
        let reference = date(2026, 8, 6, calendar: calendar)
        let rides = [
            try ride(reference, distance: Double.greatestFiniteMagnitude),
            try ride(reference, distance: Double.greatestFiniteMagnitude)
        ]

        #expect(throws: RideStatisticsError.aggregateOverflow) {
            _ = try RideStatisticsAggregator.summarize(
                period: .today,
                rides: rides,
                referenceDate: reference,
                calendar: calendar
            )
        }
    }

    @Test("invalid reference date fails before aggregation")
    func invalidReferenceDate() throws {
        let calendar = calendar()
        let invalidDate = Date(timeIntervalSinceReferenceDate: .infinity)
        #expect(throws: RideStatisticsError.invalidReferenceDate) {
            _ = try RideStatisticsAggregator.summarize(
                period: .today,
                rides: [],
                referenceDate: invalidDate,
                calendar: calendar
            )
        }
    }

    @Test("empty periods stay unavailable instead of manufacturing zero-distance evidence")
    func emptyPeriod() throws {
        let calendar = calendar()
        let summary = try RideStatisticsAggregator.summarize(
            period: .today,
            rides: [],
            referenceDate: date(2026, 8, 6, calendar: calendar),
            calendar: calendar
        )
        #expect(summary.rideCount == 0)
        #expect(summary.ridingDayCount == 0)
        #expect(summary.trustworthyDistanceRideCount == 0)
        #expect(summary.excludedDistanceRideCount == 0)
        #expect(summary.totalDistanceMeters == nil)
        #expect(summary.longestRideDistanceMeters == nil)
        #expect(summary.longestRideSessionID == nil)
        #expect(summary.longestRidingDayStreakDays == 0)
    }
}
