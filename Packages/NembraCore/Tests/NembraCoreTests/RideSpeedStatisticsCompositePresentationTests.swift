import Foundation
import Testing

@testable import NembraCore

@Suite("Ride speed statistics composite presentation")
struct RideSpeedStatisticsCompositePresentationTests {
    private struct PreparedSpeedRide {
        let completed: CompletedRideEvidence
        let average: RideAverageSpeedStatisticsRide
        let maximum: RideObservedMaxSpeedStatisticsRide
    }

    private var calendar: Calendar {
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
        _ hour: Int = 12,
        _ minute: Int = 0
    ) -> Date {
        calendar.date(
            from: DateComponents(
                year: year,
                month: month,
                day: day,
                hour: hour,
                minute: minute
            )
        )!
    }

    private func completedRide(
        sessionID: UUID,
        beganAt: Date,
        endedAt: Date? = nil
    ) throws -> CompletedRideEvidence {
        let end = endedAt ?? beganAt.addingTimeInterval(120)
        return try CompletedRideEvidence(
            sessionID: sessionID,
            beganAtDate: beganAt,
            confirmedAtDate: beganAt.addingTimeInterval(1),
            endedAtDate: end,
            startingOdometerKilometers: nil,
            endingOdometerKilometers: nil,
            qualityScreenedGPSDistanceMeters: 0,
            continuity: .uninterruptedProcess
        )
    }

    private func durationEvidence(
        for completedRide: CompletedRideEvidence,
        nanoseconds: UInt64 = 100_000_000_000
    ) throws -> CompletedRideDurationEvidence {
        var accumulator = RideSessionDurationEvidenceAccumulator(
            sessionID: completedRide.sessionID
        )
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
        return try CompletedRideDurationEvidence(
            completedRide: completedRide,
            duration: accumulator.snapshot
        )
    }

    private func averageRide(
        for completedRide: CompletedRideEvidence,
        distanceMeters: Double? = 1_000,
        distanceDisposition: RideStatisticsDistanceDisposition = .included,
        attribution: RideStatisticsCalendarAttribution = .rideBegan
    ) throws -> RideAverageSpeedStatisticsRide {
        let attributedDate: Date
        switch attribution {
        case .rideBegan:
            attributedDate = completedRide.beganAtDate
        case .rideEnded:
            attributedDate = completedRide.endedAtDate
        }

        let distance = try RideStatisticsRide(
            sessionID: completedRide.sessionID,
            attributedDate: attributedDate,
            distanceMeters: distanceMeters,
            distanceDisposition: distanceDisposition
        )
        return try RideAverageSpeedStatisticsRide(
            completedRide: completedRide,
            distanceRide: distance,
            durationEvidence: durationEvidence(for: completedRide),
            calendarAttribution: attribution
        )
    }

    private func sample(
        metersPerSecond: Double,
        uptime: UInt64,
        receivedAtBase: Date
    ) throws -> SpeedTelemetrySample {
        try SpeedTelemetrySample(
            source: .scooterBluetooth,
            provenance: .absoluteMeasurement,
            metersPerSecond: metersPerSecond,
            receivedAtUptimeNanoseconds: uptime,
            receivedAtDate: receivedAtBase.addingTimeInterval(Double(uptime) / 1_000_000_000),
            measurementDate: nil,
            speedAccuracyMetersPerSecond: nil
        )
    }

    private func observedPeakPolicy() throws -> RideObservedPeakQualityPolicy {
        try RideObservedPeakQualityPolicy(
            telemetry: SpeedTelemetryQualityPolicy(
                requiredSource: .scooterBluetooth,
                minimumAcceptedSampleCount: 3,
                maximumRejectedSampleFraction: 0,
                maximumMeanIntervalMilliseconds: 150,
                maximumObservedIntervalMilliseconds: 200,
                maximumJitterStandardDeviationMilliseconds: 50,
                maximumEmpiricalSpeedStepKilometersPerHour: 100
            )
        )
    }

    private func maximumRide(
        for completedRide: CompletedRideEvidence,
        speeds: [Double] = [2, 4, 3],
        attribution: RideStatisticsCalendarAttribution = .rideBegan
    ) throws -> RideObservedMaxSpeedStatisticsRide {
        var evidence = RideSpeedEvidenceSessionAccumulator(
            sessionID: completedRide.sessionID,
            peakPolicy: try PeakSpeedPolicy(source: .scooterBluetooth)
        )
        for (index, speed) in speeds.enumerated() {
            _ = evidence.record(try sample(
                metersPerSecond: speed,
                uptime: UInt64(index + 1) * 100_000_000,
                receivedAtBase: completedRide.beganAtDate
            ))
        }

        let snapshot = evidence.snapshot
        let readiness = snapshot.observedPeakReadiness(using: try observedPeakPolicy())
        let livePeak = try #require(snapshot.peakEvidence)
        let durablePeak = try CompletedRidePeakSpeedEvidence(
            completedRide: completedRide,
            ridePeak: livePeak
        )
        return try RideObservedMaxSpeedStatisticsRide(
            completedRide: completedRide,
            completedPeak: durablePeak,
            readiness: readiness,
            calendarAttribution: attribution
        )
    }

    private func preparedRide(
        sessionID: UUID = UUID(),
        beganAt: Date,
        endedAt: Date? = nil,
        averageDistanceMeters: Double? = 1_000,
        averageDistanceDisposition: RideStatisticsDistanceDisposition = .included,
        averageAttribution: RideStatisticsCalendarAttribution = .rideBegan,
        maximumAttribution: RideStatisticsCalendarAttribution = .rideBegan,
        speeds: [Double] = [2, 4, 3]
    ) throws -> PreparedSpeedRide {
        let completed = try completedRide(
            sessionID: sessionID,
            beganAt: beganAt,
            endedAt: endedAt
        )
        return PreparedSpeedRide(
            completed: completed,
            average: try averageRide(
                for: completed,
                distanceMeters: averageDistanceMeters,
                distanceDisposition: averageDistanceDisposition,
                attribution: averageAttribution
            ),
            maximum: try maximumRide(
                for: completed,
                speeds: speeds,
                attribution: maximumAttribution
            )
        )
    }

    @Test("matching selected rides compose truthful average and observed maximum")
    func matchingSelectedRidesCompose() throws {
        let first = try preparedRide(
            sessionID: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
            beganAt: date(2026, 8, 7, 10),
            averageDistanceMeters: 1_000,
            speeds: [2, 4, 3]
        )
        let second = try preparedRide(
            sessionID: UUID(uuidString: "20000000-0000-0000-0000-000000000002")!,
            beganAt: date(2026, 8, 7, 14),
            averageDistanceMeters: 2_000,
            speeds: [5, 7, 6]
        )

        let presentation = try RideSpeedStatisticsCompositePresenter.present(
            period: .today,
            averageSpeedRides: [first.average, second.average],
            observedMaximumRides: [first.maximum, second.maximum],
            referenceDate: date(2026, 8, 7, 18),
            calendar: calendar
        )

        #expect(presentation.period == .today)
        #expect(presentation.rideCount == 2)
        #expect(presentation.elapsedAverage.state == .completePairedEvidence)
        #expect(presentation.elapsedAverage.averageElapsedRideSpeedMetersPerSecond == 15)
        #expect(presentation.observedMaximum.state == .completeQualifiedEvidence)
        #expect(presentation.observedMaximum.highestQualifiedObservedSpeedMetersPerSecond == 7)
    }

    @Test("same period and count cannot hide different selected sessions")
    func sameCountDifferentSessionsFailsClosed() throws {
        let averageOnly = try preparedRide(
            sessionID: UUID(uuidString: "30000000-0000-0000-0000-000000000003")!,
            beganAt: date(2026, 8, 7, 10)
        )
        let maximumOnly = try preparedRide(
            sessionID: UUID(uuidString: "40000000-0000-0000-0000-000000000004")!,
            beganAt: date(2026, 8, 7, 10)
        )

        #expect(throws: RideSpeedStatisticsCompositePresentationError.selectedRideScopeMismatch) {
            try RideSpeedStatisticsCompositePresenter.present(
                period: .today,
                averageSpeedRides: [averageOnly.average],
                observedMaximumRides: [maximumOnly.maximum],
                referenceDate: date(2026, 8, 7, 18),
                calendar: calendar
            )
        }
    }

    @Test("same session with different calendar attribution cannot be composed")
    func sameSessionDifferentAttributionFailsClosed() throws {
        let crossMidnight = try preparedRide(
            sessionID: UUID(uuidString: "50000000-0000-0000-0000-000000000005")!,
            beganAt: date(2026, 8, 7, 23, 55),
            endedAt: date(2026, 8, 8, 0, 5),
            averageAttribution: .rideBegan,
            maximumAttribution: .rideEnded
        )

        #expect(throws: RideSpeedStatisticsCompositePresentationError.selectedRideScopeMismatch) {
            try RideSpeedStatisticsCompositePresenter.present(
                period: .allTime,
                averageSpeedRides: [crossMidnight.average],
                observedMaximumRides: [crossMidnight.maximum],
                referenceDate: date(2026, 8, 8, 12),
                calendar: calendar
            )
        }
    }

    @Test("metric evidence completeness remains independent inside one shared ride population")
    func componentCompletenessRemainsIndependent() throws {
        let complete = try preparedRide(
            sessionID: UUID(uuidString: "60000000-0000-0000-0000-000000000006")!,
            beganAt: date(2026, 8, 7, 10),
            averageDistanceMeters: 1_000,
            speeds: [2, 4, 3]
        )
        let averageExcluded = try preparedRide(
            sessionID: UUID(uuidString: "70000000-0000-0000-0000-000000000007")!,
            beganAt: date(2026, 8, 7, 14),
            averageDistanceMeters: nil,
            averageDistanceDisposition: .excludedInsufficientEvidence,
            speeds: [5, 7, 6]
        )

        let presentation = try RideSpeedStatisticsCompositePresenter.present(
            period: .today,
            averageSpeedRides: [complete.average, averageExcluded.average],
            observedMaximumRides: [complete.maximum, averageExcluded.maximum],
            referenceDate: date(2026, 8, 7, 18),
            calendar: calendar
        )

        #expect(presentation.rideCount == 2)
        #expect(presentation.elapsedAverage.state == .partialPairedEvidence)
        #expect(presentation.elapsedAverage.ridesSupportingAverage == 1)
        #expect(presentation.elapsedAverage.requiresIncompleteEvidenceDisclosure)
        #expect(presentation.observedMaximum.state == .completeQualifiedEvidence)
        #expect(presentation.observedMaximum.ridesSupportingObservedMaximum == 2)
        #expect(!presentation.observedMaximum.requiresIncompleteEvidenceDisclosure)
    }

    @Test("bounded period ignores unrelated rides outside the selected window")
    func boundedPeriodIgnoresUnrelatedOutsideRides() throws {
        let selected = try preparedRide(
            sessionID: UUID(uuidString: "80000000-0000-0000-0000-000000000008")!,
            beganAt: date(2026, 8, 7, 10)
        )
        let averageOutside = try preparedRide(
            sessionID: UUID(uuidString: "90000000-0000-0000-0000-000000000009")!,
            beganAt: date(2026, 8, 6, 10)
        )
        let maximumOutside = try preparedRide(
            sessionID: UUID(uuidString: "A0000000-0000-0000-0000-00000000000A")!,
            beganAt: date(2026, 8, 8, 10)
        )

        let presentation = try RideSpeedStatisticsCompositePresenter.present(
            period: .today,
            averageSpeedRides: [selected.average, averageOutside.average],
            observedMaximumRides: [selected.maximum, maximumOutside.maximum],
            referenceDate: date(2026, 8, 7, 18),
            calendar: calendar
        )

        #expect(presentation.rideCount == 1)
        #expect(presentation.elapsedAverage.rideCount == 1)
        #expect(presentation.observedMaximum.rideCount == 1)
    }

    @Test("empty populations compose as no completed rides")
    func emptyPopulationsCompose() throws {
        let presentation = try RideSpeedStatisticsCompositePresenter.present(
            period: .month,
            averageSpeedRides: [],
            observedMaximumRides: [],
            referenceDate: date(2026, 8, 7, 18),
            calendar: calendar
        )

        #expect(presentation.rideCount == 0)
        #expect(presentation.elapsedAverage.state == .noCompletedRides)
        #expect(presentation.observedMaximum.state == .noCompletedRides)
    }
}
