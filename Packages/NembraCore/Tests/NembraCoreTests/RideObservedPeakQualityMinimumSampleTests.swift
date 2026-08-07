import Foundation
import Testing

@testable import NembraCore

@Suite("Observed peak quality minimum sample evidence")
struct RideObservedPeakQualityMinimumSampleTests {
    private let sessionID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    private let epoch = Date(timeIntervalSinceReferenceDate: 10_000)

    private func telemetryPolicy(minimumAcceptedSampleCount: Int) throws -> SpeedTelemetryQualityPolicy {
        try SpeedTelemetryQualityPolicy(
            requiredSource: .scooterBluetooth,
            minimumAcceptedSampleCount: minimumAcceptedSampleCount,
            maximumRejectedSampleFraction: 0,
            maximumMeanIntervalMilliseconds: 150,
            maximumObservedIntervalMilliseconds: 200,
            maximumJitterStandardDeviationMilliseconds: 50,
            maximumEmpiricalSpeedStepKilometersPerHour: 10
        )
    }

    private func sample(
        metersPerSecond: Double,
        uptime: UInt64
    ) throws -> SpeedTelemetrySample {
        try SpeedTelemetrySample(
            source: .scooterBluetooth,
            provenance: .absoluteMeasurement,
            metersPerSecond: metersPerSecond,
            receivedAtUptimeNanoseconds: uptime,
            receivedAtDate: epoch
        )
    }

    @Test("one accepted sample cannot establish jitter evidence")
    func oneAcceptedSampleRejected() throws {
        #expect(
            throws: RideObservedPeakQualityPolicyError
                .minimumAcceptedSampleCountInsufficientForJitter(required: 3, actual: 1)
        ) {
            try RideObservedPeakQualityPolicy(
                telemetry: telemetryPolicy(minimumAcceptedSampleCount: 1)
            )
        }
    }

    @Test("one timing interval cannot establish jitter evidence")
    func twoAcceptedSamplesRejected() throws {
        #expect(
            throws: RideObservedPeakQualityPolicyError
                .minimumAcceptedSampleCountInsufficientForJitter(required: 3, actual: 2)
        ) {
            try RideObservedPeakQualityPolicy(
                telemetry: telemetryPolicy(minimumAcceptedSampleCount: 2)
            )
        }
    }

    @Test("three accepted samples are the structural minimum for two intervals")
    func threeAcceptedSamplesAccepted() throws {
        let policy = try RideObservedPeakQualityPolicy(
            telemetry: telemetryPolicy(minimumAcceptedSampleCount: 3)
        )
        #expect(policy.telemetry.minimumAcceptedSampleCount == 3)
    }

    @Test("three accepted samples split by a gap cannot masquerade as two jitter intervals")
    func knownGapCanStillLeaveInsufficientJitterIntervals() throws {
        var session = RideSpeedEvidenceSessionAccumulator(
            sessionID: sessionID,
            peakPolicy: try PeakSpeedPolicy(source: .scooterBluetooth)
        )

        _ = session.record(try sample(metersPerSecond: 1, uptime: 100_000_000))
        _ = session.record(try sample(metersPerSecond: 2, uptime: 200_000_000))
        session.recordInterruption(.selectedSourceUnavailable)
        _ = session.record(try sample(metersPerSecond: 3, uptime: 300_000_000))

        let policy = try RideObservedPeakQualityPolicy(
            telemetry: telemetryPolicy(minimumAcceptedSampleCount: 3)
        )
        let readiness = session.snapshot.observedPeakReadiness(using: policy)

        #expect(session.snapshot.telemetryBenchmark.acceptedSampleCount == 3)
        #expect(session.snapshot.telemetryBenchmark.intervalCount == 1)
        #expect(readiness.telemetryQuality.isQualified)
        #expect(!readiness.isReady)
        #expect(readiness.failures.contains(.partialPeakObservation))
        #expect(readiness.failures.contains(
            .insufficientJitterIntervalEvidence(required: 2, actual: 1)
        ))
    }
}
