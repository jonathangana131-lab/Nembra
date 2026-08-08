import Foundation
import Testing

@testable import NembraCore

@Suite("Ride history observed peak presentation")
struct RideHistoryObservedPeakPresentationTests {
    private let sessionID = UUID(uuidString: "A1B2C3D4-1111-2222-3333-444455556666")!
    private let epoch = Date(timeIntervalSinceReferenceDate: 50_000)

    private struct Fixture {
        let ride: CompletedRideEvidence
        let evidence: RideObservedPeakHistoryEvidence
    }

    @Test("clean durable evidence permits observed-maximum wording")
    func qualifiedObservedMaximum() throws {
        let fixture = try bluetoothFixture(speeds: [3, 6, 5])
        let presentation = try RideHistoryObservedPeakPresenter.present(joined(fixture))

        #expect(presentation.sessionID == sessionID)
        #expect(presentation.state == .qualifiedObservedMaximum)
        #expect(presentation.selectedSource == .scooterBluetooth)
        #expect(presentation.acceptedObservedSpeedEvidenceMetersPerSecond == 6)
        #expect(presentation.qualifiedObservedMaximumMetersPerSecond == 6)
        #expect(presentation.observationContinuity == .noRecordedSelectedSourceEvidenceLoss)
        #expect(presentation.permitsObservedMaximumWording)
        #expect(!presentation.requiresQualityDisclosure)
    }

    @Test("legitimate accepted zero stays distinct from unavailable peak")
    func legitimateObservedZero() throws {
        let fixture = try bluetoothFixture(speeds: [0, 0, 0])
        let presentation = try RideHistoryObservedPeakPresenter.present(joined(fixture))

        #expect(presentation.state == .qualifiedObservedMaximum)
        #expect(presentation.acceptedObservedSpeedEvidenceMetersPerSecond == 0)
        #expect(presentation.qualifiedObservedMaximumMetersPerSecond == 0)
        #expect(presentation.observationContinuity == .noRecordedSelectedSourceEvidenceLoss)
        #expect(presentation.permitsObservedMaximumWording)
        #expect(!presentation.requiresQualityDisclosure)
    }

    @Test("clean continuity does not override a failed telemetry-quality policy")
    func telemetryQualityFailureIsUnqualified() throws {
        let fixture = try bluetoothFixture(
            speeds: [3, 6, 5],
            minimumAcceptedSampleCount: 4
        )
        let presentation = try RideHistoryObservedPeakPresenter.present(joined(fixture))

        #expect(presentation.state == .unqualifiedAcceptedObservation)
        #expect(presentation.acceptedObservedSpeedEvidenceMetersPerSecond == 6)
        #expect(presentation.qualifiedObservedMaximumMetersPerSecond == nil)
        #expect(presentation.observationContinuity == .noRecordedSelectedSourceEvidenceLoss)
        #expect(!presentation.permitsObservedMaximumWording)
        #expect(presentation.requiresQualityDisclosure)
    }

    @Test("interrupted faster observation remains visible evidence but cannot become max wording")
    func interruptedObservationIsUnqualified() throws {
        let fixture = try bluetoothFixture(
            speeds: [3, 5, 4],
            interruptionThenSpeeds: [8, 12, 10]
        )
        let presentation = try RideHistoryObservedPeakPresenter.present(joined(fixture))

        #expect(presentation.state == .unqualifiedAcceptedObservation)
        #expect(presentation.acceptedObservedSpeedEvidenceMetersPerSecond == 12)
        #expect(presentation.qualifiedObservedMaximumMetersPerSecond == nil)
        #expect(presentation.observationContinuity == .partialSelectedSourceEvidence)
        #expect(!presentation.permitsObservedMaximumWording)
        #expect(presentation.requiresQualityDisclosure)
    }

    @Test("foreign-source traffic keeps accepted observation subordinate to quality disclosure")
    func foreignSourceTrafficIsUnqualified() throws {
        let fixture = try bluetoothFixture(
            speeds: [3, 6, 5],
            includeForeignSourceCallback: true,
            maximumRejectedFraction: 1
        )
        let presentation = try RideHistoryObservedPeakPresenter.present(joined(fixture))

        #expect(presentation.state == .unqualifiedAcceptedObservation)
        #expect(presentation.acceptedObservedSpeedEvidenceMetersPerSecond == 6)
        #expect(presentation.qualifiedObservedMaximumMetersPerSecond == nil)
        #expect(!presentation.permitsObservedMaximumWording)
        #expect(presentation.requiresQualityDisclosure)
    }

    @Test("missing peak stays unavailable and never becomes fake zero")
    func missingPeakIsUnavailable() throws {
        let ride = try completedRide()
        let accumulator = RideSpeedEvidenceSessionAccumulator(
            sessionID: sessionID,
            peakPolicy: try PeakSpeedPolicy(source: .scooterBluetooth)
        )
        let readiness = accumulator.snapshot.observedPeakReadiness(using: try bluetoothPolicy())
        let evidence = try RideObservedPeakHistoryEvidence(
            completedRide: ride,
            completedPeak: nil,
            readiness: readiness
        )
        let presentation = try RideHistoryObservedPeakPresenter.present(
            joined(Fixture(ride: ride, evidence: evidence))
        )

        #expect(presentation.state == .observedPeakUnavailable)
        #expect(presentation.selectedSource == .scooterBluetooth)
        #expect(presentation.acceptedObservedSpeedEvidenceMetersPerSecond == nil)
        #expect(presentation.acceptedObservedSpeedAccuracyMetersPerSecond == nil)
        #expect(presentation.observationContinuity == nil)
        #expect(presentation.qualifiedObservedMaximumMetersPerSecond == nil)
        #expect(!presentation.permitsObservedMaximumWording)
        #expect(!presentation.requiresQualityDisclosure)
    }

    @Test("qualified GPS peak preserves accepted accuracy provenance")
    func qualifiedGPSAccuracy() throws {
        let ride = try completedRide()
        var accumulator = RideSpeedEvidenceSessionAccumulator(
            sessionID: sessionID,
            peakPolicy: try PeakSpeedPolicy(
                source: .gps,
                maximumSpeedAccuracyMetersPerSecond: 0.5
            )
        )
        for (index, speed) in [4.0, 7.0, 6.0].enumerated() {
            _ = accumulator.record(try sample(
                source: .gps,
                metersPerSecond: speed,
                uptime: UInt64(index + 1) * 100_000_000,
                speedAccuracy: 0.2
            ))
        }
        let snapshot = accumulator.snapshot
        let readiness = snapshot.observedPeakReadiness(using: try gpsPolicy())
        let ridePeak = try #require(snapshot.peakEvidence)
        let completedPeak = try CompletedRidePeakSpeedEvidence(
            completedRide: ride,
            ridePeak: ridePeak
        )
        let evidence = try RideObservedPeakHistoryEvidence(
            completedRide: ride,
            completedPeak: completedPeak,
            readiness: readiness
        )
        let presentation = try RideHistoryObservedPeakPresenter.present(
            joined(Fixture(ride: ride, evidence: evidence))
        )

        #expect(presentation.state == .qualifiedObservedMaximum)
        #expect(presentation.selectedSource == .gps)
        #expect(presentation.acceptedObservedSpeedEvidenceMetersPerSecond == 7)
        #expect(presentation.acceptedObservedSpeedAccuracyMetersPerSecond == 0.2)
        #expect(presentation.qualifiedObservedMaximumMetersPerSecond == 7)
        #expect(presentation.permitsObservedMaximumWording)
    }

    private func bluetoothFixture(
        speeds: [Double],
        interruptionThenSpeeds: [Double] = [],
        includeForeignSourceCallback: Bool = false,
        maximumRejectedFraction: Double = 0,
        minimumAcceptedSampleCount: Int = 3
    ) throws -> Fixture {
        let ride = try completedRide()
        var accumulator = RideSpeedEvidenceSessionAccumulator(
            sessionID: sessionID,
            peakPolicy: try PeakSpeedPolicy(source: .scooterBluetooth)
        )

        for (index, speed) in speeds.enumerated() {
            _ = accumulator.record(try sample(
                metersPerSecond: speed,
                uptime: UInt64(index + 1) * 100_000_000
            ))
        }

        if includeForeignSourceCallback {
            _ = accumulator.record(try sample(
                source: .motionAssist,
                metersPerSecond: 9,
                uptime: 600_000_000
            ))
        }

        if !interruptionThenSpeeds.isEmpty {
            accumulator.recordInterruption(.selectedSourceUnavailable)
            for (index, speed) in interruptionThenSpeeds.enumerated() {
                _ = accumulator.record(try sample(
                    metersPerSecond: speed,
                    uptime: 1_000_000_000 + UInt64(index + 1) * 100_000_000
                ))
            }
        }

        let snapshot = accumulator.snapshot
        let readiness = snapshot.observedPeakReadiness(
            using: try bluetoothPolicy(
                maximumRejectedFraction: maximumRejectedFraction,
                minimumAcceptedSampleCount: minimumAcceptedSampleCount
            )
        )
        let ridePeak = try #require(snapshot.peakEvidence)
        let completedPeak = try CompletedRidePeakSpeedEvidence(
            completedRide: ride,
            ridePeak: ridePeak
        )
        let evidence = try RideObservedPeakHistoryEvidence(
            completedRide: ride,
            completedPeak: completedPeak,
            readiness: readiness
        )
        return Fixture(ride: ride, evidence: evidence)
    }

    private func joined(_ fixture: Fixture) throws -> RideHistoryObservedPeakJoinedRecord {
        try RideHistoryObservedPeakJoinedRecord(
            historyRecord: RideHistoryRecord(evidence: fixture.ride),
            observedPeakRecord: RideHistoryObservedPeakRecord(evidence: fixture.evidence)
        )
    }

    private func completedRide() throws -> CompletedRideEvidence {
        try CompletedRideEvidence(
            sessionID: sessionID,
            beganAtDate: epoch,
            confirmedAtDate: epoch.addingTimeInterval(2),
            endedAtDate: epoch.addingTimeInterval(120),
            startingOdometerKilometers: nil,
            endingOdometerKilometers: nil,
            qualityScreenedGPSDistanceMeters: 0,
            continuity: .uninterruptedProcess
        )
    }

    private func sample(
        source: SpeedTelemetrySource = .scooterBluetooth,
        metersPerSecond: Double,
        uptime: UInt64,
        speedAccuracy: Double? = nil
    ) throws -> SpeedTelemetrySample {
        let receivedAt = epoch.addingTimeInterval(Double(uptime) / 1_000_000_000)
        return try SpeedTelemetrySample(
            source: source,
            provenance: source == .motionAssist ? .shortHorizonEstimate : .absoluteMeasurement,
            metersPerSecond: metersPerSecond,
            receivedAtUptimeNanoseconds: uptime,
            receivedAtDate: receivedAt,
            measurementDate: source == .gps ? receivedAt.addingTimeInterval(-0.05) : nil,
            speedAccuracyMetersPerSecond: speedAccuracy
        )
    }

    private func bluetoothPolicy(
        maximumRejectedFraction: Double = 0,
        minimumAcceptedSampleCount: Int = 3
    ) throws -> RideObservedPeakQualityPolicy {
        try RideObservedPeakQualityPolicy(
            telemetry: SpeedTelemetryQualityPolicy(
                requiredSource: .scooterBluetooth,
                minimumAcceptedSampleCount: minimumAcceptedSampleCount,
                maximumRejectedSampleFraction: maximumRejectedFraction,
                maximumMeanIntervalMilliseconds: 150,
                maximumObservedIntervalMilliseconds: 200,
                maximumJitterStandardDeviationMilliseconds: 50,
                maximumEmpiricalSpeedStepKilometersPerHour: 100
            )
        )
    }

    private func gpsPolicy() throws -> RideObservedPeakQualityPolicy {
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
}
