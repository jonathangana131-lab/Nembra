import Foundation
import Testing

@testable import NembraCore

@Suite("Ride history observed peak consumer projection")
struct RideHistoryObservedPeakConsumerProjectionTests {
    private let sessionID = UUID(uuidString: "B2C3D4E5-2222-3333-4444-555566667777")!
    private let epoch = Date(timeIntervalSinceReferenceDate: 60_000)

    private struct Fixture {
        let ride: CompletedRideEvidence
        let evidence: RideObservedPeakHistoryEvidence
    }

    @Test("qualified peak exposes exactly one observed-maximum state")
    func qualifiedPeak() throws {
        let presentation = try RideHistoryObservedPeakPresenter.present(
            joined(try bluetoothFixture(speeds: [3, 6, 5]))
        )
        let projection = try #require(
            RideHistoryObservedPeakConsumerProjector.project(presentation)
        )

        #expect(projection.sessionID == sessionID)
        #expect(projection.selectedSource == .scooterBluetooth)
        #expect(projection.state == .qualifiedObservedMaximum(metersPerSecond: 6))
        #expect(projection.state.speedMetersPerSecond == 6)
        #expect(projection.state.permitsObservedMaximumWording)
        #expect(!projection.state.requiresQualityDisclosure)
    }

    @Test("accepted zero remains subordinate evidence and never maximum wording")
    func acceptedZero() throws {
        let presentation = try RideHistoryObservedPeakPresenter.present(
            joined(try bluetoothFixture(speeds: [0, 0, 0]))
        )
        let projection = try #require(
            RideHistoryObservedPeakConsumerProjector.project(presentation)
        )

        #expect(projection.state == .acceptedObservation(metersPerSecond: 0))
        #expect(projection.state.speedMetersPerSecond == 0)
        #expect(!projection.state.permitsObservedMaximumWording)
        #expect(projection.state.requiresQualityDisclosure)
    }

    @Test("missing peak exposes no numeric value or maximum wording")
    func missingPeak() throws {
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
        let projection = try #require(
            RideHistoryObservedPeakConsumerProjector.project(presentation)
        )

        #expect(projection.state == .unavailable)
        #expect(projection.state.speedMetersPerSecond == nil)
        #expect(!projection.state.permitsObservedMaximumWording)
        #expect(!projection.state.requiresQualityDisclosure)
    }

    private func bluetoothFixture(speeds: [Double]) throws -> Fixture {
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

        let snapshot = accumulator.snapshot
        let readiness = snapshot.observedPeakReadiness(using: try bluetoothPolicy())
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
        metersPerSecond: Double,
        uptime: UInt64
    ) throws -> SpeedTelemetrySample {
        let receivedAt = epoch.addingTimeInterval(Double(uptime) / 1_000_000_000)
        return try SpeedTelemetrySample(
            source: .scooterBluetooth,
            provenance: .absoluteMeasurement,
            metersPerSecond: metersPerSecond,
            receivedAtUptimeNanoseconds: uptime,
            receivedAtDate: receivedAt
        )
    }

    private func bluetoothPolicy() throws -> RideObservedPeakQualityPolicy {
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
}
