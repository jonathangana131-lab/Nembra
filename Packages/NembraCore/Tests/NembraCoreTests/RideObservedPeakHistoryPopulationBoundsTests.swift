import Foundation
import Testing

@testable import NembraCore

@Suite("Observed peak history population bounds")
struct RideObservedPeakHistoryPopulationBoundsTests {
    private let sessionID = UUID(uuidString: "98765432-1111-2222-3333-444455556666")!
    private let epoch = Date(timeIntervalSinceReferenceDate: 70_000)

    @Test("interval jitter above half the retained range is impossible")
    func impossibleIntervalPopulationDeviationRejected() throws {
        let evidence = try bluetoothEvidence()
        let data = try mutatedJSON(evidence) { root in
            var benchmark = root["telemetryBenchmark"] as! [String: Any]

            // Two intervals with min=100 ms, max=300 ms, mean=200 ms and
            // duration=400 ms are otherwise algebraically consistent. A
            // population SD of 150 ms is impossible because Popoviciu caps it at
            // (300 - 100) / 2 = 100 ms. The old full-range check admitted 150.
            benchmark["observedDurationSeconds"] = 0.4
            benchmark["effectiveSampleRateHertz"] = 5.0
            benchmark["meanIntervalMilliseconds"] = 200.0
            benchmark["minimumIntervalMilliseconds"] = 100.0
            benchmark["maximumIntervalMilliseconds"] = 300.0
            benchmark["intervalJitterStandardDeviationMilliseconds"] = 150.0
            root["telemetryBenchmark"] = benchmark
        }

        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(RideObservedPeakHistoryEvidence.self, from: data)
        }
    }

    @Test("delivery latency deviation above half the retained range is impossible")
    func impossibleLatencyPopulationDeviationRejected() throws {
        let evidence = try gpsNoPeakEvidence()
        let data = try mutatedJSON(evidence) { root in
            var benchmark = root["telemetryBenchmark"] as! [String: Any]

            // Three retained latency samples with min=10 ms and max=90 ms can
            // never have population SD > 40 ms. Keep the mean centered and use
            // 60 ms so every ordinary min/mean/max shape check passes while the
            // old full-range (80 ms) bound would have accepted the aggregate.
            benchmark["meanDeliveryLatencyMilliseconds"] = 50.0
            benchmark["minimumDeliveryLatencyMilliseconds"] = 10.0
            benchmark["maximumDeliveryLatencyMilliseconds"] = 90.0
            benchmark["deliveryLatencyStandardDeviationMilliseconds"] = 60.0
            root["telemetryBenchmark"] = benchmark
        }

        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(RideObservedPeakHistoryEvidence.self, from: data)
        }
    }

    private func bluetoothEvidence() throws -> RideObservedPeakHistoryEvidence {
        let ride = try completedRide()
        var accumulator = RideSpeedEvidenceSessionAccumulator(
            sessionID: sessionID,
            peakPolicy: try PeakSpeedPolicy(source: .scooterBluetooth)
        )

        for (index, speed) in [3.0, 6.0, 5.0].enumerated() {
            _ = accumulator.record(try sample(
                source: .scooterBluetooth,
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

        return try RideObservedPeakHistoryEvidence(
            completedRide: ride,
            completedPeak: completedPeak,
            readiness: readiness
        )
    }

    private func gpsNoPeakEvidence() throws -> RideObservedPeakHistoryEvidence {
        let ride = try completedRide()
        var accumulator = RideSpeedEvidenceSessionAccumulator(
            sessionID: sessionID,
            peakPolicy: try PeakSpeedPolicy(
                source: .gps,
                maximumSpeedAccuracyMetersPerSecond: 0.5
            )
        )

        for index in 1...3 {
            _ = accumulator.record(try sample(
                source: .gps,
                metersPerSecond: Double(index),
                uptime: UInt64(index) * 100_000_000,
                speedAccuracy: 0.8
            ))
        }

        let snapshot = accumulator.snapshot
        #expect(snapshot.peakEvidence == nil)
        let readiness = snapshot.observedPeakReadiness(using: try gpsPolicy())
        return try RideObservedPeakHistoryEvidence(
            completedRide: ride,
            completedPeak: nil,
            readiness: readiness
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
        source: SpeedTelemetrySource,
        metersPerSecond: Double,
        uptime: UInt64,
        speedAccuracy: Double? = nil
    ) throws -> SpeedTelemetrySample {
        let receivedAt = epoch.addingTimeInterval(Double(uptime) / 1_000_000_000)
        return try SpeedTelemetrySample(
            source: source,
            provenance: .absoluteMeasurement,
            metersPerSecond: metersPerSecond,
            receivedAtUptimeNanoseconds: uptime,
            receivedAtDate: receivedAt,
            measurementDate: source == .gps ? receivedAt.addingTimeInterval(-0.05) : nil,
            speedAccuracyMetersPerSecond: speedAccuracy
        )
    }

    private func bluetoothPolicy() throws -> RideObservedPeakQualityPolicy {
        try RideObservedPeakQualityPolicy(
            telemetry: SpeedTelemetryQualityPolicy(
                requiredSource: .scooterBluetooth,
                minimumAcceptedSampleCount: 3,
                maximumRejectedSampleFraction: 0,
                maximumMeanIntervalMilliseconds: 500,
                maximumObservedIntervalMilliseconds: 500,
                maximumJitterStandardDeviationMilliseconds: 500,
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
                maximumMeanIntervalMilliseconds: 500,
                maximumObservedIntervalMilliseconds: 500,
                maximumJitterStandardDeviationMilliseconds: 500,
                minimumDeliveryLatencySampleFraction: 1,
                maximumMeanDeliveryLatencyMilliseconds: 500,
                maximumEmpiricalSpeedStepKilometersPerHour: 100
            )
        )
    }

    private func mutatedJSON(
        _ evidence: RideObservedPeakHistoryEvidence,
        mutate: (inout [String: Any]) -> Void
    ) throws -> Data {
        let data = try JSONEncoder().encode(evidence)
        var root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        mutate(&root)
        return try JSONSerialization.data(withJSONObject: root)
    }
}
