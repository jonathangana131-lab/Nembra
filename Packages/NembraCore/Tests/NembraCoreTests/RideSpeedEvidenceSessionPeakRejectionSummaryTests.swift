import Foundation
import Testing

@testable import NembraCore

@Suite("Ride speed evidence peak rejection summary")
struct RideSpeedEvidenceSessionPeakRejectionSummaryTests {
    private let sessionID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    private let epoch = Date(timeIntervalSinceReferenceDate: 10_000)

    private func absoluteSample(
        source: SpeedTelemetrySource,
        metersPerSecond: Double,
        uptime: UInt64,
        accuracy: Double? = nil
    ) throws -> SpeedTelemetrySample {
        try SpeedTelemetrySample(
            source: source,
            provenance: .absoluteMeasurement,
            metersPerSecond: metersPerSecond,
            receivedAtUptimeNanoseconds: uptime,
            receivedAtDate: epoch,
            speedAccuracyMetersPerSecond: accuracy
        )
    }

    @Test("all-rejected GPS peak retains accuracy-rejection provenance before any peak exists")
    func noPeakDoesNotErasePeakSpecificAccuracyRejections() throws {
        var session = RideSpeedEvidenceSessionAccumulator(
            sessionID: sessionID,
            peakPolicy: try PeakSpeedPolicy(
                source: .gps,
                maximumSpeedAccuracyMetersPerSecond: 0.5
            )
        )

        for index in 1...3 {
            let result = session.record(try absoluteSample(
                source: .gps,
                metersPerSecond: Double(index),
                uptime: UInt64(index) * 100_000_000,
                accuracy: 0.8
            ))
            #expect(result.benchmark == .accepted)
            #expect(
                result.peak == .rejected(
                    .speedAccuracyExceeded(maximum: 0.5, actual: 0.8)
                )
            )
        }

        let snapshot = session.snapshot
        #expect(snapshot.peakEvidence == nil)
        #expect(snapshot.telemetryBenchmark.acceptedSampleCount == 3)
        #expect(snapshot.telemetryBenchmark.rejectedSampleCount == 0)
        #expect(snapshot.peakRejections.speedAccuracyExceededCount == 3)
        #expect(snapshot.peakRejections.selectedSourceQualityRejectedSampleCount == 3)
        #expect(snapshot.peakRejections.totalRejectedSampleCount == 3)
        #expect(snapshot.peakRejections.nonAuthoritativeSampleCount == 0)
        #expect(snapshot.peakRejections.sourceMismatchSampleCount == 0)
    }

    @Test("foreign authoritative and motion-assist callbacks retain distinct peak rejection reasons")
    func foreignTrafficDoesNotCollapsePeakRejectionCauses() throws {
        var session = RideSpeedEvidenceSessionAccumulator(
            sessionID: sessionID,
            peakPolicy: try PeakSpeedPolicy(source: .scooterBluetooth)
        )

        let foreignGPS = session.record(try absoluteSample(
            source: .gps,
            metersPerSecond: 8,
            uptime: 100,
            accuracy: 0.2
        ))
        #expect(foreignGPS.benchmark == .rejected(.sourceMismatch))
        #expect(foreignGPS.peak == .rejected(.sourceMismatch))

        let motionAssist = try SpeedTelemetrySample(
            source: .motionAssist,
            provenance: .shortHorizonEstimate,
            metersPerSecond: 9,
            receivedAtUptimeNanoseconds: 200,
            receivedAtDate: epoch
        )
        let motionResult = session.record(motionAssist)
        #expect(motionResult.benchmark == .rejected(.sourceMismatch))
        #expect(motionResult.peak == .rejected(.nonAuthoritativeSample))

        let snapshot = session.snapshot
        #expect(snapshot.foreignSourceCallbackCount == 2)
        #expect(snapshot.peakRejections.sourceMismatchSampleCount == 1)
        #expect(snapshot.peakRejections.nonAuthoritativeSampleCount == 1)
        #expect(snapshot.peakRejections.totalRejectedSampleCount == 2)
        #expect(snapshot.peakRejections.selectedSourceQualityRejectedSampleCount == 0)
    }

    @Test("published peak quality-rejection count matches session summary")
    func acceptedPeakCrossChecksSelectedSourceQualityRejections() throws {
        var session = RideSpeedEvidenceSessionAccumulator(
            sessionID: sessionID,
            peakPolicy: try PeakSpeedPolicy(
                source: .gps,
                maximumSpeedAccuracyMetersPerSecond: 0.5
            )
        )

        _ = session.record(try absoluteSample(
            source: .gps,
            metersPerSecond: 8,
            uptime: 100,
            accuracy: 0.8
        ))
        _ = session.record(try absoluteSample(
            source: .gps,
            metersPerSecond: 6,
            uptime: 200,
            accuracy: 0.4
        ))

        let snapshot = session.snapshot
        let peak = try #require(snapshot.peakEvidence)
        #expect(peak.peakEvidence.qualityRejectedSampleCount == 1)
        #expect(snapshot.peakRejections.selectedSourceQualityRejectedSampleCount == 1)
        #expect(snapshot.peakRejections.speedAccuracyExceededCount == 1)
    }

    @Test("readiness retains rejection summary even when peak is unavailable")
    func readinessCarriesNoPeakRejectionAudit() throws {
        var session = RideSpeedEvidenceSessionAccumulator(
            sessionID: sessionID,
            peakPolicy: try PeakSpeedPolicy(
                source: .gps,
                maximumSpeedAccuracyMetersPerSecond: 0.5
            )
        )

        for index in 1...3 {
            let receivedAt = epoch.addingTimeInterval(Double(index) / 10)
            let sample = try SpeedTelemetrySample(
                source: .gps,
                provenance: .absoluteMeasurement,
                metersPerSecond: Double(index),
                receivedAtUptimeNanoseconds: UInt64(index) * 100_000_000,
                receivedAtDate: receivedAt,
                measurementDate: receivedAt.addingTimeInterval(-0.05),
                speedAccuracyMetersPerSecond: 0.8
            )
            _ = session.record(sample)
        }

        let policy = try RideObservedPeakQualityPolicy(
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
        let readiness = session.snapshot.observedPeakReadiness(using: policy)

        #expect(!readiness.isReady)
        #expect(readiness.peakEvidence == nil)
        #expect(readiness.telemetryQuality.isQualified)
        #expect(readiness.peakRejections.speedAccuracyExceededCount == 3)
        #expect(readiness.peakRejections.selectedSourceQualityRejectedSampleCount == 3)
        #expect(readiness.failures.contains(.peakUnavailable))
    }
}
