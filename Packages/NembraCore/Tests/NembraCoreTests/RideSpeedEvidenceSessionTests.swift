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

    private func bluetoothQualityPolicy(
        minimumAcceptedSamples: Int = 3,
        maximumRejectedFraction: Double = 0,
        maximumMeanIntervalMilliseconds: Double = 150,
        maximumObservedIntervalMilliseconds: Double = 200,
        maximumJitterMilliseconds: Double = 50,
        maximumSpeedStepKPH: Double = 10
    ) throws -> RideObservedPeakQualityPolicy {
        try RideObservedPeakQualityPolicy(
            telemetry: SpeedTelemetryQualityPolicy(
                requiredSource: .scooterBluetooth,
                minimumAcceptedSampleCount: minimumAcceptedSamples,
                maximumRejectedSampleFraction: maximumRejectedFraction,
                maximumMeanIntervalMilliseconds: maximumMeanIntervalMilliseconds,
                maximumObservedIntervalMilliseconds: maximumObservedIntervalMilliseconds,
                maximumJitterStandardDeviationMilliseconds: maximumJitterMilliseconds,
                maximumEmpiricalSpeedStepKilometersPerHour: maximumSpeedStepKPH
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
                maximumEmpiricalSpeedStepKilometersPerHour: 10
            )
        )
    }

    @Test("same callbacks mechanically produce same-ride peak and benchmark evidence")
    func sameRideEvidenceStaysBound() throws {
        var session = RideSpeedEvidenceSessionAccumulator(
            sessionID: sessionID,
            peakPolicy: try PeakSpeedPolicy(source: .scooterBluetooth)
        )

        _ = session.record(try sample(metersPerSecond: 1, uptime: 100_000_000))
        _ = session.record(try sample(metersPerSecond: 2, uptime: 200_000_000))
        _ = session.record(try sample(metersPerSecond: 3, uptime: 300_000_000))

        let snapshot = session.snapshot
        let peak = try #require(snapshot.peakEvidence)
        #expect(snapshot.sessionID == sessionID)
        #expect(snapshot.source == .scooterBluetooth)
        #expect(peak.sessionID == sessionID)
        #expect(peak.policy.source == snapshot.telemetryBenchmark.source)
        #expect(peak.peakEvidence.peak.metersPerSecond == 3)
        #expect(snapshot.telemetryBenchmark.acceptedSampleCount == 3)
        #expect(snapshot.telemetryBenchmark.intervalCount == 2)
    }

    @Test("explicit complete quality requirements can make clean BLE peak ready")
    func cleanBluetoothPeakCanQualify() throws {
        var session = RideSpeedEvidenceSessionAccumulator(
            sessionID: sessionID,
            peakPolicy: try PeakSpeedPolicy(source: .scooterBluetooth)
        )

        _ = session.record(try sample(metersPerSecond: 1, uptime: 100_000_000))
        _ = session.record(try sample(metersPerSecond: 2, uptime: 200_000_000))
        _ = session.record(try sample(metersPerSecond: 3, uptime: 300_000_000))

        let readiness = session.snapshot.observedPeakReadiness(
            using: try bluetoothQualityPolicy()
        )
        #expect(readiness.isReady)
        #expect(readiness.failures.isEmpty)
        #expect(readiness.telemetryQuality.isQualified)
        #expect(readiness.peakEvidence?.peakEvidence.peak.metersPerSecond == 3)
    }

    @Test("known interruption keeps segmented benchmark useful but makes peak unreportable")
    func interruptionDisqualifiesPeakWithoutFabricatingBenchmarkInterval() throws {
        var session = RideSpeedEvidenceSessionAccumulator(
            sessionID: sessionID,
            peakPolicy: try PeakSpeedPolicy(source: .scooterBluetooth)
        )

        _ = session.record(try sample(metersPerSecond: 1, uptime: 100_000_000))
        _ = session.record(try sample(metersPerSecond: 2, uptime: 200_000_000))
        session.recordInterruption(.vehicleConnectionLost)
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
            using: try bluetoothQualityPolicy(minimumAcceptedSamples: 4)
        )
        #expect(!readiness.isReady)
        #expect(readiness.telemetryQuality.isQualified)
        #expect(readiness.failures == [.partialPeakObservation])
    }

    @Test("initial recovery gap is not hidden just because benchmark starts cleanly")
    func initialObservationGapDisqualifiesPeak() throws {
        var session = RideSpeedEvidenceSessionAccumulator(
            sessionID: sessionID,
            peakPolicy: try PeakSpeedPolicy(source: .scooterBluetooth),
            beginsAfterKnownObservationGap: true
        )

        _ = session.record(try sample(metersPerSecond: 1, uptime: 100_000_000))
        _ = session.record(try sample(metersPerSecond: 2, uptime: 200_000_000))
        _ = session.record(try sample(metersPerSecond: 3, uptime: 300_000_000))

        let snapshot = session.snapshot
        #expect(snapshot.beganAfterKnownObservationGap)
        #expect(snapshot.telemetryBenchmark.knownObservationInterruptionCount == 0)
        #expect(snapshot.peakEvidence?.beganAfterKnownObservationGap == true)
        #expect(snapshot.peakEvidence?.peakEvidence.continuity == .partialSelectedSourceEvidence)

        let readiness = snapshot.observedPeakReadiness(
            using: try bluetoothQualityPolicy()
        )
        #expect(!readiness.isReady)
        #expect(readiness.telemetryQuality.isQualified)
        #expect(readiness.failures == [.partialPeakObservation])
    }

    @Test("peak-specific GPS accuracy rejection cannot be hidden by clean raw benchmark")
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

        let readiness = snapshot.observedPeakReadiness(using: try gpsQualityPolicy())
        #expect(!readiness.isReady)
        #expect(readiness.telemetryQuality.isQualified)
        #expect(readiness.failures == [.partialPeakObservation])
    }

    @Test("GPS peak cannot be ready without an explicit peak accuracy ceiling")
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

        let readiness = session.snapshot.observedPeakReadiness(using: try gpsQualityPolicy())
        #expect(!readiness.isReady)
        #expect(readiness.telemetryQuality.isQualified)
        #expect(readiness.failures == [.gpsPeakAccuracyPolicyUnavailable])
    }

    @Test("benchmark quality failure keeps otherwise clean peak unavailable for reporting")
    func weakCadenceFailsReadiness() throws {
        var session = RideSpeedEvidenceSessionAccumulator(
            sessionID: sessionID,
            peakPolicy: try PeakSpeedPolicy(source: .scooterBluetooth)
        )

        _ = session.record(try sample(metersPerSecond: 1, uptime: 100_000_000))
        _ = session.record(try sample(metersPerSecond: 2, uptime: 500_000_000))
        _ = session.record(try sample(metersPerSecond: 3, uptime: 900_000_000))

        let readiness = session.snapshot.observedPeakReadiness(
            using: try bluetoothQualityPolicy(
                maximumMeanIntervalMilliseconds: 150,
                maximumObservedIntervalMilliseconds: 200
            )
        )
        #expect(!readiness.isReady)
        #expect(!readiness.telemetryQuality.isQualified)
        #expect(readiness.failures.count == 1)
        guard case let .telemetryQualityFailed(failures) = readiness.failures[0] else {
            Issue.record("Expected telemetry-quality failure")
            return
        }
        #expect(failures.contains(.meanIntervalExceeded(
            maximumMilliseconds: 150,
            actualMilliseconds: 400
        )))
        #expect(failures.contains(.observedIntervalExceeded(
            maximumMilliseconds: 200,
            actualMilliseconds: 400
        )))
    }

    @Test("all GPS benchmark samples may be valid while no peak sample passes GPS accuracy")
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

        let readiness = session.snapshot.observedPeakReadiness(using: try gpsQualityPolicy())
        #expect(!readiness.isReady)
        #expect(readiness.telemetryQuality.isQualified)
        #expect(readiness.failures == [.peakUnavailable])
    }

    @Test("foreign-source callback reaches both collectors and cannot silently disappear")
    func foreignSourceTrafficIsVisibleToBenchmarkQuality() throws {
        var session = RideSpeedEvidenceSessionAccumulator(
            sessionID: sessionID,
            peakPolicy: try PeakSpeedPolicy(source: .scooterBluetooth)
        )

        let foreignResult = session.record(try sample(
            source: .gps,
            metersPerSecond: 20,
            uptime: 50_000_000,
            speedAccuracy: 0.2,
            latencyMilliseconds: 20
        ))
        #expect(foreignResult.peak == .rejected(.sourceMismatch))
        #expect(foreignResult.benchmark == .rejected(.sourceMismatch))

        _ = session.record(try sample(metersPerSecond: 1, uptime: 100_000_000))
        _ = session.record(try sample(metersPerSecond: 2, uptime: 200_000_000))
        _ = session.record(try sample(metersPerSecond: 3, uptime: 300_000_000))

        let readiness = session.snapshot.observedPeakReadiness(
            using: try bluetoothQualityPolicy(maximumRejectedFraction: 0)
        )
        #expect(!readiness.isReady)
        #expect(session.snapshot.peakEvidence?.peakEvidence.continuity == .noRecordedSelectedSourceEvidenceLoss)
        #expect(session.snapshot.telemetryBenchmark.rejectedSampleCount == 1)
        #expect(!readiness.telemetryQuality.isQualified)
    }

    @Test("peak quality wrapper refuses policies that silently omit required evidence dimensions")
    func incompleteFeaturePolicyIsRejected() throws {
        let weak = try SpeedTelemetryQualityPolicy(
            requiredSource: .scooterBluetooth,
            minimumAcceptedSampleCount: 1
        )

        #expect(throws: RideObservedPeakQualityPolicyError.rejectedFractionRequirementRequired) {
            try RideObservedPeakQualityPolicy(telemetry: weak)
        }
    }

    @Test("feature policy requires an explicit authoritative source")
    func explicitSourceRequirementIsMandatory() throws {
        let sourceAgnostic = try SpeedTelemetryQualityPolicy(
            minimumAcceptedSampleCount: 3,
            maximumRejectedSampleFraction: 0,
            maximumMeanIntervalMilliseconds: 150,
            maximumObservedIntervalMilliseconds: 200,
            maximumJitterStandardDeviationMilliseconds: 50,
            maximumEmpiricalSpeedStepKilometersPerHour: 10
        )

        #expect(throws: RideObservedPeakQualityPolicyError.sourceRequirementRequired) {
            try RideObservedPeakQualityPolicy(telemetry: sourceAgnostic)
        }
    }

    @Test("GPS feature policy requires explicit latency coverage and limit")
    func gpsLatencyEvidenceRequirementsCannotBeOmitted() throws {
        let missingCoverage = try SpeedTelemetryQualityPolicy(
            requiredSource: .gps,
            minimumAcceptedSampleCount: 3,
            maximumRejectedSampleFraction: 0,
            maximumMeanIntervalMilliseconds: 150,
            maximumObservedIntervalMilliseconds: 200,
            maximumJitterStandardDeviationMilliseconds: 50,
            maximumMeanDeliveryLatencyMilliseconds: 100,
            maximumEmpiricalSpeedStepKilometersPerHour: 10
        )
        #expect(throws: RideObservedPeakQualityPolicyError.gpsLatencyCoverageRequirementRequired) {
            try RideObservedPeakQualityPolicy(telemetry: missingCoverage)
        }

        let missingLimit = try SpeedTelemetryQualityPolicy(
            requiredSource: .gps,
            minimumAcceptedSampleCount: 3,
            maximumRejectedSampleFraction: 0,
            maximumMeanIntervalMilliseconds: 150,
            maximumObservedIntervalMilliseconds: 200,
            maximumJitterStandardDeviationMilliseconds: 50,
            minimumDeliveryLatencySampleFraction: 1,
            maximumEmpiricalSpeedStepKilometersPerHour: 10
        )
        #expect(throws: RideObservedPeakQualityPolicyError.gpsLatencyRequirementRequired) {
            try RideObservedPeakQualityPolicy(telemetry: missingLimit)
        }
    }
}
