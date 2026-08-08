import Foundation
import Testing

@testable import NembraCore

@Suite("Ride statistics composite presentation")
struct RideStatisticsCompositePresentationTests {
    private let sessionA = UUID(uuidString: "D0000000-0000-0000-0000-000000000001")!
    private let sessionB = UUID(uuidString: "D0000000-0000-0000-0000-000000000002")!
    private let sessionC = UUID(uuidString: "D0000000-0000-0000-0000-000000000003")!

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func completedRide(
        sessionID: UUID,
        beganAtDate: Date,
        endedAtDate: Date? = nil,
        continuity: RideSessionContinuity = .uninterruptedProcess
    ) throws -> CompletedRideEvidence {
        try CompletedRideEvidence(
            sessionID: sessionID,
            beganAtDate: beganAtDate,
            confirmedAtDate: beganAtDate.addingTimeInterval(2),
            endedAtDate: endedAtDate ?? beganAtDate.addingTimeInterval(120),
            startingOdometerKilometers: nil,
            endingOdometerKilometers: nil,
            qualityScreenedGPSDistanceMeters: 0,
            continuity: continuity
        )
    }

    private func distanceRide(
        _ ride: CompletedRideEvidence,
        meters: Double?,
        disposition: RideStatisticsDistanceDisposition,
        attribution: RideStatisticsCalendarAttribution = .rideBegan
    ) throws -> RideStatisticsRide {
        let attributedDate: Date
        switch attribution {
        case .rideBegan:
            attributedDate = ride.beganAtDate
        case .rideEnded:
            attributedDate = ride.endedAtDate
        }

        return try RideStatisticsRide(
            sessionID: ride.sessionID,
            attributedDate: attributedDate,
            distanceMeters: meters,
            distanceDisposition: disposition
        )
    }

    private func durationRide(
        _ ride: CompletedRideEvidence,
        nanoseconds: UInt64?,
        coverage: RideSessionDurationCoverage,
        attribution: RideStatisticsCalendarAttribution = .rideBegan
    ) throws -> RideDurationStatisticsRide {
        let snapshot = RideSessionDurationEvidenceSnapshot(
            sessionID: ride.sessionID,
            observedDurationNanoseconds: nanoseconds,
            coverage: coverage,
            observationSegmentCount: nanoseconds == nil ? 0 : 1
        )
        let evidence = try CompletedRideDurationEvidence(
            completedRide: ride,
            duration: snapshot
        )
        return try RideDurationStatisticsRide(
            completedRide: ride,
            durationEvidence: evidence,
            calendarAttribution: attribution
        )
    }

    private func peakEvidence(
        for ride: CompletedRideEvidence,
        watts: Double,
        beginsAfterKnownObservationGap: Bool = false
    ) throws -> CompletedRidePeakPowerEvidence {
        let scope = try ObservedPowerEnvelopeScope.simulatorQA(
            vehicleIdentityKey: "sim-es80",
            confirmedModeKey: "drive"
        )
        var accumulator = try RidePeakPowerEvidenceAccumulator(
            sessionID: ride.sessionID,
            scope: scope,
            beginsAfterKnownObservationGap: beginsAfterKnownObservationGap
        )
        let result = accumulator.record(.simulatorQA(
            scope: scope,
            powerWatts: watts,
            receiptSequenceNumber: 1,
            observedAtUptimeNanoseconds: 100,
            learningEligibility: .measurementOnly
        ))
        guard case .peakUpdated = result,
              let accepted = accumulator.evidence else {
            Issue.record("Expected simulator observation to establish accepted peak evidence")
            throw RidePowerStatisticsError.invalidRide
        }
        return try CompletedRidePeakPowerEvidence(
            completedRide: ride,
            ridePeak: accepted
        )
    }

    private func powerRide(
        _ ride: CompletedRideEvidence,
        watts: Double?,
        attribution: RideStatisticsCalendarAttribution = .rideBegan,
        beginsAfterKnownObservationGap: Bool = false
    ) throws -> RidePowerStatisticsRide {
        let peak = try watts.map {
            try peakEvidence(
                for: ride,
                watts: $0,
                beginsAfterKnownObservationGap: beginsAfterKnownObservationGap
            )
        }
        return try RidePowerStatisticsRide(
            completedRide: ride,
            peakPowerEvidence: peak,
            calendarAttribution: attribution
        )
    }

    @Test("matching selected rides compose without weakening complete metric truth")
    func matchingScopeComposes() throws {
        let reference = date(2026, 8, 7)
        let ride = try completedRide(sessionID: sessionA, beganAtDate: reference)

        let presentation = try RideStatisticsCompositePresenter.present(
            period: .today,
            distanceRides: [try distanceRide(ride, meters: 1_250, disposition: .included)],
            durationRides: [try durationRide(ride, nanoseconds: 90_000_000_000, coverage: .complete)],
            powerRides: [try powerRide(ride, watts: 540)],
            referenceDate: reference,
            calendar: calendar
        )

        #expect(presentation.period == .today)
        #expect(presentation.rideCount == 1)
        #expect(presentation.distance.state == .completeTrustworthyDistance)
        #expect(presentation.distance.knownDistanceSubtotalMeters == 1_250)
        #expect(presentation.observedDuration.state == .completeObservedDuration)
        #expect(presentation.observedDuration.totalObservedDurationNanoseconds == 90_000_000_000)
        #expect(presentation.observedPower.state == .completeAcceptedEvidence)
        #expect(presentation.observedPower.highestAcceptedObservedPowerWatts == 540)
    }

    @Test("equal period and count cannot compose different selected sessions")
    func equalCountsWithDifferentSessionsFailClosed() throws {
        let reference = date(2026, 8, 7)
        let rideA = try completedRide(sessionID: sessionA, beganAtDate: reference)
        let rideB = try completedRide(sessionID: sessionB, beganAtDate: reference.addingTimeInterval(60))

        #expect(throws: RideStatisticsCompositePresentationError.selectedRideScopeMismatch) {
            _ = try RideStatisticsCompositePresenter.present(
                period: .today,
                distanceRides: [try distanceRide(rideA, meters: 1_000, disposition: .included)],
                durationRides: [try durationRide(rideB, nanoseconds: 10, coverage: .complete)],
                powerRides: [try powerRide(rideA, watts: 500)],
                referenceDate: reference,
                calendar: calendar
            )
        }
    }

    @Test("same session cannot silently mix begin-date and end-date attribution")
    func attributionMismatchFailsClosedEvenAllTime() throws {
        let began = date(2026, 8, 6, 23)
        let ended = date(2026, 8, 7, 1)
        let ride = try completedRide(
            sessionID: sessionA,
            beganAtDate: began,
            endedAtDate: ended
        )

        #expect(throws: RideStatisticsCompositePresentationError.selectedRideScopeMismatch) {
            _ = try RideStatisticsCompositePresenter.present(
                period: .allTime,
                distanceRides: [try distanceRide(ride, meters: 900, disposition: .included, attribution: .rideBegan)],
                durationRides: [try durationRide(ride, nanoseconds: 10, coverage: .complete, attribution: .rideEnded)],
                powerRides: [try powerRide(ride, watts: 480, attribution: .rideBegan)],
                referenceDate: ended,
                calendar: calendar
            )
        }
    }

    @Test("unrelated out-of-period populations do not poison a bounded matching snapshot")
    func boundedPeriodIgnoresUnrelatedHistory() throws {
        let reference = date(2026, 8, 7)
        let selected = try completedRide(sessionID: sessionA, beganAtDate: reference)
        let oldDistanceOnly = try completedRide(sessionID: sessionB, beganAtDate: date(2026, 7, 1))
        let oldDurationOnly = try completedRide(sessionID: sessionC, beganAtDate: date(2026, 6, 1))

        let presentation = try RideStatisticsCompositePresenter.present(
            period: .today,
            distanceRides: [
                try distanceRide(selected, meters: 1_500, disposition: .included),
                try distanceRide(oldDistanceOnly, meters: 8_000, disposition: .included)
            ],
            durationRides: [
                try durationRide(selected, nanoseconds: 20, coverage: .complete),
                try durationRide(oldDurationOnly, nanoseconds: 30, coverage: .complete)
            ],
            powerRides: [try powerRide(selected, watts: 510)],
            referenceDate: reference,
            calendar: calendar
        )

        #expect(presentation.rideCount == 1)
        #expect(presentation.distance.knownDistanceSubtotalMeters == 1_500)
        #expect(presentation.observedDuration.totalObservedDurationNanoseconds == 20)
        #expect(presentation.observedPower.highestAcceptedObservedPowerWatts == 510)
    }

    @Test("partial evidence remains independently partial after safe composition")
    func partialEvidenceDoesNotCrossUpgrade() throws {
        let reference = date(2026, 8, 7)
        let rideA = try completedRide(sessionID: sessionA, beganAtDate: reference)
        let rideB = try completedRide(
            sessionID: sessionB,
            beganAtDate: reference.addingTimeInterval(60),
            continuity: .recoveredCheckpoint
        )

        let presentation = try RideStatisticsCompositePresenter.present(
            period: .today,
            distanceRides: [
                try distanceRide(rideA, meters: 1_000, disposition: .included),
                try distanceRide(rideB, meters: nil, disposition: .excludedInsufficientEvidence)
            ],
            durationRides: [
                try durationRide(rideA, nanoseconds: 40, coverage: .complete),
                try durationRide(rideB, nanoseconds: nil, coverage: .unknown)
            ],
            powerRides: [
                try powerRide(rideA, watts: 500),
                try powerRide(rideB, watts: nil)
            ],
            referenceDate: reference,
            calendar: calendar
        )

        #expect(presentation.rideCount == 2)
        #expect(presentation.distance.state == .partialTrustworthyDistance)
        #expect(presentation.distance.requiresKnownDistanceSubtotalDisclosure)
        #expect(presentation.observedDuration.state == .partialObservedDuration)
        #expect(presentation.observedDuration.requiresIncompleteDurationDisclosure)
        #expect(presentation.observedPower.state == .partialAcceptedEvidence)
        #expect(presentation.observedPower.requiresIncompleteEvidenceDisclosure)
    }

    @Test("empty populations compose as one explicit no-rides snapshot")
    func emptyScopeComposes() throws {
        let reference = date(2026, 8, 7)
        let presentation = try RideStatisticsCompositePresenter.present(
            period: .month,
            distanceRides: [],
            durationRides: [],
            powerRides: [],
            referenceDate: reference,
            calendar: calendar
        )

        #expect(presentation.rideCount == 0)
        #expect(presentation.distance.state == .noCompletedRides)
        #expect(presentation.observedDuration.state == .noCompletedRides)
        #expect(presentation.observedPower.state == .noCompletedRides)
    }
}
