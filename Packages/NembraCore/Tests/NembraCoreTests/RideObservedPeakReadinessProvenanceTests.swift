import Foundation
import Testing

@testable import NembraCore

@Suite("Observed peak readiness audit provenance")
struct RideObservedPeakReadinessProvenanceTests {
    private let sessionID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    private let epoch = Date(timeIntervalSinceReferenceDate: 10_000)

    private func sample(
        source: SpeedTelemetrySource = .scooterBluetooth,
        metersPerSecond: Double,
        uptime: UInt64,
        speedAccuracy: Double? = nil
    ) throws -> SpeedTelemetrySample {
        try SpeedTelemetrySample(
            source: source,
            provenance: .absoluteMeasurement,
            metersPerSecond: metersPerSecond,
            receivedAtUptimeNanoseconds: uptime,
            receivedAtDate: epoch,
            speedAccuracyMetersPerSecond: speedAccuracy
        )
    }

    private func policy() throws -> RideObservedPeakQualityPolicy {
        try RideObservedPeakQualityPolicy(
            telemetry: SpeedTelemetryQualityPolicy(
                requiredSource: .scooterBluetooth,
                minimumAcceptedSampleCount: 3,
                maximumRejectedSampleFraction: 0.5,
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
        #expect(!readiness.beganAfterKnownObservationGap)
        #expect(readiness.knownSelectedSourceInterruptionCount == 0)
        #expect(readiness.foreignSourceCallbackCount == 0)
        #expect(readiness.peakRejections == snapshot.peakRejections)
        #expect(readiness.peakRejections.totalRejectedSampleCount == 0)
        #expect(readiness.peakEvidence == snapshot.peakEvidence)
        #expect(readiness.telemetryBenchmark == snapshot.telemetryBenchmark)
        #expect(readiness.policy == qualityPolicy)
        #expect(readiness.telemetryQuality.source == .scooterBluetooth)
        #expect(readiness.telemetryQuality.isQualified)
    }

    @Test("failed readiness retains initial-gap and foreign-source provenance even without a peak")
    func failedDecisionDoesNotDropSessionTopologyWhenPeakIsUnavailable() throws {
        var session = RideSpeedEvidenceSessionAccumulator(
            sessionID: sessionID,
            peakPolicy: try PeakSpeedPolicy(source: .scooterBluetooth),
            beginsAfterKnownObservationGap: true
        )

        // Foreign GPS evidence cannot establish a scooter-BLE peak. Keep it as
        // source-mixing provenance even though no selected-source peak exists.
        _ = session.record(try sample(
            source: .gps,
            metersPerSecond: 8,
            uptime: 100_000_000,
            speedAccuracy: 0.2
        ))

        let snapshot = session.snapshot
        let qualityPolicy = try policy()
        let readiness = snapshot.observedPeakReadiness(using: qualityPolicy)

        #expect(snapshot.peakEvidence == nil)
        #expect(snapshot.beganAfterKnownObservationGap)
        #expect(snapshot.knownSelectedSourceInterruptionCount == 1)
        #expect(snapshot.foreignSourceCallbackCount == 1)
        #expect(snapshot.peakRejections.sourceMismatchSampleCount == 1)
        #expect(!readiness.isReady)
        #expect(readiness.sessionID == snapshot.sessionID)
        #expect(readiness.source == snapshot.source)
        #expect(readiness.beganAfterKnownObservationGap)
        #expect(readiness.knownSelectedSourceInterruptionCount == 1)
        #expect(readiness.foreignSourceCallbackCount == 1)
        #expect(readiness.peakRejections == snapshot.peakRejections)
        #expect(readiness.peakRejections.sourceMismatchSampleCount == 1)
        #expect(readiness.peakEvidence == nil)
        #expect(readiness.telemetryBenchmark == snapshot.telemetryBenchmark)
        #expect(readiness.policy == qualityPolicy)
        #expect(readiness.failures.contains(.peakUnavailable))
        #expect(readiness.failures.contains(.foreignSourceTraffic(callbackCount: 1)))
        #expect(readiness.failures.contains(
            .insufficientJitterIntervalEvidence(required: 2, actual: 0)
        ))
    }
}
