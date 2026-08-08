import Foundation
import Testing

@testable import NembraCore

@Suite("Ride observed-maximum speed statistics")
struct RideObservedMaxSpeedStatisticsTests {
    private let epoch = Date(timeIntervalSinceReferenceDate: 20_000)

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private struct Fixture {
        let completedRide: CompletedRideEvidence
        let readiness: RideObservedPeakReadiness
        let completedPeak: CompletedRidePeakSpeedEvidence?
        let statisticsRide: RideObservedMaxSpeedStatisticsRide
    }

    private func completedRide(
        sessionID: UUID,
        beganAt: Date,
        endedAt: Date? = nil,
        continuity: RideSessionContinuity = .uninterruptedProcess
    ) throws -> CompletedRideEvidence {
        let end = endedAt ?? beganAt.addingTimeInterval(120)
        return try CompletedRideEvidence(
            sessionID: sessionID,
            beganAtDate: beganAt,
            confirmedAtDate: beganAt.addingTimeInterval(5),
            endedAtDate: end,
            startingOdometerKilometers: nil,
            endingOdometerKilometers: nil,
            qualityScreenedGPSDistanceMeters: 0,
            continuity: continuity
        )
    }

    private func sample(
        source: SpeedTelemetrySource,
        metersPerSecond: Double,
        uptime: UInt64,
        receivedAtBase: Date,
        speedAccuracy: Double? = nil,
        latencyMilliseconds: Double? = nil
    ) throws -> SpeedTelemetrySample {
        let receivedAt = receivedAtBase.addingTimeInterval(Double(uptime) / 1_000_000_000)
        let measurementDate = latencyMilliseconds.map {
            receivedAt.addingTimeInterval(-$0 / 1_000)
        }
        return try SpeedTelemetrySample(
            source: source,
            provenance: .absoluteMeasurement,
            metersPerSecond: metersPerSecond,
            receivedAtUptimeNanoseconds: uptime,
            receivedAtDate: receivedAt,
            measurementDate: measurementDate,
            speedAccuracyMetersPerSecond: speedAccuracy
        )
    }

    private func bluetoothQualityPolicy(minimumSamples: Int = 3) throws -> RideObservedPeakQualityPolicy {
        try RideObservedPeakQualityPolicy(
            telemetry: SpeedTelemetryQualityPolicy(
                requiredSource: .scooterBluetooth,
                minimumAcceptedSampleCount: minimumSamples,
                maximumRejectedSampleFraction: 0,
                maximumMeanIntervalMilliseconds: 150,
                maximumObservedIntervalMilliseconds: 200,
                maximumJitterStandardDeviationMilliseconds: 50,
                maximumEmpiricalSpeedStepKilometersPerHour: 100
            )
        )
    }

    private func gpsQualityPolicy() throws -> RideObservedPeakQualityPolicy {
        try RideObservedPeakQualityPolicy(
            telemetry: SpeedTelemetryQualityPolicy(
                requiredSource: .gps,
                minimumAcceptedSampleCount: 3,
                maximumRejectedSampleFraction: 0,
                maximumMeanIntervalMilliseconds: 150,
                maximumObservedIntervalMilliseconds: 200,
                maximumJitterStandardDeviationMilliseconds: 50,
                minimumDeliveryLatencySampleFraction: 1,
                maximumMeanDeliveryLatencyMilliseconds: 100,
                maximumEmpiricalSpeedStepKilometersPerHour: 100
            )
        )
    }

    private func qualifiedFixture(
        sessionID: UUID,
        beganAt: Date,
        speeds: [Double],
        endedAt: Date? = nil,
        attribution: RideStatisticsCalendarAttribution = .rideBegan
    ) throws -> Fixture {
        let ride = try completedRide(sessionID: sessionID, beganAt: beganAt, endedAt: endedAt)
        var session = RideSpeedEvidenceSessionAccumulator(
            sessionID: sessionID,
            peakPolicy: try PeakSpeedPolicy(source: .scooterBluetooth)
        )
        for (index, speed) in speeds.enumerated() {
            _ = session.record(try sample(
                source: .scooterBluetooth,
                metersPerSecond: speed,
                uptime: UInt64(index + 1) * 100_000_000,
                receivedAtBase: beganAt
            ))
        }
        let snapshot = session.snapshot
        let readiness = snapshot.observedPeakReadiness(
            using: try bluetoothQualityPolicy(minimumSamples: speeds.count)
        )
        let livePeak = try #require(snapshot.peakEvidence)
        let durable = try CompletedRidePeakSpeedEvidence(completedRide: ride, ridePeak: livePeak)
        let statisticsRide = try RideObservedMaxSpeedStatisticsRide(
            completedRide: ride,
            completedPeak: durable,
            readiness: readiness,
            calendarAttribution: attribution
        )
        return Fixture(
            completedRide: ride,
            readiness: readiness,
            completedPeak: durable,
            statisticsRide: statisticsRide
        )
    }

    private func interruptedFixture(
        sessionID: UUID,
        beganAt: Date,
        highSpeed: Double = 20
    ) throws -> Fixture {
        let ride = try completedRide(sessionID: sessionID, beganAt: beganAt)
        var session = RideSpeedEvidenceSessionAccumulator(
            sessionID: sessionID,
            peakPolicy: try PeakSpeedPolicy(source: .scooterBluetooth)
        )
        _ = session.record(try sample(
            source: .scooterBluetooth,
            metersPerSecond: 2,
            uptime: 100_000_000,
            receivedAtBase: beganAt
        ))
        _ = session.record(try sample(
            source: .scooterBluetooth,
            metersPerSecond: 4,
            uptime: 200_000_000,
            receivedAtBase: beganAt
        ))
        session.recordInterruption(.selectedSourceUnavailable)
        _ = session.record(try sample(
            source: .scooterBluetooth,
            metersPerSecond: highSpeed,
            uptime: 10_000_000_000,
            receivedAtBase: beganAt
        ))
        _ = session.record(try sample(
            source: .scooterBluetooth,
            metersPerSecond: highSpeed - 1,
            uptime: 10_100_000_000,
            receivedAtBase: beganAt
        ))

        let snapshot = session.snapshot
        let readiness = snapshot.observedPeakReadiness(
            using: try bluetoothQualityPolicy(minimumSamples: 4)
        )
        #expect(!readiness.isReady)
        let livePeak = try #require(snapshot.peakEvidence)
        let durable = try CompletedRidePeakSpeedEvidence(completedRide: ride, ridePeak: livePeak)
        let statisticsRide = try RideObservedMaxSpeedStatisticsRide(
            completedRide: ride,
            completedPeak: durable,
            readiness: readiness,
            calendarAttribution: .rideBegan
        )
        return Fixture(
            completedRide: ride,
            readiness: readiness,
            completedPeak: durable,
            statisticsRide: statisticsRide
        )
    }

    private func noPeakGPSFixture(sessionID: UUID, beganAt: Date) throws -> Fixture {
        let ride = try completedRide(sessionID: sessionID, beganAt: beganAt)
        var session = RideSpeedEvidenceSessionAccumulator(
            sessionID: sessionID,
            peakPolicy: try PeakSpeedPolicy(
                source: .gps,
                maximumSpeedAccuracyMetersPerSecond: 0.5
            )
        )
        for index in 1...3 {
            _ = session.record(try sample(
                source: .gps,
                metersPerSecond: Double(index),
                uptime: UInt64(index) * 100_000_000,
                receivedAtBase: beganAt,
                speedAccuracy: 0.8,
                latencyMilliseconds: 50
            ))
        }
        let readiness = session.snapshot.observedPeakReadiness(using: try gpsQualityPolicy())
        #expect(!readiness.isReady)
        #expect(readiness.peakEvidence == nil)
        let statisticsRide = try RideObservedMaxSpeedStatisticsRide(
            completedRide: ride,
            completedPeak: nil,
            readiness: readiness,
            calendarAttribution: .rideBegan
        )
        return Fixture(
            completedRide: ride,
            readiness: readiness,
            completedPeak: nil,
            statisticsRide: statisticsRide
        )
    }

    @Test("complete period chooses the highest qualified accepted observation")
    func completePeriodChoosesHighestQualifiedObservation() throws {
        let lowID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
        let highID = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
        let low = try qualifiedFixture(sessionID: lowID, beganAt: epoch, speeds: [2, 4, 3])
        let high = try qualifiedFixture(
            sessionID: highID,
            beganAt: epoch.addingTimeInterval(300),
            speeds: [5, 7, 6]
        )
        let summary = try RideObservedMaxSpeedStatisticsAggregator.summarize(
            period: .allTime,
            rides: [low.statisticsRide, high.statisticsRide],
            referenceDate: epoch,
            calendar: utcCalendar
        )

        #expect(summary.availability == .complete)
        #expect(summary.rideCount == 2)
        #expect(summary.qualifyingRideCount == 2)
        #expect(summary.highestQualifiedObservedSpeedMetersPerSecond == 7)
        #expect(summary.highestQualifiedObservedSpeedSessionID == highID)
        #expect(summary.permitsCompletePeriodObservedMaximumWording)

        let presentation = try RideObservedMaxSpeedStatisticsPresenter.present(summary)
        #expect(presentation.state == .completeQualifiedEvidence)
        #expect(presentation.highestQualifiedObservedSpeedMetersPerSecond == 7)
    }

    @Test("partial period cannot promote a faster unqualified ride")
    func partialPeriodKeepsUnqualifiedFasterRideOut() throws {
        let qualified = try qualifiedFixture(
            sessionID: UUID(uuidString: "40000000-0000-0000-0000-000000000004")!,
            beganAt: epoch,
            speeds: [4, 6, 5]
        )
        let interrupted = try interruptedFixture(
            sessionID: UUID(uuidString: "50000000-0000-0000-0000-000000000005")!,
            beganAt: epoch.addingTimeInterval(300),
            highSpeed: 20
        )
        let summary = try RideObservedMaxSpeedStatisticsAggregator.summarize(
            period: .allTime,
            rides: [interrupted.statisticsRide, qualified.statisticsRide],
            referenceDate: epoch,
            calendar: utcCalendar
        )

        #expect(summary.availability == .partial)
        #expect(summary.qualifyingRideCount == 1)
        #expect(summary.unqualifiedObservedPeakRideCount == 1)
        #expect(summary.highestQualifiedObservedSpeedMetersPerSecond == 6)
        #expect(!summary.permitsCompletePeriodObservedMaximumWording)
        #expect(summary.requiresIncompleteEvidenceDisclosure)

        let presentation = try RideObservedMaxSpeedStatisticsPresenter.present(summary)
        #expect(presentation.state == .partialQualifiedEvidence)
        #expect(presentation.highestQualifiedObservedSpeedMetersPerSecond == 6)
        #expect(presentation.requiresIncompleteEvidenceDisclosure)
    }

    @Test("completed rides without a qualified peak are unavailable, never zero")
    func unavailableNeverManufacturesZero() throws {
        let interrupted = try interruptedFixture(
            sessionID: UUID(uuidString: "60000000-0000-0000-0000-000000000006")!,
            beganAt: epoch,
            highSpeed: 18
        )
        let noPeak = try noPeakGPSFixture(
            sessionID: UUID(uuidString: "70000000-0000-0000-0000-000000000007")!,
            beganAt: epoch.addingTimeInterval(300)
        )
        let summary = try RideObservedMaxSpeedStatisticsAggregator.summarize(
            period: .allTime,
            rides: [interrupted.statisticsRide, noPeak.statisticsRide],
            referenceDate: epoch,
            calendar: utcCalendar
        )

        #expect(summary.availability == .unavailable)
        #expect(summary.peakUnavailableRideCount == 1)
        #expect(summary.unqualifiedObservedPeakRideCount == 1)
        #expect(summary.highestQualifiedObservedSpeedMetersPerSecond == nil)
        #expect(try RideObservedMaxSpeedStatisticsPresenter.present(summary).state == .observedMaximumUnavailable)
    }

    @Test("no rides stays distinct from unavailable evidence")
    func noRidesStayDistinct() throws {
        let summary = try RideObservedMaxSpeedStatisticsAggregator.summarize(
            period: .today,
            rides: [],
            referenceDate: epoch,
            calendar: utcCalendar
        )
        #expect(summary.availability == .noRides)
        #expect(try RideObservedMaxSpeedStatisticsPresenter.present(summary).state == .noCompletedRides)
    }

    @Test("identical duplicate session records are idempotent")
    func identicalDuplicatesDeduplicate() throws {
        let fixture = try qualifiedFixture(
            sessionID: UUID(uuidString: "80000000-0000-0000-0000-000000000008")!,
            beganAt: epoch,
            speeds: [2, 5, 4]
        )
        let summary = try RideObservedMaxSpeedStatisticsAggregator.summarize(
            period: .allTime,
            rides: [fixture.statisticsRide, fixture.statisticsRide],
            referenceDate: epoch,
            calendar: utcCalendar
        )
        #expect(summary.rideCount == 1)
        #expect(summary.highestQualifiedObservedSpeedMetersPerSecond == 5)
    }

    @Test("conflicting records for one immutable session fail closed")
    func conflictingDuplicateSessionFailsClosed() throws {
        let sessionID = UUID(uuidString: "90000000-0000-0000-0000-000000000009")!
        let first = try qualifiedFixture(sessionID: sessionID, beganAt: epoch, speeds: [2, 5, 4])
        let conflicting = try qualifiedFixture(sessionID: sessionID, beganAt: epoch, speeds: [2, 8, 4])
        #expect(throws: RideObservedMaxSpeedStatisticsError.sessionConflict(sessionID)) {
            try RideObservedMaxSpeedStatisticsAggregator.summarize(
                period: .allTime,
                rides: [first.statisticsRide, conflicting.statisticsRide],
                referenceDate: epoch,
                calendar: utcCalendar
            )
        }
    }

    @Test("equal maxima use session identity only as deterministic tie break")
    func equalMaximaTieBreakBySessionIdentity() throws {
        let lowerID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let higherID = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!
        let lower = try qualifiedFixture(
            sessionID: lowerID,
            beganAt: epoch.addingTimeInterval(300),
            speeds: [3, 5, 4]
        )
        let higher = try qualifiedFixture(sessionID: higherID, beganAt: epoch, speeds: [4, 5, 3])
        let summary = try RideObservedMaxSpeedStatisticsAggregator.summarize(
            period: .allTime,
            rides: [higher.statisticsRide, lower.statisticsRide],
            referenceDate: epoch,
            calendar: utcCalendar
        )
        #expect(summary.highestQualifiedObservedSpeedSessionID == lowerID)
    }

    @Test("bounded period ignores a higher peak outside its calendar bucket")
    func boundedPeriodSelection() throws {
        let calendar = utcCalendar
        let today = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let todayRide = try qualifiedFixture(
            sessionID: UUID(uuidString: "A0000000-0000-0000-0000-00000000000A")!,
            beganAt: today,
            speeds: [3, 6, 5]
        )
        let yesterdayRide = try qualifiedFixture(
            sessionID: UUID(uuidString: "B0000000-0000-0000-0000-00000000000B")!,
            beganAt: yesterday,
            speeds: [10, 12, 11]
        )
        let summary = try RideObservedMaxSpeedStatisticsAggregator.summarize(
            period: .today,
            rides: [yesterdayRide.statisticsRide, todayRide.statisticsRide],
            referenceDate: today,
            calendar: calendar
        )
        #expect(summary.rideCount == 1)
        #expect(summary.highestQualifiedObservedSpeedMetersPerSecond == 6)
    }

    @Test("cross-midnight ownership follows explicit calendar attribution")
    func crossMidnightCalendarAttributionIsExplicit() throws {
        let calendar = utcCalendar
        let reference = calendar.date(from: DateComponents(year: 2026, month: 8, day: 7, hour: 12))!
        let began = calendar.date(from: DateComponents(year: 2026, month: 8, day: 6, hour: 23, minute: 58))!
        let ended = calendar.date(from: DateComponents(year: 2026, month: 8, day: 7, hour: 0, minute: 5))!
        let sessionID = UUID(uuidString: "C0000000-0000-0000-0000-00000000000C")!
        let beganOwned = try qualifiedFixture(
            sessionID: sessionID,
            beganAt: began,
            speeds: [3, 5, 4],
            endedAt: ended,
            attribution: .rideBegan
        )
        let endedOwned = try qualifiedFixture(
            sessionID: sessionID,
            beganAt: began,
            speeds: [3, 5, 4],
            endedAt: ended,
            attribution: .rideEnded
        )
        let beginSummary = try RideObservedMaxSpeedStatisticsAggregator.summarize(
            period: .today,
            rides: [beganOwned.statisticsRide],
            referenceDate: reference,
            calendar: calendar
        )
        let endSummary = try RideObservedMaxSpeedStatisticsAggregator.summarize(
            period: .today,
            rides: [endedOwned.statisticsRide],
            referenceDate: reference,
            calendar: calendar
        )
        #expect(beginSummary.rideCount == 0)
        #expect(endSummary.rideCount == 1)
    }

    @Test("readiness from another ride cannot qualify this completed ride")
    func sessionMismatchCannotCrossQualify() throws {
        let first = try qualifiedFixture(
            sessionID: UUID(uuidString: "D0000000-0000-0000-0000-00000000000D")!,
            beganAt: epoch,
            speeds: [2, 5, 4]
        )
        let otherRide = try completedRide(
            sessionID: UUID(uuidString: "E0000000-0000-0000-0000-00000000000E")!,
            beganAt: epoch
        )
        #expect(throws: RideObservedMaxSpeedStatisticsError.sessionMismatch) {
            try RideObservedMaxSpeedStatisticsRide(
                completedRide: otherRide,
                completedPeak: first.completedPeak,
                readiness: first.readiness,
                calendarAttribution: .rideBegan
            )
        }
    }

    @Test("ready live peak requires its exact durable projection")
    func readyPeakCannotLoseDurableProjection() throws {
        let fixture = try qualifiedFixture(
            sessionID: UUID(uuidString: "F0000000-0000-0000-0000-00000000000F")!,
            beganAt: epoch,
            speeds: [2, 5, 4]
        )
        #expect(throws: RideObservedMaxSpeedStatisticsError.evidenceMismatch) {
            try RideObservedMaxSpeedStatisticsRide(
                completedRide: fixture.completedRide,
                completedPeak: nil,
                readiness: fixture.readiness,
                calendarAttribution: .rideBegan
            )
        }
    }

    @Test("same-session durable peak cannot borrow a different clean readiness audit")
    func durablePeakMustExactlyMatchReadinessPeak() throws {
        let sessionID = UUID(uuidString: "11111111-AAAA-BBBB-CCCC-111111111111")!
        let fixture = try qualifiedFixture(sessionID: sessionID, beganAt: epoch, speeds: [2, 5, 4])
        var otherAccumulator = RidePeakSpeedEvidenceAccumulator(
            sessionID: sessionID,
            policy: try PeakSpeedPolicy(source: .scooterBluetooth)
        )
        _ = otherAccumulator.record(try sample(
            source: .scooterBluetooth,
            metersPerSecond: 9,
            uptime: 100_000_000,
            receivedAtBase: epoch
        ))
        let otherLivePeak = try #require(otherAccumulator.evidence)
        let otherDurable = try CompletedRidePeakSpeedEvidence(
            completedRide: fixture.completedRide,
            ridePeak: otherLivePeak
        )
        #expect(throws: RideObservedMaxSpeedStatisticsError.evidenceMismatch) {
            try RideObservedMaxSpeedStatisticsRide(
                completedRide: fixture.completedRide,
                completedPeak: otherDurable,
                readiness: fixture.readiness,
                calendarAttribution: .rideBegan
            )
        }
    }

    @Test("presentation rejects contradictory counts")
    func presentationRejectsContradictoryCounts() {
        let summary = RideObservedMaxSpeedStatisticsSummary(
            period: .week,
            rideCount: 2,
            qualifyingRideCount: 1,
            peakUnavailableRideCount: 0,
            unqualifiedObservedPeakRideCount: 0,
            availability: .partial,
            highestQualifiedObservedSpeedMetersPerSecond: 5,
            highestQualifiedObservedSpeedSessionID: UUID(uuidString: "22222222-AAAA-BBBB-CCCC-222222222222"),
            highestQualifiedObservedSpeedSource: .scooterBluetooth,
            highestQualifiedObservedSpeedAccuracyMetersPerSecond: nil
        )
        #expect(throws: RideObservedMaxSpeedStatisticsPresentationError.invalidSummary) {
            try RideObservedMaxSpeedStatisticsPresenter.present(summary)
        }
    }

    @Test("presentation rejects nonfinite and non-authoritative fabricated winners")
    func presentationRejectsMalformedWinner() {
        let sessionID = UUID(uuidString: "33333333-AAAA-BBBB-CCCC-333333333333")!
        let nanSummary = RideObservedMaxSpeedStatisticsSummary(
            period: .week,
            rideCount: 1,
            qualifyingRideCount: 1,
            peakUnavailableRideCount: 0,
            unqualifiedObservedPeakRideCount: 0,
            availability: .complete,
            highestQualifiedObservedSpeedMetersPerSecond: .nan,
            highestQualifiedObservedSpeedSessionID: sessionID,
            highestQualifiedObservedSpeedSource: .scooterBluetooth,
            highestQualifiedObservedSpeedAccuracyMetersPerSecond: nil
        )
        let motionAssistSummary = RideObservedMaxSpeedStatisticsSummary(
            period: .week,
            rideCount: 1,
            qualifyingRideCount: 1,
            peakUnavailableRideCount: 0,
            unqualifiedObservedPeakRideCount: 0,
            availability: .complete,
            highestQualifiedObservedSpeedMetersPerSecond: 5,
            highestQualifiedObservedSpeedSessionID: sessionID,
            highestQualifiedObservedSpeedSource: .motionAssist,
            highestQualifiedObservedSpeedAccuracyMetersPerSecond: nil
        )
        #expect(throws: RideObservedMaxSpeedStatisticsPresentationError.invalidSummary) {
            try RideObservedMaxSpeedStatisticsPresenter.present(nanSummary)
        }
        #expect(throws: RideObservedMaxSpeedStatisticsPresentationError.invalidSummary) {
            try RideObservedMaxSpeedStatisticsPresenter.present(motionAssistSummary)
        }
    }

    @Test("invalid reference date fails before calendar bucketing")
    func invalidReferenceDateFailsClosed() throws {
        let fixture = try qualifiedFixture(
            sessionID: UUID(uuidString: "44444444-AAAA-BBBB-CCCC-444444444444")!,
            beganAt: epoch,
            speeds: [2, 5, 4]
        )
        #expect(throws: RideObservedMaxSpeedStatisticsError.invalidReferenceDate) {
            try RideObservedMaxSpeedStatisticsAggregator.summarize(
                period: .today,
                rides: [fixture.statisticsRide],
                referenceDate: Date(timeIntervalSinceReferenceDate: .nan),
                calendar: utcCalendar
            )
        }
    }
}
