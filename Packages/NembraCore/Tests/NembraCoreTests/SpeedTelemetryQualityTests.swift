import Foundation
import Testing
@testable import NembraCore

@Suite("Injected speed telemetry quality gates")
struct SpeedTelemetryQualityTests {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    private func sample(
        source: SpeedTelemetrySource = .scooterBluetooth,
        metersPerSecond: Double,
        milliseconds: UInt64,
        deliveryLatencyMilliseconds: Double? = nil
    ) throws -> SpeedTelemetrySample {
        let received = epoch.addingTimeInterval(Double(milliseconds) / 1_000)
        let measurementDate = deliveryLatencyMilliseconds.map {
            received.addingTimeInterval(-$0 / 1_000)
        }
        return try SpeedTelemetrySample(
            source: source,
            provenance: .absoluteMeasurement,
            metersPerSecond: metersPerSecond,
            receivedAtUptimeNanoseconds: milliseconds * 1_000_000,
            receivedAtDate: received,
            measurementDate: measurementDate,
            speedAccuracyMetersPerSecond: source == .gps ? 0.5 : nil
        )
    }

    @Test("policy accepts no implicit hardware thresholds and rejects malformed requirements")
    func policyValidation() throws {
        let unconstrained = try SpeedTelemetryQualityPolicy()
        #expect(unconstrained.minimumAcceptedSampleCount == 1)
        #expect(unconstrained.maximumMeanIntervalMilliseconds == nil)
        #expect(unconstrained.minimumDeliveryLatencySampleFraction == nil)

        #expect(throws: SpeedTelemetryQualityPolicyError.invalidMinimumAcceptedSampleCount) {
            try SpeedTelemetryQualityPolicy(minimumAcceptedSampleCount: 0)
        }
        #expect(throws: SpeedTelemetryQualityPolicyError.invalidMaximumRejectedSampleFraction) {
            try SpeedTelemetryQualityPolicy(maximumRejectedSampleFraction: 1.01)
        }
        #expect(throws: SpeedTelemetryQualityPolicyError.invalidMinimumDeliveryLatencySampleFraction) {
            try SpeedTelemetryQualityPolicy(minimumDeliveryLatencySampleFraction: -0.01)
        }
        #expect(throws: SpeedTelemetryQualityPolicyError.invalidMinimumDeliveryLatencySampleFraction) {
            try SpeedTelemetryQualityPolicy(minimumDeliveryLatencySampleFraction: .infinity)
        }
        #expect(throws: SpeedTelemetryQualityPolicyError.invalidThreshold) {
            try SpeedTelemetryQualityPolicy(maximumMeanIntervalMilliseconds: -.infinity)
        }
        #expect(throws: SpeedTelemetryQualityPolicyError.invalidThreshold) {
            try SpeedTelemetryQualityPolicy(maximumEmpiricalSpeedStepKilometersPerHour: -0.1)
        }
    }

    @Test("measured source qualifies only against the caller's supplied requirements")
    func qualifyingSummary() throws {
        var collector = TelemetryBenchmarkCollector(source: .scooterBluetooth)
        for (index, speed) in [0.0, 0.5, 1.0, 1.5, 2.0].enumerated() {
            collector.record(try sample(
                metersPerSecond: speed,
                milliseconds: UInt64(index) * 100
            ))
        }

        let policy = try SpeedTelemetryQualityPolicy(
            requiredSource: .scooterBluetooth,
            minimumAcceptedSampleCount: 5,
            maximumRejectedSampleFraction: 0,
            maximumMeanIntervalMilliseconds: 110,
            maximumObservedIntervalMilliseconds: 110,
            maximumJitterStandardDeviationMilliseconds: 1,
            maximumEmpiricalSpeedStepKilometersPerHour: 2
        )
        let assessment = collector.summary.qualityAssessment(using: policy)
        #expect(assessment.source == .scooterBluetooth)
        #expect(assessment.isQualified)
        #expect(assessment.failures.isEmpty)
    }

    @Test("single sample reports insufficient count and missing interval evidence")
    func missingIntervalEvidence() throws {
        var collector = TelemetryBenchmarkCollector(source: .scooterBluetooth)
        collector.record(try sample(metersPerSecond: 1, milliseconds: 0))

        let policy = try SpeedTelemetryQualityPolicy(
            minimumAcceptedSampleCount: 2,
            maximumMeanIntervalMilliseconds: 200
        )
        let assessment = collector.summary.qualityAssessment(using: policy)
        #expect(assessment.failures == [
            .insufficientAcceptedSamples(required: 2, actual: 1),
            .missingIntervalEvidence
        ])
    }

    @Test("source mismatch and rejected fraction remain separate quality failures")
    func sourceAndRejectionFailures() throws {
        var collector = TelemetryBenchmarkCollector(source: .scooterBluetooth)
        collector.record(try sample(metersPerSecond: 1, milliseconds: 0))
        collector.record(try sample(source: .gps, metersPerSecond: 1, milliseconds: 100))

        let policy = try SpeedTelemetryQualityPolicy(
            requiredSource: .gps,
            maximumRejectedSampleFraction: 0.2
        )
        let assessment = collector.summary.qualityAssessment(using: policy)
        #expect(assessment.failures.count == 2)
        #expect(assessment.failures[0] == .sourceMismatch(
            expected: .gps,
            actual: .scooterBluetooth
        ))
        guard case let .rejectedSampleFractionExceeded(maximum, actual) = assessment.failures[1] else {
            Issue.record("Expected rejected-sample fraction failure")
            return
        }
        #expect(maximum == 0.2)
        #expect(actual == 0.5)
    }

    @Test("cadence policy can expose mean interval, worst interval, and jitter failures together")
    func cadenceFailuresAccumulate() throws {
        var collector = TelemetryBenchmarkCollector(source: .scooterBluetooth)
        collector.record(try sample(metersPerSecond: 0, milliseconds: 0))
        collector.record(try sample(metersPerSecond: 1, milliseconds: 100))
        collector.record(try sample(metersPerSecond: 2, milliseconds: 500))

        let policy = try SpeedTelemetryQualityPolicy(
            maximumMeanIntervalMilliseconds: 200,
            maximumObservedIntervalMilliseconds: 300,
            maximumJitterStandardDeviationMilliseconds: 100
        )
        let assessment = collector.summary.qualityAssessment(using: policy)
        #expect(assessment.failures.count == 3)
        #expect(assessment.failures.contains {
            if case .meanIntervalExceeded = $0 { true } else { false }
        })
        #expect(assessment.failures.contains {
            if case .observedIntervalExceeded = $0 { true } else { false }
        })
        #expect(assessment.failures.contains {
            if case .jitterExceeded = $0 { true } else { false }
        })
    }

    @Test("missing latency and resolution evidence are both reported instead of guessed")
    func missingOptionalEvidenceAccumulates() throws {
        var collector = TelemetryBenchmarkCollector(source: .scooterBluetooth)
        collector.record(try sample(metersPerSecond: 1, milliseconds: 0))
        collector.record(try sample(metersPerSecond: 1, milliseconds: 100))

        let policy = try SpeedTelemetryQualityPolicy(
            maximumMeanDeliveryLatencyMilliseconds: 100,
            maximumEmpiricalSpeedStepKilometersPerHour: 1
        )
        let assessment = collector.summary.qualityAssessment(using: policy)
        #expect(assessment.failures == [
            .missingDeliveryLatencyEvidence,
            .missingSpeedResolutionEvidence
        ])
    }

    @Test("rejected non-finite derived speed remains unqualified")
    func nonFiniteDerivedSpeedResolutionFailsClosed() throws {
        let overflowingMetersPerSecond = Double.greatestFiniteMagnitude / 2
        var collector = TelemetryBenchmarkCollector(source: .scooterBluetooth)
        let firstResult = collector.record(try sample(
            metersPerSecond: overflowingMetersPerSecond,
            milliseconds: 0
        ))
        let secondResult = collector.record(try sample(
            metersPerSecond: overflowingMetersPerSecond,
            milliseconds: 100
        ))

        #expect(firstResult == .rejected(.nonFiniteDerivedSpeed))
        #expect(secondResult == .rejected(.nonFiniteDerivedSpeed))
        #expect(collector.summary.acceptedSampleCount == 0)
        #expect(collector.summary.rejectedSampleCount == 2)
        #expect(collector.summary.empiricalMinimumNonzeroSpeedStepKilometersPerHour == nil)

        let assessment = collector.summary.qualityAssessment(
            using: try SpeedTelemetryQualityPolicy(
                maximumEmpiricalSpeedStepKilometersPerHour: 1
            )
        )
        #expect(assessment.failures == [
            .insufficientAcceptedSamples(required: 1, actual: 0),
            .missingSpeedResolutionEvidence
        ])
    }

    @Test("latency requirement can demand representative timestamp coverage")
    func sparseLatencyCoverageFailsEvenWhenObservedMeanLooksGood() throws {
        var collector = TelemetryBenchmarkCollector(source: .gps)
        collector.record(try sample(
            source: .gps,
            metersPerSecond: 0,
            milliseconds: 0,
            deliveryLatencyMilliseconds: 50
        ))
        collector.record(try sample(source: .gps, metersPerSecond: 1, milliseconds: 100))
        collector.record(try sample(source: .gps, metersPerSecond: 2, milliseconds: 200))
        collector.record(try sample(source: .gps, metersPerSecond: 3, milliseconds: 300))

        let policy = try SpeedTelemetryQualityPolicy(
            requiredSource: .gps,
            minimumDeliveryLatencySampleFraction: 0.75,
            maximumMeanDeliveryLatencyMilliseconds: 100
        )
        let assessment = collector.summary.qualityAssessment(using: policy)

        #expect(collector.summary.deliveryLatencySampleCount == 1)
        #expect(
            collector.summary.meanDeliveryLatencyMilliseconds.map { abs($0 - 50) < 0.001 } == true
        )
        #expect(assessment.failures == [
            .deliveryLatencySampleFractionBelowMinimum(minimum: 0.75, actual: 0.25)
        ])
    }

    @Test("zero latency samples report missing evidence and insufficient requested coverage")
    func missingLatencyCoverageAccumulates() throws {
        var collector = TelemetryBenchmarkCollector(source: .gps)
        collector.record(try sample(source: .gps, metersPerSecond: 0, milliseconds: 0))
        collector.record(try sample(source: .gps, metersPerSecond: 1, milliseconds: 100))

        let policy = try SpeedTelemetryQualityPolicy(
            minimumDeliveryLatencySampleFraction: 0.5,
            maximumMeanDeliveryLatencyMilliseconds: 100
        )
        let assessment = collector.summary.qualityAssessment(using: policy)
        #expect(assessment.failures == [
            .missingDeliveryLatencyEvidence,
            .deliveryLatencySampleFractionBelowMinimum(minimum: 0.5, actual: 0)
        ])
    }

    @Test("zero minimum latency coverage imposes no hidden timestamp requirement")
    func zeroLatencyCoverageRequirementIsNoMinimum() throws {
        var collector = TelemetryBenchmarkCollector(source: .scooterBluetooth)
        collector.record(try sample(metersPerSecond: 0, milliseconds: 0))

        let policy = try SpeedTelemetryQualityPolicy(
            minimumDeliveryLatencySampleFraction: 0
        )
        let assessment = collector.summary.qualityAssessment(using: policy)
        #expect(assessment.isQualified)
        #expect(assessment.failures.isEmpty)
    }

    @Test("measured latency and empirical speed step can independently exceed requirements")
    func latencyAndResolutionFailures() throws {
        var collector = TelemetryBenchmarkCollector(source: .gps)
        collector.record(try sample(
            source: .gps,
            metersPerSecond: 0,
            milliseconds: 0,
            deliveryLatencyMilliseconds: 200
        ))
        collector.record(try sample(
            source: .gps,
            metersPerSecond: 2,
            milliseconds: 100,
            deliveryLatencyMilliseconds: 200
        ))

        let policy = try SpeedTelemetryQualityPolicy(
            requiredSource: .gps,
            minimumDeliveryLatencySampleFraction: 1,
            maximumMeanDeliveryLatencyMilliseconds: 100,
            maximumEmpiricalSpeedStepKilometersPerHour: 1
        )
        let assessment = collector.summary.qualityAssessment(using: policy)
        #expect(assessment.failures.count == 2)
        #expect(assessment.failures.contains {
            if case .deliveryLatencyExceeded = $0 { true } else { false }
        })
        #expect(assessment.failures.contains {
            if case .speedResolutionStepExceeded = $0 { true } else { false }
        })
    }

    @Test("unrequested metrics never become hidden qualification requirements")
    func unconstrainedPolicyDoesNotInventRequirements() throws {
        var collector = TelemetryBenchmarkCollector(source: .scooterBluetooth)
        collector.record(try sample(metersPerSecond: 0, milliseconds: 0))
        let assessment = collector.summary.qualityAssessment(
            using: try SpeedTelemetryQualityPolicy()
        )
        #expect(assessment.isQualified)
        #expect(assessment.failures.isEmpty)
    }
}
