import Foundation
import Testing

@testable import NembraCore

@Suite("Ride session duration evidence")
struct RideSessionDurationEvidenceTests {
    private let sessionID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    private let firstProcessID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    private let secondProcessID = UUID(uuidString: "66666666-7777-8888-9999-AAAAAAAAAAAA")!
    private let firstSegmentID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    private let secondSegmentID = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!

    private func segment(
        segmentID: UUID,
        processID: UUID,
        sequence: UInt64,
        from start: UInt64 = 100,
        through end: UInt64,
        followsGap: Bool
    ) throws -> RideSessionDurationObservedSegment {
        try RideSessionDurationObservedSegment(
            sessionID: sessionID,
            segmentID: segmentID,
            processGenerationID: processID,
            sequenceNumber: sequence,
            observedFromUptimeNanoseconds: start,
            observedThroughUptimeNanoseconds: end,
            followsUnobservedInterval: followsGap
        )
    }

    @Test("no monotonic segment is unavailable rather than fake zero")
    func emptyIsUnknown() {
        let accumulator = RideSessionDurationEvidenceAccumulator(sessionID: sessionID)
        #expect(accumulator.snapshot.observedDurationNanoseconds == nil)
        #expect(accumulator.snapshot.coverage == .unknown)
        #expect(accumulator.snapshot.observationSegmentCount == 0)
    }

    @Test("an observed zero duration remains real zero evidence")
    func observedZeroIsDistinctFromUnavailable() throws {
        var accumulator = RideSessionDurationEvidenceAccumulator(sessionID: sessionID)
        let result = try accumulator.upsert(
            segment(
                segmentID: firstSegmentID,
                processID: firstProcessID,
                sequence: 0,
                through: 100,
                followsGap: false
            )
        )

        #expect(result == .inserted)
        #expect(accumulator.snapshot.observedDurationNanoseconds == 0)
        #expect(accumulator.snapshot.coverage == .complete)
        #expect(accumulator.snapshot.observationSegmentCount == 1)
    }

    @Test("same observation segment checkpoints extend only by newly observed time")
    func segmentCheckpointExtensionIsDeltaOnly() throws {
        var accumulator = RideSessionDurationEvidenceAccumulator(sessionID: sessionID)
        try accumulator.upsert(
            segment(
                segmentID: firstSegmentID,
                processID: firstProcessID,
                sequence: 0,
                through: 1_000,
                followsGap: false
            )
        )

        let result = try accumulator.upsert(
            segment(
                segmentID: firstSegmentID,
                processID: firstProcessID,
                sequence: 0,
                through: 1_600,
                followsGap: false
            )
        )

        #expect(result == .extended(additionalNanoseconds: 600))
        #expect(accumulator.snapshot.observedDurationNanoseconds == 1_500)
        #expect(accumulator.snapshot.observationSegmentCount == 1)
    }

    @Test("identical retry is idempotent and an older retry cannot roll duration back")
    func retriesAreMonotonic() throws {
        var accumulator = RideSessionDurationEvidenceAccumulator(sessionID: sessionID)
        let current = try segment(
            segmentID: firstSegmentID,
            processID: firstProcessID,
            sequence: 0,
            through: 1_600,
            followsGap: false
        )
        try accumulator.upsert(current)
        let before = accumulator.snapshot

        let identicalResult = try accumulator.upsert(current)
        let staleResult = try accumulator.upsert(
            segment(
                segmentID: firstSegmentID,
                processID: firstProcessID,
                sequence: 0,
                through: 1_200,
                followsGap: false
            )
        )

        #expect(identicalResult == .idempotentReplay)
        #expect(staleResult == .staleReplayIgnored)
        #expect(accumulator.snapshot == before)
    }

    @Test("an in-process interruption becomes a new partial observation segment")
    func inProcessGapDoesNotRequireFakeProcessIdentity() throws {
        var accumulator = RideSessionDurationEvidenceAccumulator(sessionID: sessionID)
        try accumulator.upsert(
            segment(
                segmentID: firstSegmentID,
                processID: firstProcessID,
                sequence: 0,
                through: 1_100,
                followsGap: false
            )
        )
        try accumulator.upsert(
            segment(
                segmentID: secondSegmentID,
                processID: firstProcessID,
                sequence: 1,
                from: 5_000,
                through: 5_400,
                followsGap: true
            )
        )

        #expect(accumulator.snapshot.observedDurationNanoseconds == 1_400)
        #expect(accumulator.snapshot.coverage == .partial)
        #expect(accumulator.snapshot.hasUnobservedInterval)
        #expect(accumulator.snapshot.observationSegmentCount == 2)
    }

    @Test("relaunch recovery adds only observed time and marks coverage partial")
    func recoveryDoesNotInventMissingTime() throws {
        var accumulator = RideSessionDurationEvidenceAccumulator(sessionID: sessionID)
        try accumulator.upsert(
            segment(
                segmentID: firstSegmentID,
                processID: firstProcessID,
                sequence: 0,
                through: 1_100,
                followsGap: false
            )
        )
        try accumulator.upsert(
            segment(
                segmentID: secondSegmentID,
                processID: secondProcessID,
                sequence: 1,
                from: 5_000,
                through: 5_400,
                followsGap: true
            )
        )

        #expect(accumulator.snapshot.observedDurationNanoseconds == 1_400)
        #expect(accumulator.snapshot.coverage == .partial)
        #expect(accumulator.snapshot.observationSegmentCount == 2)
    }

    @Test("a later segment must explicitly acknowledge its unobserved interval")
    func laterGapIsMandatory() throws {
        var accumulator = RideSessionDurationEvidenceAccumulator(sessionID: sessionID)
        try accumulator.upsert(
            segment(
                segmentID: firstSegmentID,
                processID: firstProcessID,
                sequence: 0,
                through: 200,
                followsGap: false
            )
        )
        let before = accumulator.snapshot

        #expect(throws: RideSessionDurationEvidenceError.invalidGapClassification) {
            try accumulator.upsert(
                segment(
                    segmentID: secondSegmentID,
                    processID: firstProcessID,
                    sequence: 1,
                    through: 300,
                    followsGap: false
                )
            )
        }
        #expect(accumulator.snapshot == before)
    }

    @Test("first segment cannot falsely claim a preceding observation gap")
    func firstSegmentGapFlagRejected() throws {
        var accumulator = RideSessionDurationEvidenceAccumulator(sessionID: sessionID)
        #expect(throws: RideSessionDurationEvidenceError.invalidGapClassification) {
            try accumulator.upsert(
                segment(
                    segmentID: firstSegmentID,
                    processID: firstProcessID,
                    sequence: 0,
                    through: 200,
                    followsGap: true
                )
            )
        }
        #expect(accumulator.snapshot.coverage == .unknown)
    }

    @Test("same sequence cannot change segment or gap identity")
    func replayCannotChangeSegmentIdentity() throws {
        var accumulator = RideSessionDurationEvidenceAccumulator(sessionID: sessionID)
        try accumulator.upsert(
            segment(
                segmentID: firstSegmentID,
                processID: firstProcessID,
                sequence: 0,
                through: 200,
                followsGap: false
            )
        )

        #expect(throws: RideSessionDurationEvidenceError.conflictingSegmentIdentity) {
            try accumulator.upsert(
                segment(
                    segmentID: secondSegmentID,
                    processID: firstProcessID,
                    sequence: 0,
                    through: 250,
                    followsGap: false
                )
            )
        }
    }

    @Test("same sequence cannot change its process generation")
    func replayCannotChangeProcessGeneration() throws {
        var accumulator = RideSessionDurationEvidenceAccumulator(sessionID: sessionID)
        try accumulator.upsert(
            segment(
                segmentID: firstSegmentID,
                processID: firstProcessID,
                sequence: 0,
                through: 200,
                followsGap: false
            )
        )

        #expect(throws: RideSessionDurationEvidenceError.conflictingSegmentIdentity) {
            try accumulator.upsert(
                segment(
                    segmentID: firstSegmentID,
                    processID: secondProcessID,
                    sequence: 0,
                    through: 250,
                    followsGap: false
                )
            )
        }
    }

    @Test("sequence gaps fail closed instead of silently losing an interval")
    func sequenceGapRejected() throws {
        var accumulator = RideSessionDurationEvidenceAccumulator(sessionID: sessionID)
        try accumulator.upsert(
            segment(
                segmentID: firstSegmentID,
                processID: firstProcessID,
                sequence: 0,
                through: 200,
                followsGap: false
            )
        )

        #expect(throws: RideSessionDurationEvidenceError.unexpectedSequence) {
            try accumulator.upsert(
                segment(
                    segmentID: secondSegmentID,
                    processID: secondProcessID,
                    sequence: 2,
                    through: 300,
                    followsGap: true
                )
            )
        }
    }

    @Test("one segment identity cannot be counted under two sequence numbers")
    func segmentIdentityReuseRejected() throws {
        var accumulator = RideSessionDurationEvidenceAccumulator(sessionID: sessionID)
        try accumulator.upsert(
            segment(
                segmentID: firstSegmentID,
                processID: firstProcessID,
                sequence: 0,
                through: 200,
                followsGap: false
            )
        )

        #expect(throws: RideSessionDurationEvidenceError.segmentIdentityReused) {
            try accumulator.upsert(
                segment(
                    segmentID: firstSegmentID,
                    processID: firstProcessID,
                    sequence: 1,
                    through: 300,
                    followsGap: true
                )
            )
        }
    }

    @Test("foreign ride session cannot enter the accumulator")
    func sessionMixingRejected() throws {
        var accumulator = RideSessionDurationEvidenceAccumulator(sessionID: sessionID)
        let foreign = try RideSessionDurationObservedSegment(
            sessionID: UUID(),
            segmentID: firstSegmentID,
            processGenerationID: firstProcessID,
            sequenceNumber: 0,
            observedFromUptimeNanoseconds: 0,
            observedThroughUptimeNanoseconds: 1,
            followsUnobservedInterval: false
        )

        #expect(throws: RideSessionDurationEvidenceError.sessionMismatch) {
            try accumulator.upsert(foreign)
        }
    }

    @Test("process-local monotonic segment cannot run backwards")
    func backwardsUptimeRejected() {
        #expect(throws: RideSessionDurationEvidenceError.invalidObservationSegment) {
            try RideSessionDurationObservedSegment(
                sessionID: sessionID,
                segmentID: firstSegmentID,
                processGenerationID: firstProcessID,
                sequenceNumber: 0,
                observedFromUptimeNanoseconds: 200,
                observedThroughUptimeNanoseconds: 199,
                followsUnobservedInterval: false
            )
        }
    }

    @Test("aggregate duration overflow fails transactionally")
    func aggregateOverflowRejected() throws {
        var accumulator = RideSessionDurationEvidenceAccumulator(sessionID: sessionID)
        try accumulator.upsert(
            segment(
                segmentID: firstSegmentID,
                processID: firstProcessID,
                sequence: 0,
                from: 0,
                through: UInt64.max,
                followsGap: false
            )
        )
        let before = accumulator.snapshot

        #expect(throws: RideSessionDurationEvidenceError.durationOverflow) {
            try accumulator.upsert(
                segment(
                    segmentID: secondSegmentID,
                    processID: secondProcessID,
                    sequence: 1,
                    from: 0,
                    through: 1,
                    followsGap: true
                )
            )
        }
        #expect(accumulator.snapshot == before)
    }

    @Test("Codable round trip preserves checked observed duration evidence")
    func codableRoundTrip() throws {
        var accumulator = RideSessionDurationEvidenceAccumulator(sessionID: sessionID)
        try accumulator.upsert(
            segment(
                segmentID: firstSegmentID,
                processID: firstProcessID,
                sequence: 0,
                through: 1_100,
                followsGap: false
            )
        )
        try accumulator.upsert(
            segment(
                segmentID: secondSegmentID,
                processID: secondProcessID,
                sequence: 1,
                from: 4_000,
                through: 4_500,
                followsGap: true
            )
        )

        let data = try JSONEncoder().encode(accumulator)
        let decoded = try JSONDecoder().decode(
            RideSessionDurationEvidenceAccumulator.self,
            from: data
        )

        #expect(decoded == accumulator)
        #expect(decoded.snapshot.observedDurationNanoseconds == 1_500)
        #expect(decoded.snapshot.coverage == .partial)
    }

    @Test("malformed persisted sequence is rejected during decode")
    func malformedSequencePersistenceRejected() {
        let data = Data(
            """
            {
              "sessionID": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
              "observationSegments": [
                {
                  "sessionID": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
                  "segmentID": "20000000-0000-0000-0000-000000000002",
                  "processGenerationID": "66666666-7777-8888-9999-AAAAAAAAAAAA",
                  "sequenceNumber": 1,
                  "observedDurationNanoseconds": 50,
                  "followsUnobservedInterval": true
                }
              ]
            }
            """.utf8
        )

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(RideSessionDurationEvidenceAccumulator.self, from: data)
        }
    }

    @Test("persisted child segment cannot claim a different ride session")
    func malformedSessionPersistenceRejected() {
        let data = Data(
            """
            {
              "sessionID": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
              "observationSegments": [
                {
                  "sessionID": "00000000-0000-0000-0000-000000000001",
                  "segmentID": "10000000-0000-0000-0000-000000000001",
                  "processGenerationID": "11111111-2222-3333-4444-555555555555",
                  "sequenceNumber": 0,
                  "observedDurationNanoseconds": 50,
                  "followsUnobservedInterval": false
                }
              ]
            }
            """.utf8
        )

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(RideSessionDurationEvidenceAccumulator.self, from: data)
        }
    }
}
