import Foundation
import Testing

@testable import NembraCore

@Suite("Authoritative live distance integration")
struct LiveDistanceIntegrationTests {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    private func policy(
        source: SpeedTelemetrySource = .scooterBluetooth,
        maximumGap: UInt64 = 1_000_000_000
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

    @Test("policy rejects motion assist and a zero gap threshold")
    func invalidPolicy() {
        #expect(throws: LiveDistanceIntegrationError.invalidPolicy) {
            try LiveDistanceIntegrationPolicy(
                source: .motionAssist,
                maximumIntegrationIntervalNanoseconds: 1,
                method: .trapezoidalBetweenMeasurements
            )
        }
        #expect(throws: LiveDistanceIntegrationError.invalidPolicy) {
            try LiveDistanceIntegrationPolicy(
                source: .scooterBluetooth,
                maximumIntegrationIntervalNanoseconds: 0,
                method: .trapezoidalBetweenMeasurements
            )
        }
    }

    @Test("no samples means no distance evidence instead of fake zero")
    func emptyAccumulatorIsUnavailable() throws {
        let accumulator = LiveDistanceSegmentAccumulator(
            policy: try policy(),
            segmentStartUptimeNanoseconds: 100
        )
        #expect(accumulator.snapshot.distanceMeters == nil)
        #expect(accumulator.snapshot.acceptedSampleCount == 0)
        #expect(try accumulator.finalize(segmentEndUptimeNanoseconds: 100).coverage == .unknown)
    }

    @Test("first sample anchors but cannot fabricate distance by itself")
    func firstSampleAnchors() throws {
        var accumulator = LiveDistanceSegmentAccumulator(
            policy: try policy(),
            segmentStartUptimeNanoseconds: 1_000
        )
        #expect(accumulator.record(try sample(speed: 7, uptime: 1_000)) == .anchored)
        #expect(accumulator.snapshot.distanceMeters == nil)
        #expect(accumulator.snapshot.acceptedSampleCount == 1)
        #expect(accumulator.snapshot.knownCoverageGapCount == 0)
    }

    @Test("constant authoritative speed integrates measured interval exactly")
    func constantSpeedIntegration() throws {
        var accumulator = LiveDistanceSegmentAccumulator(
            policy: try policy(),
            segmentStartUptimeNanoseconds: 0
        )
        accumulator.record(try sample(speed: 10, uptime: 0))
        let result = accumulator.record(try sample(speed: 10, uptime: 1_000_000_000))
        #expect(result == .integrated(addedMeters: 10))
        #expect(accumulator.snapshot.distanceMeters == 10)
        #expect(accumulator.snapshot.hasKnownCoverageGap == false)
        #expect(accumulator.snapshot.integratedIntervalCount == 1)
        #expect(
            try accumulator.finalize(segmentEndUptimeNanoseconds: 1_000_000_000).coverage == .complete)
    }

    @Test("trapezoidal integration uses raw endpoints, not render interpolation")
    func trapezoidalIntegration() throws {
        var accumulator = LiveDistanceSegmentAccumulator(
            policy: try policy(maximumGap: 2_000_000_000),
            segmentStartUptimeNanoseconds: 0
        )
        accumulator.record(try sample(speed: 0, uptime: 0))
        let result = accumulator.record(try sample(speed: 10, uptime: 2_000_000_000))
        #expect(result == .integrated(addedMeters: 10))
        #expect(accumulator.snapshot.distanceMeters == 10)
    }

    @Test("a late first sample permanently marks integrated coverage partial")
    func leadingGapIsPartial() throws {
        var accumulator = LiveDistanceSegmentAccumulator(
            policy: try policy(),
            segmentStartUptimeNanoseconds: 0
        )
        accumulator.record(try sample(speed: 5, uptime: 100_000_000))
        accumulator.record(try sample(speed: 5, uptime: 600_000_000))
        #expect(accumulator.snapshot.distanceMeters == 2.5)
        #expect(accumulator.snapshot.hasKnownCoverageGap)
        #expect(accumulator.snapshot.knownCoverageGapCount == 1)
        #expect(try accumulator.finalize(segmentEndUptimeNanoseconds: 600_000_000).coverage == .partial)
    }

    @Test("oversized sample gap is never integrated and the new sample becomes the next anchor")
    func oversizedGapIsSkipped() throws {
        var accumulator = LiveDistanceSegmentAccumulator(
            policy: try policy(maximumGap: 1_000_000_000),
            segmentStartUptimeNanoseconds: 0
        )
        accumulator.record(try sample(speed: 10, uptime: 0))
        #expect(
            accumulator.record(try sample(speed: 10, uptime: 2_000_000_000))
                == .gapDetected(intervalNanoseconds: 2_000_000_000)
        )
        #expect(accumulator.snapshot.distanceMeters == nil)
        accumulator.record(try sample(speed: 10, uptime: 2_500_000_000))
        #expect(accumulator.snapshot.distanceMeters == 5)
        #expect(accumulator.snapshot.hasKnownCoverageGap)
        #expect(accumulator.snapshot.knownCoverageGapCount == 1)
    }

    @Test("interval exactly at the injected gap ceiling remains integrable")
    func exactGapBoundaryIntegrates() throws {
        var accumulator = LiveDistanceSegmentAccumulator(
            policy: try policy(maximumGap: 1_000_000_000),
            segmentStartUptimeNanoseconds: 0
        )
        accumulator.record(try sample(speed: 4, uptime: 0))
        #expect(
            accumulator.record(try sample(speed: 4, uptime: 1_000_000_000))
                == .integrated(addedMeters: 4)
        )
        #expect(accumulator.snapshot.hasKnownCoverageGap == false)
    }

    @Test("repeated and out-of-order timestamps are rejected transactionally")
    func timestampRejectionIsTransactional() throws {
        var accumulator = LiveDistanceSegmentAccumulator(
            policy: try policy(),
            segmentStartUptimeNanoseconds: 0
        )
        accumulator.record(try sample(speed: 2, uptime: 100))
        let before = accumulator.snapshot
        #expect(
            accumulator.record(try sample(speed: 99, uptime: 100))
                == .rejected(.nonIncreasingTimestamp)
        )
        #expect(
            accumulator.record(try sample(speed: 99, uptime: 99))
                == .rejected(.nonIncreasingTimestamp)
        )
        #expect(accumulator.snapshot == before)
    }

    @Test("wrong source and motion estimates never enter mileage evidence")
    func wrongEvidenceRejected() throws {
        var accumulator = LiveDistanceSegmentAccumulator(
            policy: try policy(source: .scooterBluetooth),
            segmentStartUptimeNanoseconds: 0
        )
        #expect(
            accumulator.record(try sample(source: .gps, speed: 3, uptime: 1))
                == .rejected(.sourceMismatch)
        )
        #expect(
            accumulator.record(try sample(source: .motionAssist, speed: 3, uptime: 2))
                == .rejected(.nonAuthoritativeSample)
        )
        #expect(accumulator.snapshot.acceptedSampleCount == 0)
    }

    @Test("samples before the declared segment boundary are rejected without becoming anchors")
    func beforeSegmentStartRejected() throws {
        var accumulator = LiveDistanceSegmentAccumulator(
            policy: try policy(),
            segmentStartUptimeNanoseconds: 1_000
        )
        #expect(
            accumulator.record(try sample(speed: 2, uptime: 999))
                == .rejected(.beforeSegmentStart)
        )
        #expect(accumulator.snapshot.acceptedSampleCount == 0)
    }

    @Test("zero speed intervals produce real zero distance evidence")
    func measuredZeroDistanceIsNotUnavailable() throws {
        var accumulator = LiveDistanceSegmentAccumulator(
            policy: try policy(),
            segmentStartUptimeNanoseconds: 0
        )
        accumulator.record(try sample(speed: 0, uptime: 0))
        accumulator.record(try sample(speed: 0, uptime: 500_000_000))
        #expect(accumulator.snapshot.distanceMeters == 0)
        #expect(accumulator.snapshot.hasKnownCoverageGap == false)
        #expect(
            try accumulator.finalize(segmentEndUptimeNanoseconds: 500_000_000).coverage == .complete)
    }

    @Test("finalization marks any unmeasured segment tail partial instead of extrapolating")
    func trailingGapIsPartial() throws {
        var accumulator = LiveDistanceSegmentAccumulator(
            policy: try policy(),
            segmentStartUptimeNanoseconds: 0
        )
        accumulator.record(try sample(speed: 5, uptime: 0))
        accumulator.record(try sample(speed: 5, uptime: 500_000_000))

        let exact = try accumulator.finalize(segmentEndUptimeNanoseconds: 500_000_000)
        #expect(exact.coverage == .complete)
        #expect(exact.distanceMeters == 2.5)

        let later = try accumulator.finalize(segmentEndUptimeNanoseconds: 500_000_001)
        #expect(later.coverage == .partial)
        #expect(later.distanceMeters == 2.5)
        #expect(later.knownCoverageGapCount == 1)
    }

    @Test("finalization cannot end before segment start or before an accepted sample")
    func invalidSegmentEndRejected() throws {
        var accumulator = LiveDistanceSegmentAccumulator(
            policy: try policy(),
            segmentStartUptimeNanoseconds: 100
        )
        #expect(throws: LiveDistanceIntegrationError.invalidSegmentEnd) {
            try accumulator.finalize(segmentEndUptimeNanoseconds: 99)
        }
        accumulator.record(try sample(speed: 3, uptime: 200))
        #expect(throws: LiveDistanceIntegrationError.invalidSegmentEnd) {
            try accumulator.finalize(segmentEndUptimeNanoseconds: 199)
        }
    }

    @Test("distance overflow preserves accepted evidence, closes chronology, and marks a gap")
    func overflowPreservesAcceptedEvidenceAndConsumesChronology() throws {
        var accumulator = LiveDistanceSegmentAccumulator(
            policy: try policy(maximumGap: 3_000_000_000),
            segmentStartUptimeNanoseconds: 0
        )
        accumulator.record(try sample(speed: Double.greatestFiniteMagnitude, uptime: 0))
        let before = accumulator.snapshot
        #expect(
            accumulator.record(
                try sample(speed: Double.greatestFiniteMagnitude, uptime: 2_000_000_000)
            ) == .rejected(.distanceOverflow)
        )

        let afterOverflow = accumulator.snapshot
        #expect(afterOverflow.lastAcceptedSampleUptimeNanoseconds == before.lastAcceptedSampleUptimeNanoseconds)
        #expect(afterOverflow.distanceMeters == before.distanceMeters)
        #expect(afterOverflow.acceptedSampleCount == before.acceptedSampleCount)
        #expect(afterOverflow.integratedIntervalCount == before.integratedIntervalCount)
        #expect(afterOverflow.knownCoverageGapCount == before.knownCoverageGapCount + 1)
        #expect(afterOverflow.hasKnownCoverageGap)

        #expect(
            accumulator.record(try sample(speed: 0, uptime: 1_000_000_000))
                == .rejected(.nonIncreasingTimestamp)
        )
        #expect(accumulator.snapshot == afterOverflow)
    }

    @Test("finalizing without an integrated interval remains unavailable rather than fake zero")
    func finalizeWithoutIntervalIsUnavailable() throws {
        var accumulator = LiveDistanceSegmentAccumulator(
            policy: try policy(),
            segmentStartUptimeNanoseconds: 0
        )
        accumulator.record(try sample(speed: 8, uptime: 10))
        let final = try accumulator.finalize(segmentEndUptimeNanoseconds: 20)
        #expect(final.distanceMeters == nil)
        #expect(final.coverage == .unknown)
        #expect(final.knownCoverageGapCount == 2)
    }
}