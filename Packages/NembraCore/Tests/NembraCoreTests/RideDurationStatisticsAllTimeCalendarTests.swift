import Foundation
import Testing
@testable import NembraCore

@Suite("Ride duration all-time calendar independence")
struct RideDurationStatisticsAllTimeCalendarTests {
    private func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    private func statisticsRide(
        at attributedDate: Date,
        durationNanoseconds: UInt64 = 123
    ) throws -> RideDurationStatisticsRide {
        let completedRide = try CompletedRideEvidence(
            sessionID: UUID(),
            beganAtDate: attributedDate,
            confirmedAtDate: attributedDate,
            endedAtDate: attributedDate,
            startingOdometerKilometers: nil,
            endingOdometerKilometers: nil,
            qualityScreenedGPSDistanceMeters: 0,
            continuity: .uninterruptedProcess
        )
        let durationEvidence = try CompletedRideDurationEvidence(
            completedRide: completedRide,
            duration: RideSessionDurationEvidenceSnapshot(
                sessionID: completedRide.sessionID,
                observedDurationNanoseconds: durationNanoseconds,
                coverage: .complete,
                observationSegmentCount: 1
            )
        )
        return try RideDurationStatisticsRide(
            completedRide: completedRide,
            durationEvidence: durationEvidence,
            calendarAttribution: .rideBegan
        )
    }

    @Test("all time does not discard monotonic duration because wall clock is outside Calendar range")
    func allTimeIgnoresCalendarRepresentability() throws {
        let calendar = calendar()
        let extremeFiniteDate = Date(
            timeIntervalSinceReferenceDate: Double.greatestFiniteMagnitude
        )
        let dayInterval = calendar.dateInterval(of: .day, for: extremeFiniteDate)

        #expect(extremeFiniteDate.timeIntervalSinceReferenceDate.isFinite)
        #expect(dayInterval?.contains(extremeFiniteDate) != true)

        let summary = try RideDurationStatisticsAggregator.summarize(
            period: .allTime,
            rides: [try statisticsRide(at: extremeFiniteDate)],
            referenceDate: extremeFiniteDate,
            calendar: calendar
        )

        #expect(summary.rideCount == 1)
        #expect(summary.completeCoverageRideCount == 1)
        #expect(summary.durationAvailability == .complete)
        #expect(summary.totalObservedDurationNanoseconds == 123)
    }

    @Test("bounded periods still fail closed for calendar-unrepresentable ride dates")
    func boundedPeriodStillRequiresRepresentableRideDate() throws {
        let calendar = calendar()
        let extremeFiniteDate = Date(
            timeIntervalSinceReferenceDate: Double.greatestFiniteMagnitude
        )
        let referenceDate = calendar.date(
            from: DateComponents(year: 2026, month: 8, day: 7, hour: 12)
        )!
        let ride = try statisticsRide(at: extremeFiniteDate)

        #expect(throws: RideDurationStatisticsError.invalidRide) {
            _ = try RideDurationStatisticsAggregator.summarize(
                period: .today,
                rides: [ride],
                referenceDate: referenceDate,
                calendar: calendar
            )
        }
    }
}
