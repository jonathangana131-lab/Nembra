import Foundation
import Testing

@testable import NembraCore

@Suite("Ride duration cockpit presentation")
struct RideDurationCockpitPresentationTests {
    private let sessionID = UUID(uuidString: "A1100000-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    private let processID = UUID(uuidString: "B2200000-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    private let firstSegmentID = UUID(uuidString: "C3300000-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    private let secondSegmentID = UUID(uuidString: "D4400000-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

    @Test("unknown evidence stays unavailable instead of becoming zero")
    func unknownStaysUnavailable() {
        let accumulator = RideSessionDurationEvidenceAccumulator(sessionID: sessionID)

        #expect(
            RideDurationCockpitState(snapshot: accumulator.snapshot)
                == .unavailable(sessionID: sessionID)
        )
    }

    @Test("an actually observed zero remains a real zero-duration value")
    func observedZeroRemainsObserved() throws {
        var accumulator = RideSessionDurationEvidenceAccumulator(sessionID: sessionID)
        try accumulator.upsert(
            segment(
                id: firstSegmentID,
                sequence: 0,
                from: 500,
                through: 500,
                followsGap: false
            )
        )

        guard case let .observed(value) = RideDurationCockpitState(snapshot: accumulator.snapshot) else {
            Issue.record("Expected observed cockpit duration")
            return
        }
        #expect(value.observedDurationNanoseconds == 0)
        #expect(value.wholeObservedSeconds == 0)
        #expect(value.observationSegmentCount == 1)
        #expect(value.role == .elapsedObserved)
    }

    @Test("complete observed duration projects whole seconds without altering exact evidence")
    func completeDurationProjectsConservatively() throws {
        var accumulator = RideSessionDurationEvidenceAccumulator(sessionID: sessionID)
        try accumulator.upsert(
            segment(
                id: firstSegmentID,
                sequence: 0,
                from: 10_000,
                through: 3_500_010_000,
                followsGap: false
            )
        )

        guard case let .observed(value) = RideDurationCockpitState(snapshot: accumulator.snapshot) else {
            Issue.record("Expected observed cockpit duration")
            return
        }
        #expect(value.observedDurationNanoseconds == 3_500_000_000)
        #expect(value.wholeObservedSeconds == 3)
        #expect(value.role == .elapsedObserved)
    }

    @Test("a known observation gap changes the product meaning to partial observed time")
    func partialCoverageIsQualified() throws {
        var accumulator = RideSessionDurationEvidenceAccumulator(sessionID: sessionID)
        try accumulator.upsert(
            segment(
                id: firstSegmentID,
                sequence: 0,
                from: 100,
                through: 2_000_000_100,
                followsGap: false
            )
        )
        try accumulator.upsert(
            segment(
                id: secondSegmentID,
                sequence: 1,
                from: 9_000_000_000,
                through: 10_500_000_000,
                followsGap: true
            )
        )

        guard case let .observed(value) = RideDurationCockpitState(snapshot: accumulator.snapshot) else {
            Issue.record("Expected observed cockpit duration")
            return
        }
        #expect(value.observedDurationNanoseconds == 3_500_000_000)
        #expect(value.wholeObservedSeconds == 3)
        #expect(value.observationSegmentCount == 2)
        #expect(value.role == .partialObserved)
    }

    @Test("recovery beginning after an unobserved interval never claims complete elapsed time")
    func recoveryStartsPartial() throws {
        var accumulator = RideSessionDurationEvidenceAccumulator(
            sessionID: sessionID,
            beginsAfterUnobservedInterval: true
        )
        try accumulator.upsert(
            segment(
                id: firstSegmentID,
                sequence: 0,
                from: 20_000,
                through: 1_250_020_000,
                followsGap: true
            )
        )

        guard case let .observed(value) = RideDurationCockpitState(snapshot: accumulator.snapshot) else {
            Issue.record("Expected partial observed cockpit duration")
            return
        }
        #expect(value.wholeObservedSeconds == 1)
        #expect(value.role == .partialObserved)
    }

    @Test("malformed unknown snapshot with a numeric duration fails closed")
    func contradictoryUnknownSnapshotFailsClosed() {
        let snapshot = RideSessionDurationEvidenceSnapshot(
            sessionID: sessionID,
            observedDurationNanoseconds: 1_000_000_000,
            coverage: .unknown,
            observationSegmentCount: 1
        )

        #expect(
            RideDurationCockpitState(snapshot: snapshot)
                == .unavailable(sessionID: sessionID)
        )
    }

    @Test("malformed complete snapshot with multiple segments fails closed")
    func impossibleCompleteSegmentCountFailsClosed() {
        let snapshot = RideSessionDurationEvidenceSnapshot(
            sessionID: sessionID,
            observedDurationNanoseconds: 2_000_000_000,
            coverage: .complete,
            observationSegmentCount: 2
        )

        #expect(
            RideDurationCockpitState(snapshot: snapshot)
                == .unavailable(sessionID: sessionID)
        )
    }

    @Test("malformed partial snapshot without a segment fails closed")
    func impossiblePartialSegmentCountFailsClosed() {
        let snapshot = RideSessionDurationEvidenceSnapshot(
            sessionID: sessionID,
            observedDurationNanoseconds: 2_000_000_000,
            coverage: .partial,
            observationSegmentCount: 0
        )

        #expect(
            RideDurationCockpitState(snapshot: snapshot)
                == .unavailable(sessionID: sessionID)
        )
    }

    @Test("missing duration fails closed even if coverage metadata claims complete")
    func missingNumericDurationFailsClosed() {
        let snapshot = RideSessionDurationEvidenceSnapshot(
            sessionID: sessionID,
            observedDurationNanoseconds: nil,
            coverage: .complete,
            observationSegmentCount: 1
        )

        #expect(
            RideDurationCockpitState(snapshot: snapshot)
                == .unavailable(sessionID: sessionID)
        )
    }

    @Test("whole-second projection remains safe at the maximum UInt64 duration")
    func maximumDurationProjectionDoesNotOverflow() {
        let snapshot = RideSessionDurationEvidenceSnapshot(
            sessionID: sessionID,
            observedDurationNanoseconds: .max,
            coverage: .complete,
            observationSegmentCount: 1
        )

        guard case let .observed(value) = RideDurationCockpitState(snapshot: snapshot) else {
            Issue.record("Expected observed cockpit duration")
            return
        }
        #expect(value.observedDurationNanoseconds == UInt64.max)
        #expect(value.wholeObservedSeconds == UInt64.max / 1_000_000_000)
    }

    private func segment(
        id: UUID,
        sequence: UInt64,
        from start: UInt64,
        through end: UInt64,
        followsGap: Bool
    ) throws -> RideSessionDurationObservedSegment {
        try RideSessionDurationObservedSegment(
            sessionID: sessionID,
            segmentID: id,
            processGenerationID: processID,
            sequenceNumber: sequence,
            observedFromUptimeNanoseconds: start,
            observedThroughUptimeNanoseconds: end,
            followsUnobservedInterval: followsGap
        )
    }
}
