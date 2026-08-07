import Foundation
import Testing

@testable import NembraCore

@Suite("Ride-owned speed evidence session")
struct RideSpeedEvidenceSessionTests {
    private let sessionID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    private let epoch = Date(timeIntervalSinceReferenceDate: 10_000)

    private func sample(
        source: SpeedTelemetrySource = .scooterBluetooth,
        metersPerSecond: Double,
        uptime: UInt64,
        speedAccuracy: Double? = nil,
        latencyMilliseconds: Double? = nil
    ) throws -> SpeedTelemetrySample {
        let receivedAt = epoch.addingTimeInterval(Double(uptime) / 1_000_000_000)
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

    private func bluetoothPolicy(
        minimumSamples: Int = 3,
        maximumMeanIntervalMilliseconds: Double = 150,
        maximumObservedIntervalMilliseconds: Double = 200
    ) throws -> RideObservedPeakQualityPolicy {
        try RideObservedPeakQualityPolicy(
            telemetry: SpeedTelemetryQualityPolicy(
                requiredSource: .scooterBluetooth,
                minimumAcceptedSampleCount: minimumSamples,
                maximumRejectedSampleFraction: 0,
                maximumMeanIntervalMilliseconds: maximumMeanIntervalMilliseconds,
                maximumObservedIntervalMilliseconds: maximumObservedIntervalMilliseconds,
                maximumJitterStandardDeviationMilliseconds: 50,
                maximumEmpiricalSpeedStepKilometersPerHour: 10
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
                maximumEmpiricalSpeedStepKilometersPerHour: 10
            )
        )
    }

    private func recordCleanBluetoothSamples(
        into session: inout RideSpeedEvidenceSessionAccumulator
    ) throws {
        _ = session.record(try sample(metersPerSecond: 1, uptime: 100_000_000))
        _ = session.record(try sample(metersPerSecond: 2, uptime: 200_000_000))
        _ = session.record(try sample(metersPerSecond: 3, uptime: 300_000_000))
    }

    @Test("clean callbacks mechanically bind peak and benchmark to one ride and source")
    func cleanEvidenceStaysBoundAndCanQualify() throws {
        var session = RideSpeedEvidenceSessionAccumulator(
            sessionID: sessionID,
            peakPolicy: try PeakSpeedPolicy(source: .scooterBluetooth)
        )
        try recordCleanBluetoothSamples(into: &session)

        let snapshot = session.snapshot
        let peak = try #require(snapshot.peakEvidence)
        #expect(snapshot.sessionID == sessionID)
        #expect(snapshot.source == .scooterBluetooth)
        #expect(peak.sessionID == sessionID)
        #expect(peak.policy.source == snapshot.telemetryBenchmark.source)
        #expect(peak.peakEvidence.peak.metersPerSecond == 3)
        #expect(snapshot.telemetryBenchmark.acceptedSampleCount == 3)
        #expect(snapshot.telemetryBenchmark.intervalCount == 2)

        let readiness = snapshot.observedPeakReadiness(using: try bluetoothPolicy())
        #expect(readiness.isReady)
        #expect(readiness.failures.isEmpty)
        #expect(readiness.telemetryQuality.isQualified)
    }

    @Test("selected-source unavailability segments benchmark and marks peak partial")
    func selectedSourceGapCannotBecomeSlowPacket() throws {
        var session = RideSpeedEvidenceSessionAccumulator(
            sessionID: sessionID,
            peakPolicy: try PeakSpeedPolicy(source: .scooterBluetooth)
        )
        _ = session.record(try sample(metersPerSecond: 1, uptime: 100_000_000))
        _ = session.record(try sample(metersPerSecond: 2, uptime: 200_000_000))
        session.recordInterruption(.selectedSourceUnavailable)
        _ = session.record(try sample(metersPerSecond: 3, uptime: 10_000_000_000))
        _ = session.record(try sample(metersPerSecond: 4, uptime: 10_100_000_000))

        let snapshot = session.snapshot
        #expect(snapshot.telemetryBenchmark.acceptedSampleCount == 4)
        #expect(snapshot.telemetryBenchmark.observationSegmentCount == 2)
        #expect(snapshot.telemetryBenchmark.knownObservationInterruptionCount == 1)
        #expect(snapshot.telemetryBenchmark.intervalCount == 2)
        #expect(snapshot.telemetryBenchmark.maximumIntervalMilliseconds == 100)
        #expect(snapshot.peakEvidence?.peakEvidence.continuity == .partialSelectedSourceEvidence)

        let readiness = snapshot.observedPeakReadiness(
            using: try bluetoothPolicy(minimumSamples: 4)
        )
        #expect(!readiness.isReady)
        #expect(readiness.telemetryQuality.isQualified)
        #expect(readiness.failures == [.partialPeakObservation])
    }

    @Test("application lifecycle interruption uses the same selected-stream truth boundary")
    func lifecycleGapMarksBothPipelines() throws {
        var session = RideSpeedEvidenceSessionAccumulator(
            sessionID: sessionID,
            peakPolicy: try PeakSpeedPolicy(source: .scooterBluetooth)
        )
        _ = session.record(try sample(metersPerSecond: 1, uptime: 100_000_000))
        session.recordInterruption(.applicationLifecycleInterrupted)
        _ = session.record(try sample(metersPerSecond: 2, uptime: 200_000_000))

        #expect(session.snapshot.telemetryBenchmark.knownObservationInterruptionCount == 1)
        #expect(session.snapshot.peakEvidence?.peakEvidence.knownInterruptionCount == 1)
        #expect(session.snapshot.peakEvidence?.peakEvidence.continuity == .partialSelectedSourceEvidence)
    }

    @Test("initial recovery gap remains visible even though first benchmark segment starts cleanly")
    func initialObservationGapDisqualifiesPeak() throws {
        var session = RideSpeedEvidenceSessionAccumulator(
            sessionID: sessionID,
            peakPolicy: try PeakSpeedPolicy(source: .scooterBluetooth),
            beginsAfterKnownObservationGap: true
        )
        try recordCleanBluetoothSamples(into: &session)

        let snapshot = session.snapshot
        #expect(snapshot.beganAfterKnownObservationGap)
        #expect(snapshot.telemetryBenchmark.knownObservationInterruptionCount == 0)
        #expect(snapshot.peakEvidence?.beganAfterKnownObservationGap == true)
        #expect(snapshot.peakEvidence?.peakEvidence.continuity == .partialSelectedSourceEvidence)

        let readiness = snapshot.observedPeakReadiness(using: try bluetoothPolicy())
        #expect(!readiness.isReady)
        #expect(readiness.telemetryQuality.isQualified)
        #expect(readiness.failures == [.partialPeakObservation])
    }

    @Test("GPS peak-specific accuracy rejection cannot be hidden by clean raw benchmark")
    func gpsAccuracyRejectionRemainsPeakFailure() throws {
        var session = RideSpeedEvidenceSessionAccumulator(
            sessionID: sessionID,
            peakPolicy: try PeakSpeedPolicy(
                source: .gps,
                maximumSpeedAccuracyMetersPerSecond: 0.5
            )
        )
        _ = session.record(try sample(
            source: .gps,
            metersPerSecond: 1,
            uptime: 100_000_000,
            speedAccuracy: 0.8,
            latencyMilliseconds: 50
        ))
        _ = session.record(try sample(
            source: .gps,
            metersPerSecond: 2,
            uptime: 200_000_000,
            speedAccuracy: 0.4,
            latencyMilliseconds: 50
        ))
        _ = session.record(try sample(
            source: .gps,
            metersPerSecond: 3,
            uptime: 300_000_000,
            speedAccuracy: 0.4,
            latencyMilliseconds: 50
        ))

        let snapshot = session.snapshot
        #expect(snapshot.telemetryBenchmark.acceptedSampleCount == 3)
        #expect(snapshot.telemetryBenchmark.rejectedSampleCount == 0)
        #expect(snapshot.peakEvidence?.peakEvidence.acceptedSampleCount == 2)
        #expect(snapshot.peakEvidence?.peakEvidence.qualityRejectedSampleCount == 1)

        let readiness = snapshot.observedPeakReadiness(using: try gpsPolicy())
        #expect(!readiness.isReady)
        #expect(readiness.telemetryQuality.isQualified)
        #expect(readiness.failures == [.partialPeakObservation])
    }

    @Test("GPS cannot qualify without an explicit peak speed-accuracy ceiling")
    func gpsPeakAccuracyPolicyIsRequired() throws {
        var session = RideSpeedEvidenceSessionAccumulator(
            sessionID: sessionID,
            peakPolicy: try PeakSpeedPolicy(source: .gps)
        )
        for index in 1...3 {
            _ = session.record(try sample(
                source: .gps,
                metersPerSecond: Double(index),
                uptime: UInt64(index) * 100_000_000,
                speedAccuracy: 0.4,
                latencyMilliseconds: 50
            ))
        }

        let readiness = session.snapshot.observedPeakReadiness(using: try gpsPolicy())
        #expect(!readiness.isReady)
        #expect(readiness.telemetryQuality.isQualified)
        #expect(readiness.failures == [.gpsPeakAccuracyPolicyUnavailable])
    }

    @Test("weak cadence fails even when the numeric peak itself is clean")
    func weakCadenceFailsReadiness() throws {
        var session = RideSpeedEvidenceSessionAccumulator(
            sessionID: sessionID,
            peakPolicy: try PeakSpeedPolicy(source: .scooterBluetooth)
        )
        _ = session.record(try sample(metersPerSecond: 1, uptime: 100_000_000))
        _ = session.record(try sample(metersPerSecond: 2, uptime: 500_000_000))
        _ = session.record(try sample(metersPerSecond: 3, uptime: 900_000_000))

        let readiness = session.snapshot.observedPeakReadiness(
            using: try bluetoothPolicy(
                maximumMeanIntervalMilliseconds: 150,
                maximumObservedIntervalMilliseconds: 200
            )
        )
        #expect(!readiness.isReady)
        #expect(!readiness.telemetryQuality.isQualified)
        #expect(readiness.failures.contains { failure in
            if case .telemetryQualityFailed = failure { return true }
            return false
        })
    }

    @Test("raw GPS benchmark may qualify while peak is unavailable after all accuracy rejections")
    func noAcceptedPeakFailsSeparatelyFromBenchmarkQuality() throws {
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
                speedAccuracy: 0.8,
                latencyMilliseconds: 50
            ))
        }

        let readiness = session.snapshot.observedPeakReadiness(using: try gpsPolicy())
        #expect(!readiness.isReady)
        #expect(readiness.telemetryQuality.isQualified)
        #expect(readiness.failures == [.peakUnavailable])
    }
}
