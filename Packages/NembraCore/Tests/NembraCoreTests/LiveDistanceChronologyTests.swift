import Foundation
import Testing

@testable import NembraCore

@Suite("Live distance callback chronology")
struct LiveDistanceChronologyTests {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    private func policy(
        source: SpeedTelemetrySource = .scooterBluetooth,
        maximumGap: UInt64 = 3_000_000_000
    ) throws -> LiveDistanceIntegrationPolicy {
        try LiveDistanceIntegrationPolicy(
            source: source,
            maximumIntegrationIntervalNanoseconds: maximumGap,
            method: .trapezoidalBetweenMeasurements
        )
    }

    private func sample(
        source: SpeedTelemetrySource = .scooterBluetooth,
        speed: Double,
        uptime: UInt64
    ) throws -> SpeedTelemetrySample {
        try SpeedTelemetrySample(
            source: source,
            provenance: source == .motionAssist ? .shortHorizonEstimate : .absoluteMeasurement,
            metersPerSecond: speed,
            receivedAtUptimeNanoseconds: uptime,
            receivedAtDate: epoch.addingTimeInterval(Double(uptime) / 1_000_000_000)
        )
    }

    @Test("fresh numeric rejection consumes selected authoritative chronology")
    func rejectedOverflowClosesChronologyToDelayedCallbacks() throws {
        var accumulator = LiveDistanceSegmentAccumulator(
            policy: try policy(),
            segmentStartUptimeNanoseconds: 0
        )

        #expect(
            accumulator.record(
                try sample(speed: Double.greatestFiniteMagnitude, uptime: 0)
            ) == .anchored
        )
        let acceptedBeforeOverflow = accumulator.snapshot

        #expect(
            accumulator.record(
                try sample(speed: Double.greatestFiniteMagnitude, uptime: 2_000_000_000)
            ) == .rejected(.distanceOverflow)
        )

        // Numeric rejection must not rewrite accepted distance/anchor evidence.
        #expect(accumulator.snapshot == acceptedBeforeOverflow)

        // But the newer callback identity is still part of this immutable stream.
        #expect(
            accumulator.record(try sample(speed: 0, uptime: 1_000_000_000))
                == .rejected(.nonIncreasingTimestamp)
        )
        #expect(
            accumulator.record(try sample(speed: 0, uptime: 2_000_000_000))
                == .rejected(.nonIncreasingTimestamp)
        )
        #expect(accumulator.snapshot == acceptedBeforeOverflow)
    }

    @Test("foreign and non-authoritative callbacks cannot poison selected chronology")
    func rejectedForeignEvidenceDoesNotConsumeChronology() throws {
        var accumulator = LiveDistanceSegmentAccumulator(
            policy: try policy(),
            segmentStartUptimeNanoseconds: 0
        )

        #expect(
            accumulator.record(try sample(source: .gps, speed: 3, uptime: 200))
                == .rejected(.sourceMismatch)
        )
        #expect(
            accumulator.record(try sample(source: .motionAssist, speed: 3, uptime: 300))
                == .rejected(.nonAuthoritativeSample)
        )

        // Neither unrelated callback owns chronology for the selected BLE stream.
        #expect(accumulator.record(try sample(speed: 4, uptime: 100)) == .anchored)
        let result = accumulator.record(try sample(speed: 4, uptime: 200))
        guard case let .integrated(addedMeters) = result else {
            Issue.record("selected authoritative callbacks should remain integrable")
            return
        }
        #expect(abs(addedMeters - 0.000_000_4) < 1e-15)
    }

    @Test("pre-segment callback does not consume in-segment chronology")
    func beforeSegmentStartDoesNotConsumeChronology() throws {
        var accumulator = LiveDistanceSegmentAccumulator(
            policy: try policy(),
            segmentStartUptimeNanoseconds: 1_000
        )

        #expect(
            accumulator.record(try sample(speed: 2, uptime: 999))
                == .rejected(.beforeSegmentStart)
        )
        #expect(accumulator.record(try sample(speed: 2, uptime: 1_000)) == .anchored)
    }

    @Test("finalization cannot predate a newer rejected authoritative callback")
    func finalizationHonorsConsumedChronology() throws {
        var accumulator = LiveDistanceSegmentAccumulator(
            policy: try policy(),
            segmentStartUptimeNanoseconds: 0
        )

        accumulator.record(
            try sample(speed: Double.greatestFiniteMagnitude, uptime: 0)
        )
        #expect(
            accumulator.record(
                try sample(speed: Double.greatestFiniteMagnitude, uptime: 2_000_000_000)
            ) == .rejected(.distanceOverflow)
        )

        #expect(throws: LiveDistanceIntegrationError.invalidSegmentEnd) {
            try accumulator.finalize(segmentEndUptimeNanoseconds: 1_000_000_000)
        }

        let final = try accumulator.finalize(segmentEndUptimeNanoseconds: 2_000_000_000)
        #expect(final.lastAcceptedSampleUptimeNanoseconds == 0)
        #expect(final.distanceMeters == nil)
        #expect(final.coverage == .unknown)
        #expect(final.knownCoverageGapCount == 1)
    }
}
