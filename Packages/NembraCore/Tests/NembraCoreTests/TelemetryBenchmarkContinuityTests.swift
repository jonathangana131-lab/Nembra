import Foundation
import Testing
@testable import NembraCore

@Suite("Telemetry benchmark continuity")
struct TelemetryBenchmarkContinuityTests {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    private func sample(
        milliseconds: UInt64,
        speedKilometersPerHour: Double
    ) throws -> SpeedTelemetrySample {
        try SpeedTelemetrySample(
            source: .scooterBluetooth,
            provenance: .absoluteMeasurement,
            metersPerSecond: speedKilometersPerHour / 3.6,
            receivedAtUptimeNanoseconds: milliseconds * 1_000_000,
            receivedAtDate: epoch.addingTimeInterval(Double(milliseconds) / 1_000)
        )
    }

    @Test("known interruption stays out of cadence jitter and speed-step evidence")
    func interruptionDoesNotBecomeAnInterval() throws {
        var collector = TelemetryBenchmarkCollector(source: .scooterBluetooth)

        #expect(collector.record(try sample(milliseconds: 0, speedKilometersPerHour: 0)) == .accepted)
        #expect(collector.record(try sample(milliseconds: 100, speedKilometersPerHour: 1)) == .accepted)

        collector.markContinuityInterruption()

        // Ten seconds of missing evidence must stay a gap rather than becoming
        // a 10 s packet interval or a cross-gap duplicate/resolution sample.
        #expect(collector.record(try sample(milliseconds: 10_100, speedKilometersPerHour: 1)) == .accepted)
        #expect(collector.record(try sample(milliseconds: 10_200, speedKilometersPerHour: 2)) == .accepted)

        let summary = collector.summary
        #expect(summary.acceptedSampleCount == 4)
        #expect(summary.rejectedSampleCount == 0)
        #expect(summary.observationSegmentCount == 2)
        #expect(summary.knownObservationInterruptionCount == 1)
        #expect(summary.intervalCount == 2)
        #expect(abs(summary.observedDurationSeconds - 0.2) < 0.000_001)
        #expect(abs((summary.effectiveSampleRateHertz ?? 0) - 10) < 0.000_001)
        #expect(abs((summary.meanIntervalMilliseconds ?? 0) - 100) < 0.000_001)
        #expect(abs((summary.minimumIntervalMilliseconds ?? 0) - 100) < 0.000_001)
        #expect(abs((summary.maximumIntervalMilliseconds ?? 0) - 100) < 0.000_001)
        #expect((summary.intervalJitterStandardDeviationMilliseconds ?? -1) < 0.000_001)
        #expect(summary.duplicateSpeedValueCount == 0)
        #expect(abs((summary.empiricalMinimumNonzeroSpeedStepKilometersPerHour ?? 0) - 1) < 0.000_001)
    }

    @Test("interruption does not erase the global monotonic ordering anchor")
    func staleCallbackAfterInterruptionIsRejected() throws {
        var collector = TelemetryBenchmarkCollector(source: .scooterBluetooth)

        #expect(collector.record(try sample(milliseconds: 100, speedKilometersPerHour: 4)) == .accepted)
        collector.markContinuityInterruption()

        #expect(
            collector.record(try sample(milliseconds: 90, speedKilometersPerHour: 5))
                == .rejected(.nonMonotonicTimestamp)
        )
        #expect(collector.record(try sample(milliseconds: 200, speedKilometersPerHour: 5)) == .accepted)

        let afterReconnect = collector.summary
        #expect(afterReconnect.acceptedSampleCount == 2)
        #expect(afterReconnect.rejectedSampleCount == 1)
        #expect(afterReconnect.observationSegmentCount == 2)
        #expect(afterReconnect.knownObservationInterruptionCount == 1)
        #expect(afterReconnect.intervalCount == 0)
        #expect(afterReconnect.observedDurationSeconds == 0)
        #expect(afterReconnect.effectiveSampleRateHertz == nil)

        #expect(collector.record(try sample(milliseconds: 300, speedKilometersPerHour: 6)) == .accepted)
        let continued = collector.summary
        #expect(continued.intervalCount == 1)
        #expect(abs(continued.observedDurationSeconds - 0.1) < 0.000_001)
        #expect(abs((continued.effectiveSampleRateHertz ?? 0) - 10) < 0.000_001)
    }

    @Test("repeated interruption marks without new evidence are idempotent")
    func interruptionMarksAreIdempotentUntilEvidenceResumes() throws {
        var collector = TelemetryBenchmarkCollector(source: .scooterBluetooth)

        collector.markContinuityInterruption()
        #expect(collector.summary.knownObservationInterruptionCount == 0)
        #expect(collector.summary.observationSegmentCount == 0)

        #expect(collector.record(try sample(milliseconds: 100, speedKilometersPerHour: 1)) == .accepted)
        collector.markContinuityInterruption()
        collector.markContinuityInterruption()

        var summary = collector.summary
        #expect(summary.knownObservationInterruptionCount == 1)
        #expect(summary.observationSegmentCount == 1)
        #expect(summary.intervalCount == 0)

        #expect(collector.record(try sample(milliseconds: 200, speedKilometersPerHour: 2)) == .accepted)
        summary = collector.summary
        #expect(summary.knownObservationInterruptionCount == 1)
        #expect(summary.observationSegmentCount == 2)

        collector.markContinuityInterruption()
        summary = collector.summary
        #expect(summary.knownObservationInterruptionCount == 2)
        #expect(summary.observationSegmentCount == 2)
    }

    @Test("rejected derived speed cannot consume a pending interruption")
    func derivedSpeedOverflowPreservesPendingInterruption() throws {
        var collector = TelemetryBenchmarkCollector(source: .scooterBluetooth)

        #expect(collector.record(try sample(milliseconds: 100, speedKilometersPerHour: 3.6)) == .accepted)
        collector.markContinuityInterruption()

        let overflowing = try SpeedTelemetrySample(
            source: .scooterBluetooth,
            provenance: .absoluteMeasurement,
            metersPerSecond: Double.greatestFiniteMagnitude / 2,
            receivedAtUptimeNanoseconds: 200_000_000,
            receivedAtDate: epoch.addingTimeInterval(0.2)
        )
        #expect(overflowing.kilometersPerHour.isFinite == false)
        #expect(collector.record(overflowing) == .rejected(.nonFiniteDerivedSpeed))

        var summary = collector.summary
        #expect(summary.acceptedSampleCount == 1)
        #expect(summary.rejectedSampleCount == 1)
        #expect(summary.observationSegmentCount == 1)
        #expect(summary.knownObservationInterruptionCount == 1)
        #expect(summary.intervalCount == 0)

        #expect(collector.record(try sample(milliseconds: 300, speedKilometersPerHour: 7.2)) == .accepted)
        summary = collector.summary
        #expect(summary.observationSegmentCount == 2)
        #expect(summary.knownObservationInterruptionCount == 1)
        #expect(summary.intervalCount == 0)

        #expect(collector.record(try sample(milliseconds: 400, speedKilometersPerHour: 10.8)) == .accepted)
        summary = collector.summary
        #expect(summary.intervalCount == 1)
        #expect(abs(summary.observedDurationSeconds - 0.1) < 0.000_001)
        #expect(abs((summary.meanIntervalMilliseconds ?? 0) - 100) < 0.000_001)
    }
}
