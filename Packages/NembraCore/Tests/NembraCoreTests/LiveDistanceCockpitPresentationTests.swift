import Foundation
import Testing

@testable import NembraCore

@Suite("Live distance cockpit presentation")
struct LiveDistanceCockpitPresentationTests {
    @Test("no accepted interval stays unavailable instead of becoming zero")
    func noDistanceEvidenceStaysUnavailable() throws {
        var accumulator = try makeAccumulator(segmentStart: 100)

        #expect(LiveDistanceCockpitState(snapshot: accumulator.snapshot) == .unavailable)

        _ = accumulator.record(try sample(speed: 2, uptime: 100))
        #expect(LiveDistanceCockpitState(snapshot: accumulator.snapshot) == .unavailable)
    }

    @Test("an actually integrated zero-meter interval remains a real observed zero")
    func integratedZeroRemainsObserved() throws {
        var accumulator = try makeAccumulator(segmentStart: 100)
        _ = accumulator.record(try sample(speed: 0, uptime: 100))
        _ = accumulator.record(try sample(speed: 0, uptime: 1_000_000_100))

        guard case let .observed(value) = LiveDistanceCockpitState(snapshot: accumulator.snapshot) else {
            Issue.record("Expected observed live distance")
            return
        }

        #expect(value.distanceMeters == 0)
        #expect(value.acceptedSampleCount == 2)
        #expect(value.integratedIntervalCount == 1)
        #expect(value.knownCoverageGapCount == 0)
        #expect(value.role == .observedNoRecordedGap)
        #expect(value.source == .gps)
        #expect(value.method == .trapezoidalBetweenMeasurements)
    }

    @Test("accepted integration preserves exact meters without claiming finalized ride coverage")
    func acceptedDistanceProjectsExactSubtotal() throws {
        var accumulator = try makeAccumulator(segmentStart: 0)
        _ = accumulator.record(try sample(speed: 1, uptime: 0))
        _ = accumulator.record(try sample(speed: 3, uptime: 1_000_000_000))

        guard case let .observed(value) = LiveDistanceCockpitState(snapshot: accumulator.snapshot) else {
            Issue.record("Expected observed live distance")
            return
        }

        #expect(value.distanceMeters == 2)
        #expect(value.role == .observedNoRecordedGap)
    }

    @Test("a known initial observation hole qualifies the numeric value as partial")
    func initialGapMakesSubtotalPartial() throws {
        var accumulator = try makeAccumulator(segmentStart: 100)
        _ = accumulator.record(try sample(speed: 1, uptime: 200))
        _ = accumulator.record(try sample(speed: 1, uptime: 1_000_000_200))

        guard case let .observed(value) = LiveDistanceCockpitState(snapshot: accumulator.snapshot) else {
            Issue.record("Expected partial observed live distance")
            return
        }

        #expect(value.distanceMeters == 1)
        #expect(value.knownCoverageGapCount == 1)
        #expect(value.role == .partialObserved)
    }

    @Test("a later oversized interval preserves the accepted subtotal but exposes partial evidence")
    func oversizedIntervalMakesSubtotalPartial() throws {
        var accumulator = try makeAccumulator(
            segmentStart: 0,
            maximumIntervalNanoseconds: 1_500_000_000
        )
        _ = accumulator.record(try sample(speed: 1, uptime: 0))
        _ = accumulator.record(try sample(speed: 1, uptime: 1_000_000_000))
        let result = accumulator.record(try sample(speed: 1, uptime: 5_000_000_000))

        #expect(result == .gapDetected(intervalNanoseconds: 4_000_000_000))

        guard case let .observed(value) = LiveDistanceCockpitState(snapshot: accumulator.snapshot) else {
            Issue.record("Expected partial observed live distance")
            return
        }

        #expect(value.distanceMeters == 1)
        #expect(value.acceptedSampleCount == 3)
        #expect(value.integratedIntervalCount == 1)
        #expect(value.knownCoverageGapCount == 1)
        #expect(value.role == .partialObserved)
    }

    @Test("leading and later interval gaps remain independently accounted partial evidence")
    func leadingAndIntervalGapsRemainPartial() throws {
        var accumulator = try makeAccumulator(
            segmentStart: 100,
            maximumIntervalNanoseconds: 1_500_000_000
        )
        _ = accumulator.record(try sample(speed: 1, uptime: 200))
        _ = accumulator.record(try sample(speed: 1, uptime: 1_000_000_200))
        let result = accumulator.record(try sample(speed: 1, uptime: 5_000_000_200))

        #expect(result == .gapDetected(intervalNanoseconds: 4_000_000_000))

        guard case let .observed(value) = LiveDistanceCockpitState(snapshot: accumulator.snapshot) else {
            Issue.record("Expected partial observed live distance")
            return
        }

        #expect(value.distanceMeters == 1)
        #expect(value.acceptedSampleCount == 3)
        #expect(value.integratedIntervalCount == 1)
        #expect(value.knownCoverageGapCount == 2)
        #expect(value.role == .partialObserved)
    }

    @Test("contradictory empty snapshot fails closed")
    func contradictoryEmptySnapshotFailsClosed() {
        let snapshot = LiveDistanceSegmentSnapshot(
            source: .gps,
            method: .trapezoidalBetweenMeasurements,
            segmentStartUptimeNanoseconds: 100,
            firstAcceptedSampleUptimeNanoseconds: nil,
            lastAcceptedSampleUptimeNanoseconds: nil,
            distanceMeters: 12,
            hasKnownCoverageGap: false,
            acceptedSampleCount: 0,
            integratedIntervalCount: 0,
            knownCoverageGapCount: 0
        )

        #expect(LiveDistanceCockpitState(snapshot: snapshot) == .unavailable)
    }

    @Test("impossible interval count fails closed")
    func impossibleIntervalCountFailsClosed() {
        let snapshot = LiveDistanceSegmentSnapshot(
            source: .gps,
            method: .trapezoidalBetweenMeasurements,
            segmentStartUptimeNanoseconds: 100,
            firstAcceptedSampleUptimeNanoseconds: 100,
            lastAcceptedSampleUptimeNanoseconds: 100,
            distanceMeters: 0,
            hasKnownCoverageGap: false,
            acceptedSampleCount: 1,
            integratedIntervalCount: 1,
            knownCoverageGapCount: 0
        )

        #expect(LiveDistanceCockpitState(snapshot: snapshot) == .unavailable)
    }

    @Test("a missing accepted interval cannot masquerade as gap-free evidence")
    func unrecordedMissingIntervalFailsClosed() {
        let snapshot = LiveDistanceSegmentSnapshot(
            source: .gps,
            method: .trapezoidalBetweenMeasurements,
            segmentStartUptimeNanoseconds: 100,
            firstAcceptedSampleUptimeNanoseconds: 100,
            lastAcceptedSampleUptimeNanoseconds: 2_000_000_100,
            distanceMeters: 1,
            hasKnownCoverageGap: false,
            acceptedSampleCount: 3,
            integratedIntervalCount: 1,
            knownCoverageGapCount: 0
        )

        #expect(LiveDistanceCockpitState(snapshot: snapshot) == .unavailable)
    }

    @Test("recorded gaps must account for every non-integrated accepted interval")
    func insufficientGapAccountingFailsClosed() {
        let snapshot = LiveDistanceSegmentSnapshot(
            source: .gps,
            method: .trapezoidalBetweenMeasurements,
            segmentStartUptimeNanoseconds: 100,
            firstAcceptedSampleUptimeNanoseconds: 100,
            lastAcceptedSampleUptimeNanoseconds: 3_000_000_100,
            distanceMeters: 1,
            hasKnownCoverageGap: true,
            acceptedSampleCount: 4,
            integratedIntervalCount: 1,
            knownCoverageGapCount: 1
        )

        #expect(LiveDistanceCockpitState(snapshot: snapshot) == .unavailable)
    }

    @Test("a leading gap cannot stand in for a separate missing accepted interval")
    func leadingGapCannotPayForMissingAcceptedInterval() {
        let snapshot = LiveDistanceSegmentSnapshot(
            source: .gps,
            method: .trapezoidalBetweenMeasurements,
            segmentStartUptimeNanoseconds: 100,
            firstAcceptedSampleUptimeNanoseconds: 200,
            lastAcceptedSampleUptimeNanoseconds: 2_000_000_200,
            distanceMeters: 1,
            hasKnownCoverageGap: true,
            acceptedSampleCount: 3,
            integratedIntervalCount: 1,
            knownCoverageGapCount: 1
        )

        #expect(LiveDistanceCockpitState(snapshot: snapshot) == .unavailable)
    }

    @Test("gap flag and gap count must agree")
    func contradictoryGapMetadataFailsClosed() {
        let snapshot = LiveDistanceSegmentSnapshot(
            source: .gps,
            method: .trapezoidalBetweenMeasurements,
            segmentStartUptimeNanoseconds: 100,
            firstAcceptedSampleUptimeNanoseconds: 100,
            lastAcceptedSampleUptimeNanoseconds: 1_000_000_100,
            distanceMeters: 1,
            hasKnownCoverageGap: false,
            acceptedSampleCount: 2,
            integratedIntervalCount: 1,
            knownCoverageGapCount: 1
        )

        #expect(LiveDistanceCockpitState(snapshot: snapshot) == .unavailable)
    }

    @Test("accepted chronology cannot begin before the integration segment")
    func beforeSegmentChronologyFailsClosed() {
        let snapshot = LiveDistanceSegmentSnapshot(
            source: .gps,
            method: .trapezoidalBetweenMeasurements,
            segmentStartUptimeNanoseconds: 200,
            firstAcceptedSampleUptimeNanoseconds: 100,
            lastAcceptedSampleUptimeNanoseconds: 1_000_000_100,
            distanceMeters: 1,
            hasKnownCoverageGap: false,
            acceptedSampleCount: 2,
            integratedIntervalCount: 1,
            knownCoverageGapCount: 0
        )

        #expect(LiveDistanceCockpitState(snapshot: snapshot) == .unavailable)
    }

    @Test("multiple accepted samples require strictly increasing accepted chronology")
    func repeatedAcceptedTimestampFailsClosed() {
        let snapshot = LiveDistanceSegmentSnapshot(
            source: .gps,
            method: .trapezoidalBetweenMeasurements,
            segmentStartUptimeNanoseconds: 100,
            firstAcceptedSampleUptimeNanoseconds: 100,
            lastAcceptedSampleUptimeNanoseconds: 100,
            distanceMeters: 0,
            hasKnownCoverageGap: false,
            acceptedSampleCount: 2,
            integratedIntervalCount: 1,
            knownCoverageGapCount: 0
        )

        #expect(LiveDistanceCockpitState(snapshot: snapshot) == .unavailable)
    }

    @Test("late first evidence cannot silently erase its initial coverage gap")
    func missingInitialGapMetadataFailsClosed() {
        let snapshot = LiveDistanceSegmentSnapshot(
            source: .gps,
            method: .trapezoidalBetweenMeasurements,
            segmentStartUptimeNanoseconds: 100,
            firstAcceptedSampleUptimeNanoseconds: 200,
            lastAcceptedSampleUptimeNanoseconds: 1_000_000_200,
            distanceMeters: 1,
            hasKnownCoverageGap: false,
            acceptedSampleCount: 2,
            integratedIntervalCount: 1,
            knownCoverageGapCount: 0
        )

        #expect(LiveDistanceCockpitState(snapshot: snapshot) == .unavailable)
    }

    @Test("non-finite numeric presentation evidence fails closed")
    func nonFiniteDistanceFailsClosed() {
        let snapshot = LiveDistanceSegmentSnapshot(
            source: .gps,
            method: .trapezoidalBetweenMeasurements,
            segmentStartUptimeNanoseconds: 100,
            firstAcceptedSampleUptimeNanoseconds: 100,
            lastAcceptedSampleUptimeNanoseconds: 1_000_000_100,
            distanceMeters: .infinity,
            hasKnownCoverageGap: false,
            acceptedSampleCount: 2,
            integratedIntervalCount: 1,
            knownCoverageGapCount: 0
        )

        #expect(LiveDistanceCockpitState(snapshot: snapshot) == .unavailable)
    }

    private func makeAccumulator(
        segmentStart: UInt64,
        maximumIntervalNanoseconds: UInt64 = 2_000_000_000
    ) throws -> LiveDistanceSegmentAccumulator {
        let policy = try LiveDistanceIntegrationPolicy(
            source: .gps,
            maximumIntegrationIntervalNanoseconds: maximumIntervalNanoseconds,
            method: .trapezoidalBetweenMeasurements
        )
        return LiveDistanceSegmentAccumulator(
            policy: policy,
            segmentStartUptimeNanoseconds: segmentStart
        )
    }

    private func sample(speed: Double, uptime: UInt64) throws -> SpeedTelemetrySample {
        try SpeedTelemetrySample(
            source: .gps,
            provenance: .absoluteMeasurement,
            metersPerSecond: speed,
            receivedAtUptimeNanoseconds: uptime,
            receivedAtDate: Date(timeIntervalSinceReferenceDate: Double(uptime) / 1_000_000_000)
        )
    }
}
