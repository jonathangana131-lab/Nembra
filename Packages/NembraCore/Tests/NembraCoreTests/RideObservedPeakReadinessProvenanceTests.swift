import Foundation
import Testing

@testable import NembraCore

@Suite("Observed peak readiness audit provenance")
struct RideObservedPeakReadinessProvenanceTests {
    private let sessionID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    private let epoch = Date(timeIntervalSinceReferenceDate: 10_000)

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

    private func policy() throws -> RideObservedPeakQualityPolicy {
        try RideObservedPeakQualityPolicy(
            telemetry: SpeedTelemetryQualityPolicy(
                requiredSource: .scooterBluetooth,
                minimumAcceptedSampleCount: 3,
                maximumRejectedSampleFraction: 0,
                maximumMeanIntervalMilliseconds: 150,
                maximumObservedIntervalMilliseconds: 200,
                maximumJitterStandardDeviationMilliseconds: 50,
                maximumEmpiricalSpeedStepKilometersPerHour: 10
            )
        )
    }

    @Test("readiness retains the exact same-ride benchmark and policy used to decide")
    func decisionCannotLoseItsEvidenceOrThresholdProvenance() throws {
        var session = RideSpeedEvidenceSessionAccumulator(
            sessionID: sessionID,
            peakPolicy: try PeakSpeedPolicy(source: .scooterBluetooth)
        )
        _ = session.record(try sample(metersPerSecond: 1, uptime: 100_000_000))
        _ = session.record(try sample(metersPerSecond: 2, uptime: 200_000_000))
        _ = session.record(try sample(metersPerSecond: 3, uptime: 300_000_000))

        let snapshot = session.snapshot
        let qualityPolicy = try policy()
        let readiness = snapshot.observedPeakReadiness(using: qualityPolicy)

        #expect(readiness.isReady)
        #expect(readiness.sessionID == snapshot.sessionID)
        #expect(readiness.source == snapshot.source)
        #expect(readiness.peakEvidence == snapshot.peakEvidence)
        #expect(readiness.telemetryBenchmark == snapshot.telemetryBenchmark)
        #expect(readiness.policy == qualityPolicy)
        #expect(readiness.telemetryQuality.source == .scooterBluetooth)
        #expect(readiness.telemetryQuality.isQualified)
    }
}
