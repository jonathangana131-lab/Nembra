import Testing
@testable import NembraCore

@Suite("Tuya candidate transcript receipt chronology")
struct TuyaCandidateTranscriptReceiptChronologyTests {
    private func identity(_ suffix: String = "A") throws -> TuyaCandidateValueStreamIdentity {
        try TuyaCandidateValueStreamIdentity(
            peripheralIdentifier: "peripheral-\(suffix)",
            serviceIdentifier: "A201",
            characteristicIdentifier: "2B10"
        )
    }

    private func policy() throws -> TuyaCandidateFragmentReassemblyPolicy {
        try TuyaCandidateFragmentReassemblyPolicy(
            maximumEncryptedMessageBytes: 64,
            maximumFragmentCount: 8
        )
    }

    private func encodeVarint(_ input: UInt64) -> [UInt8] {
        var value = input
        var bytes: [UInt8] = []
        repeat {
            var byte = UInt8(value & 0x7F)
            value >>= 7
            if value != 0 { byte |= 0x80 }
            bytes.append(byte)
        } while value != 0
        return bytes
    }

    private func observation(
        payload: [UInt8],
        packetIndex: UInt64,
        uptime: UInt64,
        sequence: UInt64?,
        scope: String? = "capture-session-A",
        totalLength: Int? = nil,
        stream: TuyaCandidateValueStreamIdentity? = nil,
        generation: UInt64 = 7
    ) throws -> TuyaCandidateFragmentObservation {
        var bytes = encodeVarint(packetIndex)
        if packetIndex == 0 {
            bytes += encodeVarint(UInt64(totalLength ?? payload.count))
            bytes.append(0x20)
        }
        bytes += payload
        return try TuyaCandidateFragmentObservation(
            streamIdentity: stream ?? identity(),
            continuityGeneration: generation,
            receiptUptimeNanoseconds: uptime,
            receiptSequenceNumber: sequence,
            receiptSequenceScope: sequence == nil ? nil : scope,
            bytes: bytes
        )
    }

    @Test("scoped sequence remains authoritative across completed candidates at equal uptime")
    func scopedSequenceAllowsEqualUptimeAcrossCandidateCompletion() throws {
        let observations = [
            try observation(payload: [1], packetIndex: 0, uptime: 100, sequence: 40, totalLength: 1),
            try observation(payload: [2], packetIndex: 0, uptime: 100, sequence: 41, totalLength: 1)
        ]

        let events = TuyaCandidateTranscriptAnalyzer.analyze(observations, policy: try policy())
        #expect(events.count == 2)

        guard case let .completed(firstStart, firstEnd, firstMessage) = events[0],
              case let .completed(secondStart, secondEnd, secondMessage) = events[1] else {
            Issue.record("Expected both equal-tick scoped callbacks to remain distinct completed candidates")
            return
        }

        #expect(firstStart == 0)
        #expect(firstEnd == 0)
        #expect(secondStart == 1)
        #expect(secondEnd == 1)
        #expect(firstMessage.receiptSequenceScope == "capture-session-A")
        #expect(firstMessage.firstReceiptSequenceNumber == 40)
        #expect(firstMessage.lastReceiptSequenceNumber == 40)
        #expect(secondMessage.receiptSequenceScope == "capture-session-A")
        #expect(secondMessage.firstReceiptSequenceNumber == 41)
        #expect(secondMessage.lastReceiptSequenceNumber == 41)
        #expect(firstMessage.lastReceiptUptimeNanoseconds == 100)
        #expect(secondMessage.firstReceiptUptimeNanoseconds == 100)
    }

    @Test("rejected newer scoped receipt consumes transcript sequence high-water")
    func rejectedScopedReceiptBlocksDelayedOlderEvidence() throws {
        let completed = try observation(
            payload: [1],
            packetIndex: 0,
            uptime: 100,
            sequence: 10,
            totalLength: 1
        )
        let malformedNewer = try TuyaCandidateFragmentObservation(
            streamIdentity: identity(),
            continuityGeneration: 7,
            receiptUptimeNanoseconds: 200,
            receiptSequenceNumber: 12,
            receiptSequenceScope: "capture-session-A",
            bytes: [0x01]
        )
        let delayedOlder = try observation(
            payload: [2],
            packetIndex: 0,
            uptime: 150,
            sequence: 11,
            totalLength: 1
        )
        let recovery = try observation(
            payload: [3],
            packetIndex: 0,
            uptime: 200,
            sequence: 13,
            totalLength: 1
        )

        let events = TuyaCandidateTranscriptAnalyzer.analyze(
            [completed, malformedNewer, delayedOlder, recovery],
            policy: try policy()
        )

        #expect(events.count == 4)
        guard case .completed = events[0] else {
            Issue.record("Expected first candidate to complete")
            return
        }
        #expect(events[1] == .rejectedCandidate(
            startObservationIndex: 1,
            lastAcceptedObservationIndex: nil,
            failingObservationIndex: 1,
            error: .unexpectedPacketIndex(expected: 0, actual: 1)
        ))
        #expect(events[2] == .rejectedCandidate(
            startObservationIndex: 2,
            lastAcceptedObservationIndex: nil,
            failingObservationIndex: 2,
            error: .nonMonotonicReceiptSequence(previous: 12, actual: 11)
        ))
        guard case let .completed(start, end, message) = events[3] else {
            Issue.record("Expected genuinely newer sequence to recover")
            return
        }
        #expect(start == 3)
        #expect(end == 3)
        #expect(message.encryptedBytes == [3])
        #expect(message.firstReceiptSequenceNumber == 13)
    }

    @Test("scope stays transcript-wide and foreign scope cannot poison selected chronology")
    func foreignScopeFailsWithoutAdvancingSelectedHighWater() throws {
        let first = try observation(payload: [1], packetIndex: 0, uptime: 100, sequence: 20, totalLength: 1)
        let foreign = try observation(
            payload: [9],
            packetIndex: 0,
            uptime: 500,
            sequence: 999,
            scope: "capture-session-B",
            totalLength: 1
        )
        let selected = try observation(payload: [2], packetIndex: 0, uptime: 100, sequence: 21, totalLength: 1)

        let events = TuyaCandidateTranscriptAnalyzer.analyze([first, foreign, selected], policy: try policy())
        #expect(events.count == 3)
        guard case .completed = events[0] else {
            Issue.record("Expected selected-scope seed to complete")
            return
        }
        #expect(events[1] == .rejectedCandidate(
            startObservationIndex: 1,
            lastAcceptedObservationIndex: nil,
            failingObservationIndex: 1,
            error: .receiptSequenceScopeChanged(
                expected: "capture-session-A",
                actual: "capture-session-B"
            )
        ))
        guard case let .completed(_, _, message) = events[2] else {
            Issue.record("Expected selected scope to remain recoverable")
            return
        }
        #expect(message.firstReceiptSequenceNumber == 21)
        #expect(message.receiptSequenceScope == "capture-session-A")
    }

    @Test("receipt ordering authority cannot switch after candidate completion")
    func orderingAuthoritySurvivesCandidateCompletion() throws {
        let scoped = try observation(payload: [1], packetIndex: 0, uptime: 100, sequence: 1, totalLength: 1)
        let legacy = try observation(payload: [2], packetIndex: 0, uptime: 101, sequence: nil, totalLength: 1)
        let scopedRecovery = try observation(payload: [3], packetIndex: 0, uptime: 100, sequence: 2, totalLength: 1)

        let events = TuyaCandidateTranscriptAnalyzer.analyze(
            [scoped, legacy, scopedRecovery],
            policy: try policy()
        )

        #expect(events.count == 3)
        guard case .completed = events[0] else {
            Issue.record("Expected scoped candidate to complete")
            return
        }
        #expect(events[1] == .rejectedCandidate(
            startObservationIndex: 1,
            lastAcceptedObservationIndex: nil,
            failingObservationIndex: 1,
            error: .receiptOrderingAuthorityChanged
        ))
        guard case .completed = events[2] else {
            Issue.record("Expected original scoped authority to remain usable")
            return
        }
    }

    @Test("equal-tick scoped packet zero restarts only after transcript chronology admits it")
    func scopedPacketZeroRestartPreservesPrecedenceAndObservation() throws {
        let observations = [
            try observation(payload: [1], packetIndex: 0, uptime: 100, sequence: 1, totalLength: 2),
            try observation(payload: [7], packetIndex: 0, uptime: 100, sequence: 2, totalLength: 2),
            try observation(payload: [8], packetIndex: 1, uptime: 100, sequence: 3)
        ]

        let events = TuyaCandidateTranscriptAnalyzer.analyze(observations, policy: try policy())
        #expect(events.count == 2)
        #expect(events[0] == .incompleteAtBoundary(
            startObservationIndex: 0,
            lastAcceptedObservationIndex: 0,
            nextObservationIndex: 1,
            boundary: .candidatePacketZeroRestart
        ))
        guard case let .completed(start, end, message) = events[1] else {
            Issue.record("Expected chronology-admitted restart observation to seed the next candidate")
            return
        }
        #expect(start == 1)
        #expect(end == 2)
        #expect(message.encryptedBytes == [7, 8])
        #expect(message.receiptSequenceScope == "capture-session-A")
        #expect(message.firstReceiptSequenceNumber == 2)
        #expect(message.lastReceiptSequenceNumber == 3)
        #expect(message.firstReceiptUptimeNanoseconds == 100)
        #expect(message.lastReceiptUptimeNanoseconds == 100)
    }

    @Test("backward uptime consumes scoped sequence before packet-zero restart classification")
    func backwardUptimeCannotUseRestartToRewriteReceipt() throws {
        let observations = [
            try observation(payload: [1], packetIndex: 0, uptime: 500, sequence: 20, totalLength: 2),
            try observation(payload: [7], packetIndex: 0, uptime: 499, sequence: 21, totalLength: 1),
            try observation(payload: [7], packetIndex: 0, uptime: 500, sequence: 21, totalLength: 1),
            try observation(payload: [8], packetIndex: 0, uptime: 500, sequence: 22, totalLength: 1)
        ]

        let events = TuyaCandidateTranscriptAnalyzer.analyze(observations, policy: try policy())
        #expect(events.count == 3)
        #expect(events[0] == .rejectedCandidate(
            startObservationIndex: 0,
            lastAcceptedObservationIndex: 0,
            failingObservationIndex: 1,
            error: .nonMonotonicReceiptUptime
        ))
        #expect(events[1] == .rejectedCandidate(
            startObservationIndex: 2,
            lastAcceptedObservationIndex: nil,
            failingObservationIndex: 2,
            error: .nonMonotonicReceiptSequence(previous: 21, actual: 21)
        ))
        guard case let .completed(start, end, message) = events[2] else {
            Issue.record("Expected genuinely newer scoped callback at preserved uptime floor to recover")
            return
        }
        #expect(start == 3)
        #expect(end == 3)
        #expect(message.firstReceiptSequenceNumber == 22)
    }

    @Test("real continuity boundary is classified before scoped chronology rejection")
    func transportBoundaryRemainsStrongerThanReceiptChronology() throws {
        let first = try observation(
            payload: [1],
            packetIndex: 0,
            uptime: 100,
            sequence: 50,
            totalLength: 2,
            generation: 7
        )
        let staleAfterBoundary = try observation(
            payload: [9],
            packetIndex: 0,
            uptime: 100,
            sequence: 50,
            totalLength: 1,
            generation: 8
        )

        let events = TuyaCandidateTranscriptAnalyzer.analyze(
            [first, staleAfterBoundary],
            policy: try policy()
        )

        #expect(events == [
            .incompleteAtBoundary(
                startObservationIndex: 0,
                lastAcceptedObservationIndex: 0,
                nextObservationIndex: 1,
                boundary: .continuityGenerationChanged
            ),
            .rejectedCandidate(
                startObservationIndex: 1,
                lastAcceptedObservationIndex: nil,
                failingObservationIndex: 1,
                error: .nonMonotonicReceiptSequence(previous: 50, actual: 50)
            )
        ])
    }

    @Test("legacy transcript ordering still requires strictly newer seen uptime")
    func legacyModeRetainsStrictSeenUptimeAcrossCandidates() throws {
        let first = try observation(payload: [1], packetIndex: 0, uptime: 100, sequence: nil, totalLength: 1)
        let equal = try observation(payload: [2], packetIndex: 0, uptime: 100, sequence: nil, totalLength: 1)
        let newer = try observation(payload: [3], packetIndex: 0, uptime: 101, sequence: nil, totalLength: 1)

        let events = TuyaCandidateTranscriptAnalyzer.analyze([first, equal, newer], policy: try policy())
        #expect(events.count == 3)
        guard case .completed = events[0] else {
            Issue.record("Expected first legacy candidate to complete")
            return
        }
        #expect(events[1] == .rejectedCandidate(
            startObservationIndex: 1,
            lastAcceptedObservationIndex: nil,
            failingObservationIndex: 1,
            error: .nonMonotonicReceiptUptime
        ))
        guard case .completed = events[2] else {
            Issue.record("Expected genuinely newer legacy uptime to recover")
            return
        }
    }
}
