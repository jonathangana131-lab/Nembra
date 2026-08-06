import Foundation
import Testing
@testable import NembraCore

@Suite("Observed peak-speed evidence")
struct PeakSpeedEvidenceTests {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    private func sample(
        source: SpeedTelemetrySource = .scooterBluetooth,
        provenance: SpeedTelemetryProvenance = .absoluteMeasurement,
        metersPerSecond: Double,
        uptime: UInt64,
        accuracy: Double? = nil
    ) throws -> SpeedTelemetrySample {
        try SpeedTelemetrySample(
            source: source,
            provenance: provenance,
            metersPerSecond: metersPerSecond,
            receivedAtUptimeNanoseconds: uptime,
            receivedAtDate: epoch,
            speedAccuracyMetersPerSecond: accuracy
        )
    }

    @Test("policy refuses motion-assist as an absolute peak source")
    func policyValidation() {
        #expect(throws: PeakSpeedPolicyError.nonAuthoritativeSource) {
            try PeakSpeedPolicy(source: .motionAssist)
        }
        #expect(throws: PeakSpeedPolicyError.invalidMaximumSpeedAccuracy) {
            try PeakSpeedPolicy(
                source: .gps,
                maximumSpeedAccuracyMetersPerSecond: -.infinity
            )
        }
    }

    @Test("first accepted sample establishes observed peak")
    func firstSampleEstablishesPeak() throws {
        var accumulator = PeakSpeedEvidenceAccumulator(
            policy: try PeakSpeedPolicy(source: .scooterBluetooth)
        )
        let result = accumulator.record(try sample(metersPerSecond: 4, uptime: 100))
        guard case let .peakUpdated(measurement) = result else {
            Issue.record("Expected first accepted sample to establish peak")
            return
        }
        #expect(measurement.metersPerSecond == 4)
        #expect(measurement.source == .scooterBluetooth)

        let evidence = try #require(accumulator.evidence)
        #expect(evidence.peak == measurement)
        #expect(evidence.acceptedSampleCount == 1)
        #expect(evidence.qualityRejectedSampleCount == 0)
        #expect(evidence.knownInterruptionCount == 0)
        #expect(evidence.continuity == .uninterruptedAcceptedObservations)
    }

    @Test("higher speed updates peak while lower and equal samples retain earliest maximum")
    func peakUpdatesOnlyForStrictlyHigherMeasurement() throws {
        var accumulator = PeakSpeedEvidenceAccumulator(
            policy: try PeakSpeedPolicy(source: .scooterBluetooth)
        )
        #expect(accumulator.record(try sample(metersPerSecond: 4, uptime: 100)) != .acceptedWithoutPeakChange)
        #expect(accumulator.record(try sample(metersPerSecond: 3, uptime: 200)) == .acceptedWithoutPeakChange)
        #expect(accumulator.record(try sample(metersPerSecond: 5, uptime: 300)) != .acceptedWithoutPeakChange)
        #expect(accumulator.record(try sample(metersPerSecond: 5, uptime: 400)) == .acceptedWithoutPeakChange)

        let evidence = try #require(accumulator.evidence)
        #expect(evidence.peak.metersPerSecond == 5)
        #expect(evidence.peak.receivedAtUptimeNanoseconds == 300)
        #expect(evidence.acceptedSampleCount == 4)
    }

    @Test("foreign authoritative sources never contaminate selected-source peak evidence")
    func sourceMismatchDoesNotContaminateEvidence() throws {
        var accumulator = PeakSpeedEvidenceAccumulator(
            policy: try PeakSpeedPolicy(source: .scooterBluetooth)
        )
        #expect(
            accumulator.record(try sample(
                source: .gps,
                metersPerSecond: 20,
                uptime: 100,
                accuracy: 0.2
            )) == .rejected(.sourceMismatch)
        )
        accumulator.record(try sample(metersPerSecond: 4, uptime: 200))

        let evidence = try #require(accumulator.evidence)
        #expect(evidence.peak.metersPerSecond == 4)
        #expect(evidence.acceptedSampleCount == 1)
        #expect(evidence.qualityRejectedSampleCount == 0)
        #expect(evidence.continuity == .uninterruptedAcceptedObservations)
    }

    @Test("motion-assisted estimates never become peak measurements")
    func motionEstimateRejected() throws {
        var accumulator = PeakSpeedEvidenceAccumulator(
            policy: try PeakSpeedPolicy(source: .scooterBluetooth)
        )
        let estimate = try sample(
            source: .motionAssist,
            provenance: .shortHorizonEstimate,
            metersPerSecond: 30,
            uptime: 100
        )
        #expect(accumulator.record(estimate) == .rejected(.nonAuthoritativeSample))
        #expect(accumulator.evidence == nil)
    }

    @Test("requested GPS accuracy must exist and meet the injected ceiling")
    func gpsAccuracyGating() throws {
        var accumulator = PeakSpeedEvidenceAccumulator(
            policy: try PeakSpeedPolicy(
                source: .gps,
                maximumSpeedAccuracyMetersPerSecond: 1
            )
        )
        #expect(
            accumulator.record(try sample(
                source: .gps,
                metersPerSecond: 10,
                uptime: 100
            )) == .rejected(.speedAccuracyUnavailable)
        )
        #expect(
            accumulator.record(try sample(
                source: .gps,
                metersPerSecond: 11,
                uptime: 200,
                accuracy: 1.5
            )) == .rejected(.speedAccuracyExceeded(maximum: 1, actual: 1.5))
        )
        accumulator.record(try sample(
            source: .gps,
            metersPerSecond: 8,
            uptime: 300,
            accuracy: 0.4
        ))

        let evidence = try #require(accumulator.evidence)
        #expect(evidence.peak.metersPerSecond == 8)
        #expect(evidence.qualityRejectedSampleCount == 2)
        #expect(evidence.continuity == .partialAcceptedObservations)
    }

    @Test("non-increasing selected-source timestamps are rejected transactionally")
    func staleTimestampRejectedWithoutAdvancingAnchor() throws {
        var accumulator = PeakSpeedEvidenceAccumulator(
            policy: try PeakSpeedPolicy(source: .scooterBluetooth)
        )
        accumulator.record(try sample(metersPerSecond: 4, uptime: 200))
        #expect(
            accumulator.record(try sample(metersPerSecond: 99, uptime: 100))
                == .rejected(.nonIncreasingTimestamp)
        )
        accumulator.record(try sample(metersPerSecond: 5, uptime: 300))

        let evidence = try #require(accumulator.evidence)
        #expect(evidence.peak.metersPerSecond == 5)
        #expect(evidence.acceptedSampleCount == 2)
        #expect(evidence.qualityRejectedSampleCount == 1)
        #expect(evidence.continuity == .partialAcceptedObservations)
    }

    @Test("known observation interruption preserves measured peak but marks continuity partial")
    func interruptionPreservesObservedPeak() throws {
        var accumulator = PeakSpeedEvidenceAccumulator(
            policy: try PeakSpeedPolicy(source: .scooterBluetooth)
        )
        accumulator.record(try sample(metersPerSecond: 6, uptime: 100))
        accumulator.recordInterruption(.vehicleConnectionLost)
        accumulator.record(try sample(metersPerSecond: 5, uptime: 200))

        let evidence = try #require(accumulator.evidence)
        #expect(evidence.peak.metersPerSecond == 6)
        #expect(evidence.knownInterruptionCount == 1)
        #expect(evidence.continuity == .partialAcceptedObservations)
    }

    @Test("reset removes prior peak and continuity history")
    func resetClearsEvidence() throws {
        var accumulator = PeakSpeedEvidenceAccumulator(
            policy: try PeakSpeedPolicy(source: .scooterBluetooth)
        )
        accumulator.record(try sample(metersPerSecond: 6, uptime: 100))
        accumulator.recordInterruption(.applicationLifecycleInterrupted)
        #expect(accumulator.evidence != nil)

        accumulator.reset()
        #expect(accumulator.evidence == nil)
        accumulator.record(try sample(metersPerSecond: 2, uptime: 50))
        let fresh = try #require(accumulator.evidence)
        #expect(fresh.peak.metersPerSecond == 2)
        #expect(fresh.qualityRejectedSampleCount == 0)
        #expect(fresh.knownInterruptionCount == 0)
        #expect(fresh.continuity == .uninterruptedAcceptedObservations)
    }
}
