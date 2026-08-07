import Foundation
import Testing
@testable import NembraCore

@Suite("Ride duration statistics")
struct RideDurationStatisticsTests {
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

    private func completedRide(
        id: UUID = UUID(),
        beganAtDate: Date,
        endedAtDate: Date? = nil,
        continuity: RideSessionContinuity = .uninterruptedProcess
    ) throws -> CompletedRideEvidence {
        try CompletedRideEvidence(
            sessionID: id,
            beganAtDate: beganAtDate,
            confirmedAtDate: beganAtDate.addingTimeInterval(5),
            endedAtDate: endedAtDate ?? beganAtDate.addingTimeInterval(600),
            startingOdometerKilometers: nil,
            endingOdometerKilometers: nil,
            qualityScreenedGPSDistanceMeters: 0,
            continuity: continuity
        )
    }

    private func durationEvidence(
        for ride: CompletedRideEvidence,
        nanoseconds: UInt64?,
        coverage: RideSessionDurationCoverage
    ) throws -> CompletedRideDurationEvidence {
        try CompletedRideDurationEvidence(
            completedRide: ride,
            duration: RideSessionDurationEvidenceSnapshot(
                sessionID: ride.sessionID,
                observedDurationNanoseconds: nanoseconds,
                coverage: coverage,
                observationSegmentCount: nanoseconds == nil ? 0 : 1
            )
        )
    }

    private func statisticsRide(
        _ ride: CompletedRideEvidence,
        nanoseconds: UInt64?,
        coverage: RideSessionDurationCoverage,
        attribution: RideStatisticsCalendarAttribution = .rideBegan
    ) throws -> RideDurationStatisticsRide {
        try RideDurationStatisticsRide(
            completedRide: ride,
            durationEvidence: durationEvidence(for: ride, nanoseconds: nanoseconds, coverage: coverage),
            calendarAttribution: attribution
        )
    }

    @Test("wall-clock reversal never becomes elapsed-time evidence")
    func wallClockReversalDoesNotCreateDuration() throws {
        let began = date(2026, 8, 7, 10)
        let ended = date(2026, 8, 7, 9)
        let ride = try completedRide(beganAtDate: began, endedAtDate: ended)
        let statsRide = try statisticsRide(
            ride,
            nanoseconds: 600_000_000_000,
            coverage: .complete
        )

        #expect(statsRide.observedDurationNanoseconds == 600_000_000_000)
        #expect(statsRide.attributedDate == began)
    }

    @Test("calendar attribution is explicit for rides crossing midnight")
    func calendarAttributionIsExplicit() throws {
        let began = date(2026, 8, 6, 23)
        let ended = date(2026, 8, 7, 1)
        let ride = try completedRide(beganAtDate: began, endedAtDate: ended)
        let byBeginning = try statisticsRide(
            ride,
            nanoseconds: 300,
            coverage: .complete,
            attribution: .rideBegan
        )
        let byEnding = try statisticsRide(
            ride,
            nanoseconds: 300,
            coverage: .complete,
            attribution: .rideEnded
        )
        let reference = date(2026, 8, 7)

        let beginningToday = try RideDurationStatisticsAggregator.summarize(
            period: .today,
            rides: [byBeginning],
            referenceDate: reference,
            calendar: calendar()
        )
        let endingToday = try RideDurationStatisticsAggregator.summarize(
            period: .today,
            rides: [byEnding],
            referenceDate: reference,
            calendar: calendar()
        )

        #expect(beginningToday.rideCount == 0)
        #expect(endingToday.rideCount == 1)
        #expect(endingToday.totalObservedDurationNanoseconds == 300)
    }

    @Test("completed duration identity mismatch fails closed")
    func sessionMismatchFailsClosed() throws {
        let rideA = try completedRide(beganAtDate: date(2026, 8, 7, 9))
        let rideB = try completedRide(beganAtDate: date(2026, 8, 7, 10))
        let durationA = try durationEvidence(for: rideA, nanoseconds: 10, coverage: .complete)

        #expect(throws: RideDurationStatisticsError.sessionMismatch) {
            _ = try RideDurationStatisticsRide(
                completedRide: rideB,
                durationEvidence: durationA,
                calendarAttribution: .rideBegan
            )
        }
    }

    @Test("completed duration continuity mismatch fails closed")
    func continuityMismatchFailsClosed() throws {
        let id = UUID()
        let original = try completedRide(id: id, beganAtDate: date(2026, 8, 7, 9))
        let mismatched = try completedRide(
            id: id,
            beganAtDate: date(2026, 8, 7, 9),
            continuity: .recoveredCheckpoint
        )
        let duration = try durationEvidence(for: original, nanoseconds: 10, coverage: .complete)

        #expect(throws: RideDurationStatisticsError.continuityMismatch) {
            _ = try RideDurationStatisticsRide(
                completedRide: mismatched,
                durationEvidence: duration,
                calendarAttribution: .rideBegan
            )
        }
    }

    @Test("mixed complete partial and unavailable rides expose a partial subtotal")
    func mixedCoverageProducesPartialSubtotal() throws {
        let reference = date(2026, 8, 7)
        let complete = try completedRide(beganAtDate: date(2026, 8, 7, 9))
        let partial = try completedRide(
            beganAtDate: date(2026, 8, 7, 10),
            continuity: .recoveredCheckpoint
        )
        let unknown = try completedRide(
            beganAtDate: date(2026, 8, 7, 11),
            continuity: .recoveredCheckpoint
        )
        let rides = [
            try statisticsRide(complete, nanoseconds: 100, coverage: .complete),
            try statisticsRide(partial, nanoseconds: 40, coverage: .partial),
            try statisticsRide(unknown, nanoseconds: nil, coverage: .unknown)
        ]

        let summary = try RideDurationStatisticsAggregator.summarize(
            period: .today,
            rides: rides,
            referenceDate: reference,
            calendar: calendar()
        )

        #expect(summary.rideCount == 3)
        #expect(summary.completeCoverageRideCount == 1)
        #expect(summary.partialCoverageRideCount == 1)
        #expect(summary.unavailableDurationRideCount == 1)
        #expect(summary.observedDurationRideCount == 2)
        #expect(summary.durationAvailability == .partial)
        #expect(summary.totalObservedDurationNanoseconds == 140)
    }

    @Test("all unavailable duration remains nil instead of fake zero")
    func unavailableDurationStaysNil() throws {
        let reference = date(2026, 8, 7)
        let ride = try completedRide(
            beganAtDate: reference,
            continuity: .recoveredCheckpoint
        )
        let summary = try RideDurationStatisticsAggregator.summarize(
            period: .today,
            rides: [try statisticsRide(ride, nanoseconds: nil, coverage: .unknown)],
            referenceDate: reference,
            calendar: calendar()
        )

        #expect(summary.durationAvailability == .unavailable)
        #expect(summary.totalObservedDurationNanoseconds == nil)
        #expect(summary.observedDurationRideCount == 0)
    }

    @Test("observed zero duration remains a real zero")
    func observedZeroRemainsZero() throws {
        let reference = date(2026, 8, 7)
        let ride = try completedRide(beganAtDate: reference)
        let summary = try RideDurationStatisticsAggregator.summarize(
            period: .today,
            rides: [try statisticsRide(ride, nanoseconds: 0, coverage: .complete)],
            referenceDate: reference,
            calendar: calendar()
        )

        #expect(summary.durationAvailability == .complete)
        #expect(summary.totalObservedDurationNanoseconds == 0)
        #expect(summary.completeCoverageRideCount == 1)
    }

    @Test("all complete rides produce complete availability")
    func allCompleteProducesCompleteAvailability() throws {
        let reference = date(2026, 8, 7)
        let first = try completedRide(beganAtDate: date(2026, 8, 7, 9))
        let second = try completedRide(beganAtDate: date(2026, 8, 7, 10))
        let summary = try RideDurationStatisticsAggregator.summarize(
            period: .today,
            rides: [
                try statisticsRide(first, nanoseconds: 20, coverage: .complete),
                try statisticsRide(second, nanoseconds: 30, coverage: .complete)
            ],
            referenceDate: reference,
            calendar: calendar()
        )

        #expect(summary.durationAvailability == .complete)
        #expect(summary.totalObservedDurationNanoseconds == 50)
    }

    @Test("equivalent duplicate sessions are idempotent")
    func equivalentDuplicatesAreIdempotent() throws {
        let reference = date(2026, 8, 7)
        let completed = try completedRide(beganAtDate: reference)
        let ride = try statisticsRide(completed, nanoseconds: 25, coverage: .complete)
        let summary = try RideDurationStatisticsAggregator.summarize(
            period: .allTime,
            rides: [ride, ride],
            referenceDate: reference,
            calendar: calendar()
        )

        #expect(summary.rideCount == 1)
        #expect(summary.totalObservedDurationNanoseconds == 25)
    }

    @Test("conflicting duplicate sessions fail closed")
    func conflictingDuplicatesFailClosed() throws {
        let id = UUID()
        let firstCompleted = try completedRide(id: id, beganAtDate: date(2026, 8, 7, 9))
        let secondCompleted = try completedRide(id: id, beganAtDate: date(2026, 8, 7, 10))
        let first = try statisticsRide(firstCompleted, nanoseconds: 25, coverage: .complete)
        let second = try statisticsRide(secondCompleted, nanoseconds: 25, coverage: .complete)

        #expect(throws: RideDurationStatisticsError.sessionConflict(id)) {
            _ = try RideDurationStatisticsAggregator.summarize(
                period: .allTime,
                rides: [first, second],
                referenceDate: date(2026, 8, 7),
                calendar: calendar()
            )
        }
    }

    @Test("duration aggregation overflow fails closed")
    func aggregateOverflowFailsClosed() throws {
        let firstCompleted = try completedRide(beganAtDate: date(2026, 8, 7, 9))
        let secondCompleted = try completedRide(beganAtDate: date(2026, 8, 7, 10))
        let rides = [
            try statisticsRide(firstCompleted, nanoseconds: UInt64.max, coverage: .complete),
            try statisticsRide(secondCompleted, nanoseconds: 1, coverage: .complete)
        ]

        #expect(throws: RideDurationStatisticsError.aggregateOverflow) {
            _ = try RideDurationStatisticsAggregator.summarize(
                period: .allTime,
                rides: rides,
                referenceDate: date(2026, 8, 7),
                calendar: calendar()
            )
        }
    }

    @Test("empty selected period reports no rides")
    func emptyPeriodReportsNoRides() throws {
        let completed = try completedRide(beganAtDate: date(2026, 8, 6, 9))
        let summary = try RideDurationStatisticsAggregator.summarize(
            period: .today,
            rides: [try statisticsRide(completed, nanoseconds: 10, coverage: .complete)],
            referenceDate: date(2026, 8, 7),
            calendar: calendar()
        )

        #expect(summary.rideCount == 0)
        #expect(summary.durationAvailability == .noRides)
        #expect(summary.totalObservedDurationNanoseconds == nil)
    }
}
