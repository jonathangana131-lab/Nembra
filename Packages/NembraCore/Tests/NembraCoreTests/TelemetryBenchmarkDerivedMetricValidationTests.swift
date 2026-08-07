import Foundation
import Testing
@testable import NembraCore

@Suite("Telemetry benchmark derived-metric validation")
struct TelemetryBenchmarkDerivedMetricValidationTests {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("finite SI speed that overflows benchmark km/h is rejected transactionally")
    func derivedSpeedOverflowDoesNotPoisonAcceptedEvidence() throws {
        var collector = TelemetryBenchmarkCollector(source: .scooterBluetooth)

        let first = try SpeedTelemetrySample(
            source: .scooterBluetooth,
            provenance: .absoluteMeasurement,
            metersPerSecond: 1,
            receivedAtUptimeNanoseconds: 100_000_000,
            receivedAtDate: epoch
        )
        let overflowing = try SpeedTelemetrySample(
            source: .scooterBluetooth,
            provenance: .absoluteMeasurement,
            metersPerSecond: Double.greatestFiniteMagnitude / 2,
            receivedAtUptimeNanoseconds: 200_000_000,
            receivedAtDate: epoch.addingTimeInterval(0.1)
        )
        let nextValid = try SpeedTelemetrySample(
            source: .scooterBluetooth,
            provenance: .absoluteMeasurement,
            metersPerSecond: 2,
            receivedAtUptimeNanoseconds: 300_000_000,
            receivedAtDate: epoch.addingTimeInterval(0.2)
        )

        #expect(collector.record(first) == .accepted)
        #expect(overflowing.metersPerSecond.isFinite)
        #expect(overflowing.kilometersPerHour.isFinite == false)
        #expect(collector.record(overflowing) == .rejected(.nonFiniteDerivedSpeed))
        #expect(collector.record(nextValid) == .accepted)

        let summary = collector.summary
        #expect(summary.acceptedSampleCount == 2)
        #expect(summary.rejectedSampleCount == 1)
        #expect(summary.intervalCount == 1)
        #expect(summary.meanIntervalMilliseconds == 200)
        #expect(summary.duplicateSpeedValueCount == 0)
        #expect(abs((summary.empiricalMinimumNonzeroSpeedStepKilometersPerHour ?? 0) - 3.6) < 0.000_001)
    }

    @Test("overflowing first derived speed cannot become the benchmark anchor")
    func rejectedOverflowDoesNotCreateAnchor() throws {
        var collector = TelemetryBenchmarkCollector(source: .gps)

        let overflowing = try SpeedTelemetrySample(
            source: .gps,
            provenance: .absoluteMeasurement,
            metersPerSecond: Double.greatestFiniteMagnitude / 2,
            receivedAtUptimeNanoseconds: 100,
            receivedAtDate: epoch
        )
        let firstValid = try SpeedTelemetrySample(
            source: .gps,
            provenance: .absoluteMeasurement,
            metersPerSecond: 3,
            receivedAtUptimeNanoseconds: 200,
            receivedAtDate: epoch
        )

        #expect(collector.record(overflowing) == .rejected(.nonFiniteDerivedSpeed))
        #expect(collector.record(firstValid) == .accepted)

        let summary = collector.summary
        #expect(summary.acceptedSampleCount == 1)
        #expect(summary.rejectedSampleCount == 1)
        #expect(summary.intervalCount == 0)
        #expect(summary.observedDurationSeconds == 0)
        #expect(summary.effectiveSampleRateHertz == nil)
        #expect(summary.empiricalMinimumNonzeroSpeedStepKilometersPerHour == nil)
    }

    @Test("very large speed remains benchmarkable when required conversion stays finite")
    func largeConvertibleSpeedRemainsAccepted() throws {
        var collector = TelemetryBenchmarkCollector(source: .scooterBluetooth)
        let largeMetersPerSecond = Double.greatestFiniteMagnitude / 4
        let sample = try SpeedTelemetrySample(
            source: .scooterBluetooth,
            provenance: .absoluteMeasurement,
            metersPerSecond: largeMetersPerSecond,
            receivedAtUptimeNanoseconds: 1,
            receivedAtDate: epoch
        )

        #expect(sample.kilometersPerHour.isFinite)
        #expect(collector.record(sample) == .accepted)
        #expect(collector.summary.acceptedSampleCount == 1)
        #expect(collector.summary.rejectedSampleCount == 0)
    }
}
