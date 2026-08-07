import Foundation
import Testing
@testable import NembraCore

@Suite("Telemetry benchmark selected-source chronology")
struct TelemetryBenchmarkSelectedSourceChronologyTests {
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

    private func overflowingSample(milliseconds: UInt64) throws -> SpeedTelemetrySample {
        try SpeedTelemetrySample(
            source: .scooterBluetooth,
            provenance: .absoluteMeasurement,
            metersPerSecond: Double.greatestFiniteMagnitude / 2,
            receivedAtUptimeNanoseconds: milliseconds * 1_000_000,
            receivedAtDate: epoch.addingTimeInterval(Double(milliseconds) / 1_000)
        )
    }

    @Test("newer derived-speed rejection closes chronology to delayed selected-source callbacks")
    func rejectedNewerObservationPreventsOlderReplay() throws {
        var collector = TelemetryBenchmarkCollector(source: .scooterBluetooth)

        #expect(collector.record(try sample(milliseconds: 100, speedKilometersPerHour: 3.6)) == .accepted)

        let overflow = try overflowingSample(milliseconds: 300)
        #expect(!overflow.kilometersPerHour.isFinite)
        #expect(collector.record(overflow) == .rejected(.nonFiniteDerivedSpeed))

        let afterOverflow = collector.summary
        #expect(afterOverflow.acceptedSampleCount == 1)
        #expect(afterOverflow.rejectedSampleCount == 1)
        #expect(afterOverflow.observationSegmentCount == 1)
        #expect(afterOverflow.intervalCount == 0)

        // The selected-source @300 callback is rejected from benchmark statistics,
        // but it remains real receive-order evidence. A delayed @200 callback must
        // never become fresh merely because @300 could not be represented in km/h.
        #expect(
            collector.record(try sample(milliseconds: 200, speedKilometersPerHour: 7.2))
                == .rejected(.nonMonotonicTimestamp)
        )

        let afterReplay = collector.summary
        #expect(afterReplay.acceptedSampleCount == 1)
        #expect(afterReplay.rejectedSampleCount == 2)
        #expect(afterReplay.observationSegmentCount == 1)
        #expect(afterReplay.intervalCount == 0)

        // Without an explicit continuity break, the next accepted benchmark sample
        // still spans from the last accepted benchmark anchor. The rejected sample
        // never becomes an interval endpoint or speed-step datum.
        #expect(collector.record(try sample(milliseconds: 400, speedKilometersPerHour: 10.8)) == .accepted)
        let resumed = collector.summary
        #expect(resumed.acceptedSampleCount == 2)
        #expect(resumed.rejectedSampleCount == 2)
        #expect(resumed.observationSegmentCount == 1)
        #expect(resumed.intervalCount == 1)
        #expect(abs(resumed.observedDurationSeconds - 0.3) < 0.000_001)
        #expect(abs((resumed.meanIntervalMilliseconds ?? 0) - 300) < 0.000_001)
    }

    @Test("derived-speed rejection preserves a pending interruption while still closing chronology")
    func pendingInterruptionSurvivesRejectedNewerObservationAndReplay() throws {
        var collector = TelemetryBenchmarkCollector(source: .scooterBluetooth)

        #expect(collector.record(try sample(milliseconds: 100, speedKilometersPerHour: 3.6)) == .accepted)
        collector.markKnownObservationInterruption()

        let overflow = try overflowingSample(milliseconds: 300)
        #expect(!overflow.kilometersPerHour.isFinite)
        #expect(collector.record(overflow) == .rejected(.nonFiniteDerivedSpeed))
        #expect(
            collector.record(try sample(milliseconds: 200, speedKilometersPerHour: 7.2))
                == .rejected(.nonMonotonicTimestamp)
        )

        var summary = collector.summary
        #expect(summary.acceptedSampleCount == 1)
        #expect(summary.rejectedSampleCount == 2)
        #expect(summary.observationSegmentCount == 1)
        #expect(summary.knownObservationInterruptionCount == 1)
        #expect(summary.intervalCount == 0)
        #expect(summary.observedDurationSeconds == 0)

        // Rejections may advance selected-source receive chronology, but only an
        // accepted benchmark sample may consume the pending continuity boundary.
        #expect(collector.record(try sample(milliseconds: 400, speedKilometersPerHour: 10.8)) == .accepted)
        summary = collector.summary
        #expect(summary.acceptedSampleCount == 2)
        #expect(summary.rejectedSampleCount == 2)
        #expect(summary.observationSegmentCount == 2)
        #expect(summary.knownObservationInterruptionCount == 1)
        #expect(summary.intervalCount == 0)
        #expect(summary.observedDurationSeconds == 0)

        #expect(collector.record(try sample(milliseconds: 500, speedKilometersPerHour: 14.4)) == .accepted)
        summary = collector.summary
        #expect(summary.intervalCount == 1)
        #expect(abs(summary.observedDurationSeconds - 0.1) < 0.000_001)
        #expect(abs((summary.meanIntervalMilliseconds ?? 0) - 100) < 0.000_001)
        #expect(abs((summary.effectiveSampleRateHertz ?? 0) - 10) < 0.000_001)
    }
}
