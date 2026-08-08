import Foundation
import Testing
@testable import NembraCore

@Suite("Ride average-speed statistics")
struct RideAverageSpeedStatisticsTests {
    private enum DurationFixture {
        case complete(UInt64)
        case partial
        case unavailable
    }

    private func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int = 12
    ) -> Date {
        calendar().date(
            from: DateComponents(year: year, month: month, day: day, hour: hour)
        )!
    }

    private func completedRide(
        id: UUID = UUID(),
        beganAtDate: Date? = nil,
        endedAtDate: Date? = nil,
        continuity: RideSessionContinuity = .uninterruptedProcess
    ) throws -> CompletedRideEvidence {
        let began = beganAtDate ?? date(2026, 8, 7, 10)
        let ended = endedAtDate ?? began.addingTimeInterval(1_000)
        return try CompletedRideEvidence(
            sessionID: id,
            beganAtDate: began,
            confirmedAtDate: began.addingTimeInterval(1),
            endedAtDate: ended,
            startingOdometerKilometers: nil,
            endingOdometerKilometers: nil,
            qualityScreenedGPSDistanceMeters: 0,
            continuity: continuity
        )
    }

    private func distanceRide(
        for completedRide: CompletedRideEvidence,
        distanceMeters: Double? = 1_000,
        disposition: RideStatisticsDistanceDisposition = .included,
        attribution: RideStatisticsCalendarAttribution = .rideBegan,
        sessionID: UUID? = nil
    ) throws -> RideStatisticsRide {
        let attributedDate: Date
        switch attribution {
        case .rideBegan:
            attributedDate = completedRide.beganAtDate
        case .rideEnded:
            attributedDate = completedRide.endedAtDate
        }

        return try RideStatisticsRide(
            sessionID: sessionID ?? completedRide.sessionID,
            attributedDate: attributedDate,
            distanceMeters: distanceMeters,
            distanceDisposition: disposition
        )
    }

    private func durationEvidence(
        for completedRide: CompletedRideEvidence,
        fixture: DurationFixture
    ) throws -> CompletedRideDurationEvidence {
        var accumulator = RideSessionDurationEvidenceAccumulator(
            sessionID: completedRide.sessionID
        )

        switch fixture {
        case let .complete(nanoseconds):
            try accumulator.upsert(
                RideSessionDurationObservedSegment(
                    sessionID: completedRide.sessionID,
                    segmentID: UUID(),
                    processGenerationID: UUID(),
                    sequenceNumber: 0,
                    observedFromUptimeNanoseconds: 0,
                    observedThroughUptimeNanoseconds: nanoseconds,
                    followsUnobservedInterval: false
                )
            )

        case .partial:
            try accumulator.upsert(
                RideSessionDurationObservedSegment(
                    sessionID: completedRide.sessionID,
                    segmentID: UUID(),
                    processGenerationID: UUID(),
                    sequenceNumber: 0,
                    observedFromUptimeNanoseconds: 10,
                    observedThroughUptimeNanoseconds: 110,
                    followsUnobservedInterval: false
                )
            )
            try accumulator.upsert(
                RideSessionDurationObservedSegment(
                    sessionID: completedRide.sessionID,
                    segmentID: UUID(),
                    processGenerationID: UUID(),
                    sequenceNumber: 1,
                    observedFromUptimeNanoseconds: 500,
                    observedThroughUptimeNanoseconds: 900,
                    followsUnobservedInterval: true
                )
            )

        case .unavailable:
            break
        }

        return try CompletedRideDurationEvidence(
            completedRide: completedRide,
            duration: accumulator.snapshot
        )
    }

    private func statisticsRide(
        completedRide: CompletedRideEvidence,
        distanceMeters: Double? = 1_000,
        distanceDisposition: RideStatisticsDistanceDisposition = .included,
        duration: DurationFixture = .complete(100_000_000_000),
        attribution: RideStatisticsCalendarAttribution = .rideBegan
    ) throws -> RideAverageSpeedStatisticsRide {
        try RideAverageSpeedStatisticsRide(
            completedRide: completedRide,
            distanceRide: distanceRide(
                for: completedRide,
                distanceMeters: distanceMeters,
                disposition: distanceDisposition,
                attribution: attribution
            ),
            durationEvidence: durationEvidence(
                for: completedRide,
                fixture: duration
            ),
            calendarAttribution: attribution
        )
    }

    @Test("single complete ride yields elapsed-ride average speed")
    func singleCompleteRide() throws {
        let completed = try completedRide()
        let ride = try statisticsRide(
            completedRide: completed,
            distanceMeters: 2_400,
            duration: .complete(600_000_000_000)
        )

        #expect(ride.eligibility == .included)
        #expect(ride.completeDistanceMeters == 2_400)
        #expect(ride.completeObservedDurationNanoseconds == 600_000_000_000)

        let summary = try RideAverageSpeedStatisticsAggregator.summarize(
            period: .today,
            rides: [ride],
            referenceDate: date(2026, 8, 7, 18),
            calendar: calendar()
        )

        #expect(summary.availability == .complete)
        #expect(summary.rideCount == 1)
        #expect(summary.includedRideCount == 1)
        #expect(summary.excludedRideCount == 0)
        #expect(summary.supportingDistanceMeters == 2_400)
        #expect(summary.supportingObservedDurationNanoseconds == 600_000_000_000)
        #expect(summary.averageElapsedRideSpeedMetersPerSecond == 4)
        #expect(summary.permitsCompletePeriodAverageWording)
        #expect(!summary.requiresIncompleteEvidenceDisclosure)
    }

    @Test("period average is duration-weighted rather than mean of ride averages")
    func weightedPeriodAverage() throws {
        let first = try statisticsRide(
            completedRide: completedRide(id: UUID()),
            distanceMeters: 1_000,
            duration: .complete(100_000_000_000)
        )
        let second = try statisticsRide(
            completedRide: completedRide(id: UUID()),
            distanceMeters: 1_000,
            duration: .complete(900_000_000_000)
        )

        let summary = try RideAverageSpeedStatisticsAggregator.summarize(
            period: .today,
            rides: [first, second],
            referenceDate: date(2026, 8, 7, 18),
            calendar: calendar()
        )

        #expect(summary.includedRideCount == 2)
        #expect(summary.supportingDistanceMeters == 2_000)
        #expect(summary.supportingObservedDurationNanoseconds == 1_000_000_000_000)
        #expect(summary.averageElapsedRideSpeedMetersPerSecond == 2)
    }

    @Test("partial selected-period evidence preserves only a disclosed known-evidence average")
    func partialSelectedPeriod() throws {
        let included = try statisticsRide(
            completedRide: completedRide(id: UUID()),
            distanceMeters: 1_000,
            duration: .complete(100_000_000_000)
        )
        let excluded = try statisticsRide(
            completedRide: completedRide(id: UUID()),
            distanceMeters: nil,
            distanceDisposition: .excludedInsufficientEvidence,
            duration: .complete(100_000_000_000)
        )

        let summary = try RideAverageSpeedStatisticsAggregator.summarize(
            period: .today,
            rides: [included, excluded],
            referenceDate: date(2026, 8, 7, 18),
            calendar: calendar()
        )

        #expect(summary.availability == .partial)
        #expect(summary.includedRideCount == 1)
        #expect(summary.excludedDistanceRideCount == 1)
        #expect(summary.averageElapsedRideSpeedMetersPerSecond == 10)
        #expect(!summary.permitsCompletePeriodAverageWording)
        #expect(summary.requiresIncompleteEvidenceDisclosure)
    }

    @Test("distance, duration, zero-duration, and multiple-evidence exclusions stay explicit")
    func exclusionClassification() throws {
        let distanceExcluded = try statisticsRide(
            completedRide: completedRide(id: UUID()),
            distanceMeters: nil,
            distanceDisposition: .excludedInsufficientEvidence,
            duration: .complete(100)
        )
        let durationExcluded = try statisticsRide(
            completedRide: completedRide(id: UUID()),
            distanceMeters: 10,
            duration: .partial
        )
        let zeroDuration = try statisticsRide(
            completedRide: completedRide(id: UUID()),
            distanceMeters: 0,
            duration: .complete(0)
        )
        let multipleExcluded = try statisticsRide(
            completedRide: completedRide(id: UUID()),
            distanceMeters: nil,
            distanceDisposition: .excludedIncompleteCoverage,
            duration: .unavailable
        )

        #expect(distanceExcluded.eligibility == .excludedDistanceEvidence)
        #expect(durationExcluded.eligibility == .excludedDurationEvidence)
        #expect(zeroDuration.eligibility == .excludedZeroDuration)
        #expect(multipleExcluded.eligibility == .excludedMultipleEvidence)

        let summary = try RideAverageSpeedStatisticsAggregator.summarize(
            period: .today,
            rides: [distanceExcluded, durationExcluded, zeroDuration, multipleExcluded],
            referenceDate: date(2026, 8, 7, 18),
            calendar: calendar()
        )

        #expect(summary.availability == .unavailable)
        #expect(summary.includedRideCount == 0)
        #expect(summary.excludedDistanceRideCount == 1)
        #expect(summary.excludedDurationRideCount == 1)
        #expect(summary.excludedZeroDurationRideCount == 1)
        #expect(summary.excludedMultipleEvidenceRideCount == 1)
        #expect(summary.excludedRideCount == 4)
        #expect(summary.averageElapsedRideSpeedMetersPerSecond == nil)
        #expect(summary.supportingDistanceMeters == nil)
        #expect(summary.supportingObservedDurationNanoseconds == nil)
    }

    @Test("legitimate zero distance over positive elapsed time remains zero speed")
    func legitimateZeroDistance() throws {
        let ride = try statisticsRide(
            completedRide: completedRide(),
            distanceMeters: 0,
            duration: .complete(50_000_000_000)
        )
        let summary = try RideAverageSpeedStatisticsAggregator.summarize(
            period: .today,
            rides: [ride],
            referenceDate: date(2026, 8, 7, 18),
            calendar: calendar()
        )

        #expect(summary.availability == .complete)
        #expect(summary.averageElapsedRideSpeedMetersPerSecond == 0)
    }

    @Test("distance projection must belong to the same immutable ride session")
    func distanceSessionMismatch() throws {
        let completed = try completedRide()
        let wrongDistance = try distanceRide(
            for: completed,
            sessionID: UUID()
        )
        let duration = try durationEvidence(
            for: completed,
            fixture: .complete(100)
        )

        #expect(throws: RideAverageSpeedStatisticsError.sessionMismatch) {
            _ = try RideAverageSpeedStatisticsRide(
                completedRide: completed,
                distanceRide: wrongDistance,
                durationEvidence: duration,
                calendarAttribution: .rideBegan
            )
        }
    }

    @Test("duration evidence must belong to the same immutable ride session")
    func durationSessionMismatch() throws {
        let completed = try completedRide()
        let other = try completedRide(id: UUID())
        let distance = try distanceRide(for: completed)
        let wrongDuration = try durationEvidence(
            for: other,
            fixture: .complete(100)
        )

        #expect(throws: RideAverageSpeedStatisticsError.sessionMismatch) {
            _ = try RideAverageSpeedStatisticsRide(
                completedRide: completed,
                distanceRide: distance,
                durationEvidence: wrongDuration,
                calendarAttribution: .rideBegan
            )
        }
    }

    @Test("duration continuity mismatch fails closed")
    func durationContinuityMismatch() throws {
        let id = UUID()
        let completed = try completedRide(id: id, continuity: .uninterruptedProcess)
        let recovered = try completedRide(id: id, continuity: .recoveredCheckpoint)
        let distance = try distanceRide(for: completed)
        let recoveredDuration = try durationEvidence(
            for: recovered,
            fixture: .partial
        )

        #expect(throws: RideAverageSpeedStatisticsError.continuityMismatch) {
            _ = try RideAverageSpeedStatisticsRide(
                completedRide: completed,
                distanceRide: distance,
                durationEvidence: recoveredDuration,
                calendarAttribution: .rideBegan
            )
        }
    }

    @Test("distance and average-speed calendar attribution must be the same explicit policy")
    func calendarAttributionMismatch() throws {
        let completed = try completedRide(
            beganAtDate: date(2026, 8, 7, 23),
            endedAtDate: date(2026, 8, 8, 1)
        )
        let beganDistance = try distanceRide(
            for: completed,
            attribution: .rideBegan
        )
        let duration = try durationEvidence(
            for: completed,
            fixture: .complete(100)
        )

        #expect(throws: RideAverageSpeedStatisticsError.invalidRide) {
            _ = try RideAverageSpeedStatisticsRide(
                completedRide: completed,
                distanceRide: beganDistance,
                durationEvidence: duration,
                calendarAttribution: .rideEnded
            )
        }
    }

    @Test("exact duplicate sessions deduplicate while conflicting copies fail closed")
    func duplicateSessionHandling() throws {
        let completed = try completedRide()
        let first = try statisticsRide(
            completedRide: completed,
            distanceMeters: 1_000,
            duration: .complete(100_000_000_000)
        )
        let duplicate = first
        let conflicting = try statisticsRide(
            completedRide: completed,
            distanceMeters: 2_000,
            duration: .complete(100_000_000_000)
        )

        let deduplicated = try RideAverageSpeedStatisticsAggregator.summarize(
            period: .today,
            rides: [first, duplicate],
            referenceDate: date(2026, 8, 7, 18),
            calendar: calendar()
        )
        #expect(deduplicated.rideCount == 1)
        #expect(deduplicated.averageElapsedRideSpeedMetersPerSecond == 10)

        #expect(throws: RideAverageSpeedStatisticsError.sessionConflict(completed.sessionID)) {
            _ = try RideAverageSpeedStatisticsAggregator.summarize(
                period: .today,
                rides: [first, conflicting],
                referenceDate: date(2026, 8, 7, 18),
                calendar: calendar()
            )
        }
    }

    @Test("a conflicting copy outside the bucket still invalidates a selected session")
    func selectedSessionConflictAcrossPeriodBoundary() throws {
        let id = UUID()
        let todayRide = try statisticsRide(
            completedRide: completedRide(
                id: id,
                beganAtDate: date(2026, 8, 7, 10)
            ),
            distanceMeters: 1_000,
            duration: .complete(100_000_000_000)
        )
        let yesterdayCopy = try statisticsRide(
            completedRide: completedRide(
                id: id,
                beganAtDate: date(2026, 8, 6, 10)
            ),
            distanceMeters: 1_000,
            duration: .complete(100_000_000_000)
        )

        #expect(throws: RideAverageSpeedStatisticsError.sessionConflict(id)) {
            _ = try RideAverageSpeedStatisticsAggregator.summarize(
                period: .today,
                rides: [todayRide, yesterdayCopy],
                referenceDate: date(2026, 8, 7, 18),
                calendar: calendar()
            )
        }
    }

    @Test("duration aggregation overflow fails closed")
    func durationOverflow() throws {
        let first = try statisticsRide(
            completedRide: completedRide(id: UUID()),
            distanceMeters: 1,
            duration: .complete(UInt64.max - 1)
        )
        let second = try statisticsRide(
            completedRide: completedRide(id: UUID()),
            distanceMeters: 1,
            duration: .complete(2)
        )

        #expect(throws: RideAverageSpeedStatisticsError.aggregateOverflow) {
            _ = try RideAverageSpeedStatisticsAggregator.summarize(
                period: .today,
                rides: [first, second],
                referenceDate: date(2026, 8, 7, 18),
                calendar: calendar()
            )
        }
    }

    @Test("distance aggregation overflow fails closed")
    func distanceOverflow() throws {
        let first = try statisticsRide(
            completedRide: completedRide(id: UUID()),
            distanceMeters: .greatestFiniteMagnitude,
            duration: .complete(1)
        )
        let second = try statisticsRide(
            completedRide: completedRide(id: UUID()),
            distanceMeters: .greatestFiniteMagnitude,
            duration: .complete(1)
        )

        #expect(throws: RideAverageSpeedStatisticsError.aggregateOverflow) {
            _ = try RideAverageSpeedStatisticsAggregator.summarize(
                period: .today,
                rides: [first, second],
                referenceDate: date(2026, 8, 7, 18),
                calendar: calendar()
            )
        }
    }

    @Test("empty period is distinct from rides whose paired evidence is unavailable")
    func noRidesVersusUnavailable() throws {
        let empty = try RideAverageSpeedStatisticsAggregator.summarize(
            period: .today,
            rides: [],
            referenceDate: date(2026, 8, 7, 18),
            calendar: calendar()
        )
        #expect(empty.availability == .noRides)
        #expect(empty.rideCount == 0)
        #expect(empty.averageElapsedRideSpeedMetersPerSecond == nil)

        let unavailableRide = try statisticsRide(
            completedRide: completedRide(),
            distanceMeters: 10,
            duration: .unavailable
        )
        let unavailable = try RideAverageSpeedStatisticsAggregator.summarize(
            period: .today,
            rides: [unavailableRide],
            referenceDate: date(2026, 8, 7, 18),
            calendar: calendar()
        )
        #expect(unavailable.availability == .unavailable)
        #expect(unavailable.rideCount == 1)
    }

    @Test("non-finite reference date is rejected")
    func invalidReferenceDate() throws {
        #expect(throws: RideAverageSpeedStatisticsError.invalidReferenceDate) {
            _ = try RideAverageSpeedStatisticsAggregator.summarize(
                period: .today,
                rides: [],
                referenceDate: Date(timeIntervalSinceReferenceDate: .nan),
                calendar: calendar()
            )
        }
    }
}
