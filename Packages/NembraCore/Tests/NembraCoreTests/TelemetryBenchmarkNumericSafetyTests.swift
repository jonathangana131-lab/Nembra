import Foundation
import Testing
@testable import NembraCore

@Suite("Telemetry benchmark numeric safety")
struct TelemetryBenchmarkNumericSafetyTests {
    @Test("finite m/s that overflows km/h is rejected before entering diagnostics")
    func overflowingDerivedSpeedIsRejected() throws {
        var collector = TelemetryBenchmarkCollector(source: .scooterBluetooth)
        let epoch = Date(timeIntervalSince1970: 1_700_000_000)
        let sample = try SpeedTelemetrySample(
            source: .scooterBluetooth,
            provenance: .absoluteMeasurement,
            metersPerSecond: .greatestFiniteMagnitude,
            receivedAtUptimeNanoseconds: 100_000_000,
            receivedAtDate: epoch
        )

        #expect(sample.metersPerSecond.isFinite)
        #expect(sample.kilometersPerHour.isFinite == false)
        #expect(collector.record(sample) == .rejected(.nonFiniteSpeedConversion))

        let summary = collector.summary
        #expect(summary.acceptedSampleCount == 0)
        #expect(summary.rejectedSampleCount == 1)
        #expect(summary.intervalCount == 0)
        #expect(summary.observedDurationSeconds == 0)
        #expect(summary.effectiveSampleRateHertz == nil)
        #expect(summary.empiricalMinimumNonzeroSpeedStepKilometersPerHour == nil)
    }

    @Test("rejected overflow does not advance interval or speed-step baselines")
    func overflowingDerivedSpeedIsTransactional() throws {
        var collector = TelemetryBenchmarkCollector(source: .scooterBluetooth)
        let epoch = Date(timeIntervalSince1970: 1_700_000_000)

        let first = try SpeedTelemetrySample(
            source: .scooterBluetooth,
            provenance: .absoluteMeasurement,
            metersPerSecond: 1,
            receivedAtUptimeNanoseconds: 100_000_000,
            receivedAtDate: epoch
        )
        let overflow = try SpeedTelemetrySample(
            source: .scooterBluetooth,
            provenance: .absoluteMeasurement,
            metersPerSecond: .greatestFiniteMagnitude,
            receivedAtUptimeNanoseconds: 200_000_000,
            receivedAtDate: epoch
        )
        let second = try SpeedTelemetrySample(
            source: .scooterBluetooth,
            provenance: .absoluteMeasurement,
            metersPerSecond: 2,
            receivedAtUptimeNanoseconds: 300_000_000,
            receivedAtDate: epoch
        )

        #expect(collector.record(first) == .accepted)
        #expect(collector.record(overflow) == .rejected(.nonFiniteSpeedConversion))
        #expect(collector.record(second) == .accepted)

        let summary = collector.summary
        #expect(summary.acceptedSampleCount == 2)
        #expect(summary.rejectedSampleCount == 1)
        #expect(summary.intervalCount == 1)
        #expect(abs((summary.meanIntervalMilliseconds ?? 0) - 200) < 0.000_001)
        #expect(abs((summary.effectiveSampleRateHertz ?? 0) - 5) < 0.000_001)
        #expect(abs((summary.empiricalMinimumNonzeroSpeedStepKilometersPerHour ?? 0) - 3.6) < 0.000_001)
    }
}
