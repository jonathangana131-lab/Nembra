import Foundation
import Testing

@testable import NembraCore

@Suite("Ride session duration evidence")
struct RideSessionDurationEvidenceTests {
    private let sessionID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    private let firstProcessID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    private let secondProcessID = UUID(uuidString: "66666666-7777-8888-9999-AAAAAAAAAAAA")!

    private func segment(
        processID: UUID,
        sequence: UInt64,
        from start: UInt64 = 100,
        through end: UInt64,
        followsGap: Bool
    ) throws -> RideSessionDurationProcessSegment {
        try RideSessionDurationProcessSegment(
            sessionID: sessionID,
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
        #expect(accumulator.snapshot.processSegmentCount == 0)
    }

    @Test("an observed zero duration remains real zero evidence")
    func observedZeroIsDistinctFromUnavailable() throws {
        var accumulator = RideSessionDurationEvidenceAccumulator(sessionID: sessionID)
        let result = try accumulator.upsert(
            segment(
                processID: firstProcessID,
                sequence: 0,
                through: 100,
                followsGap: false
            )
        )

        #expect(result == .inserted)
        #expect(accumulator.snapshot.observedDurationNanoseconds == 0)
        #expect(accumulator.snapshot.coverage == .complete)
        #expect(accumulator.snapshot.processSegmentCount == 1)
    }

    @Test("same-process checkpoints extend only by newly observed monotonic time")
    func processCheckpointExtensionIsDeltaOnly() throws {
        var accumulator = RideSessionDurationEvidenceAccumulator(sessionID: sessionID)
        try accumulator.upsert(
            segment(
                processID: firstProcessID,
                sequence: 0,
                through: 1_000,
                followsGap: false
            )
        )

        let result = try accumulator.upsert(
            segment(
                processID: firstProcessID,
                sequence: 0,
                through: 1_600,
                followsGap: false
            )
        )

        #expect(result == .extended(additionalNanoseconds: 600))
        #expect(accumulator.snapshot.observedDurationNanoseconds == 1_500)
        #expect(accumulator.snapshot.processSegmentCount == 1)
    }

    @Test("identical retry is idempotent and an older retry cannot roll duration back")
    func retriesAreMonotonic() throws {
        var accumulator = RideSessionDurationEvidenceAccumulator(sessionID: sessionID)
        let current = try segment(
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

    @Test("recovery process adds only observed time and marks coverage partial")
    func recoveryDoesNotInventMissingTime() throws {
        var accumulator = RideSessionDurationEvidenceAccumulator(sessionID: sessionID)
        try accumulator.upsert(
            segment(
                processID: firstProcessID,
                sequence: 0,
                through: 1_100,
                followsGap: false
            )
        )
        try accumulator.upsert(
            segment(
                processID: secondProcessID,
                sequence: 1,
                from: 5_000,
                through: 5_400,
                followsGap: true
            )
        )

        #expect(accumulator.snapshot.observedDurationNanoseconds == 1_400)
        #expect(accumulator.snapshot.coverage == .partial)
        #expect(accumulator.snapshot.hasUnobservedInterval)
        #expect(accumulator.snapshot.processSegmentCount == 2)
    }

    @Test("new process generation must explicitly acknowledge the unobserved interval")
    func recoveryGapIsMandatory() throws {
        var accumulator = RideSessionDurationEvidenceAccumulator(sessionID: sessionID)
        try accumulator.upsert(
            segment(
                processID: firstProcessID,
                sequence: 0,
                through: 200,
                followsGap: false
            )
        )
        let before = accumulator.snapshot

        #expect(throws: RideSessionDurationEvidenceError.missingRecoveryGap) {
            try accumulator.upsert(
                segment(
                    processID: secondProcessID,
                    sequence: 1,
                    through: 300,
                    followsGap: false
                )
            )
        }
        #expect(accumulator.snapshot == before)
    }

    @Test("first process cannot falsely claim it followed a recovery gap")
    func firstProcessGapFlagRejected() throws {
        var accumulator = RideSessionDurationEvidenceAccumulator(sessionID: sessionID)
        #expect(throws: RideSessionDurationEvidenceError.missingRecoveryGap) {
            try accumulator.upsert(
                segment(
                    processID: firstProcessID,
                    sequence: 0,
                    through: 200,
                    followsGap: true
                )
            )
        }
        #expect(accumulator.snapshot.coverage == .unknown)
    }

    @Test("same sequence cannot change its recovery-gap classification")
    func replayCannotChangeGapClassification() throws {
        var accumulator = RideSessionDurationEvidenceAccumulator(sessionID: sessionID)
        try accumulator.upsert(
            segment(
                processID: firstProcessID,
                sequence: 0,
                through: 200,
                followsGap: false
            )
        )

        #expect(throws: RideSessionDurationEvidenceError.conflictingProcessGeneration) {
            try accumulator.upsert(
                segment(
                    processID: firstProcessID,
                    sequence: 0,
                    through: 250,
                    followsGap: true
                )
            )
        }
    }

    @Test("sequence gaps fail closed instead of silently losing a process interval")
    func sequenceGapRejected() throws {
        var accumulator = RideSessionDurationEvidenceAccumulator(sessionID: sessionID)
        try accumulator.upsert(
            segment(
                processID: firstProcessID,
                sequence: 0,
                through: 200,
                followsGap: false
            )
        )

        #expect(throws: RideSessionDurationEvidenceError.unexpectedSequence) {
            try accumulator.upsert(
                segment(
                    processID: secondProcessID,
                    sequence: 2,
                    through: 300,
                    followsGap: true
                )
            )
        }
    }

    @Test("a process generation cannot be counted twice under different sequences")
    func processGenerationReuseRejected() throws {
        var accumulator = RideSessionDurationEvidenceAccumulator(sessionID: sessionID)
        try accumulator.upsert(
            segment(
                processID: firstProcessID,
                sequence: 0,
                through: 200,
                followsGap: false
            )
        )

        #expect(throws: RideSessionDurationEvidenceError.processGenerationReused) {
            try accumulator.upsert(
                segment(
                    processID: firstProcessID,
                    sequence: 1,
                    through: 300,
                    followsGap: true
                )
            )
        }
    }

    @Test("same sequence with different process identity is conflicting replay")
    func conflictingSequenceRejected() throws {
        var accumulator = RideSessionDurationEvidenceAccumulator(sessionID: sessionID)
        try accumulator.upsert(
            segment(
                processID: firstProcessID,
                sequence: 0,
                through: 200,
                followsGap: false
            )
        )

        #expect(throws: RideSessionDurationEvidenceError.conflictingProcessGeneration) {
            try accumulator.upsert(
                segment(
                    processID: secondProcessID,
                    sequence: 0,
                    through: 200,
                    followsGap: false
                )
            )
        }
    }

    @Test("foreign ride session cannot enter the accumulator")
    func sessionMixingRejected() throws {
        var accumulator = RideSessionDurationEvidenceAccumulator(sessionID: sessionID)
        let foreign = try RideSessionDurationProcessSegment(
            sessionID: UUID(),
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
        #expect(throws: RideSessionDurationEvidenceError.invalidProcessSegment) {
            try RideSessionDurationProcessSegment(
                sessionID: sessionID,
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

    @Test("Codable round trip preserves only checked observed duration evidence")
    func codableRoundTrip() throws {
        var accumulator = RideSessionDurationEvidenceAccumulator(sessionID: sessionID)
        try accumulator.upsert(
            segment(
                processID: firstProcessID,
                sequence: 0,
                through: 1_100,
                followsGap: false
            )
        )
        try accumulator.upsert(
            segment(
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
              "processSegments": [
                {
                  "sessionID": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
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
              "processSegments": [
                {
                  "sessionID": "00000000-0000-0000-0000-000000000001",
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
