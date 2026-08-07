import Testing
@testable import NembraCore

@Suite("Tuya candidate transcript scoped receipt chronology")
struct TuyaCandidateTranscriptReceiptChronologyTests {
    private func identity(_ peripheral: String = "peripheral-A") throws -> TuyaCandidateValueStreamIdentity {
        try TuyaCandidateValueStreamIdentity(
            peripheralIdentifier: peripheral,
            serviceIdentifier: "A201",
            characteristicIdentifier: "2B10"
        )
    }

    private func observation(
        payload: [UInt8],
        packetIndex: UInt64,
        uptime: UInt64,
        sequence: UInt64? = nil,
        scope: String? = nil,
        generation: UInt64 = 7,
        peripheral: String = "peripheral-A",
        totalLength: Int? = nil
    ) throws -> TuyaCandidateFragmentObservation {
        var bytes = encodeVarint(packetIndex)
        if packetIndex == 0 {
            bytes += encodeVarint(UInt64(totalLength ?? payload.count))
            bytes.append(0x20)
        }
        bytes += payload

        return try TuyaCandidateFragmentObservation(
            streamIdentity: identity(peripheral),
            continuityGeneration: generation,
            receiptUptimeNanoseconds: uptime,
            receiptSequenceNumber: sequence,
            receiptSequenceScope: scope,
            bytes: bytes
        )
    }

    private func encodeVarint(_ input: UInt64) -> [UInt8] {
        var value = input
        var bytes: [UInt8] = []
        repeat {
            var byte = UInt8(value & 0x7F)
            value >>= 7
            if value != 0 {
                byte |= 0x80
            }
            bytes.append(byte)
        } while value != 0
        return bytes
    }

    private func policy() throws -> TuyaCandidateFragmentReassemblyPolicy {
        try TuyaCandidateFragmentReassemblyPolicy(
            maximumEncryptedMessageBytes: 64,
            maximumFragmentCount: 8
        )
    }

    @Test("scoped sequence admits distinct callbacks on one uptime tick")
    func equalUptimeIncreasingSequenceCompletes() throws {
        let observations = [
            try observation(
                payload: [1],
                packetIndex: 0,
                uptime: 10,
                sequence: 100,
                scope: "capture-session-A",
                totalLength: 2
            ),
            try observation(
                payload: [2],
                packetIndex: 1,
                uptime: 10,
                sequence: 101,
                scope: "capture-session-A"
            )
        ]

        let events = TuyaCandidateTranscriptAnalyzer.analyze(
            observations,
            policy: try policy()
        )

        #expect(events.count == 1)
        guard case let .completed(start, end, message) = events[0] else {
            Issue.record("Expected receipt-backed equal-tick callbacks to complete one candidate")
            return
        }
        #expect(start == 0)
        #expect(end == 1)
        #expect(message.encryptedBytes == [1, 2])
        #expect(message.receiptSequenceScope == "capture-session-A")
        #expect(message.firstReceiptSequenceNumber == 100)
        #expect(message.lastReceiptSequenceNumber == 101)
        #expect(message.firstReceiptUptimeNanoseconds == 10)
        #expect(message.lastReceiptUptimeNanoseconds == 10)
    }

    @Test("framing rejection consumes newer receipt sequence across candidate reset")
    func rejectedNewerReceiptBlocksDelayedOlderEvidence() throws {
        let observations = [
            try observation(
                payload: [1],
                packetIndex: 0,
                uptime: 10,
                sequence: 10,
                scope: "capture-session-A",
                totalLength: 1
            ),
            try observation(
                payload: [2],
                packetIndex: 2,
                uptime: 20,
                sequence: 20,
                scope: "capture-session-A"
            ),
            try observation(
                payload: [3],
                packetIndex: 0,
                uptime: 15,
                sequence: 15,
                scope: "capture-session-A",
                totalLength: 1
            ),
            try observation(
                payload: [4],
                packetIndex: 0,
                uptime: 21,
                sequence: 21,
                scope: "capture-session-A",
                totalLength: 1
            )
        ]

        let events = TuyaCandidateTranscriptAnalyzer.analyze(
            observations,
            policy: try policy()
        )

        #expect(events.count == 4)
        #expect(events[1] == .rejectedCandidate(
            startObservationIndex: 1,
            lastAcceptedObservationIndex: nil,
            failingObservationIndex: 1,
            error: .unexpectedPacketIndex(expected: 0, actual: 2)
        ))
        #expect(events[2] == .rejectedCandidate(
            startObservationIndex: 2,
            lastAcceptedObservationIndex: nil,
            failingObservationIndex: 2,
            error: .nonMonotonicReceiptSequence(previous: 20, actual: 15)
        ))
        guard case let .completed(start, end, message) = events[3] else {
            Issue.record("Expected genuinely newer scoped receipt to recover")
            return
        }
        #expect(start == 3)
        #expect(end == 3)
        #expect(message.encryptedBytes == [4])
        #expect(message.firstReceiptSequenceNumber == 21)
    }

    @Test("backward uptime consumes immutable sequence before rejection")
    func backwardUptimeCannotBeRetriedWithSameSequence() throws {
        let observations = [
            try observation(
                payload: [1],
                packetIndex: 0,
                uptime: 100,
                sequence: 10,
                scope: "capture-session-A",
                totalLength: 1
            ),
            try observation(
                payload: [2],
                packetIndex: 0,
                uptime: 99,
                sequence: 11,
                scope: "capture-session-A",
                totalLength: 1
            ),
            try observation(
                payload: [2],
                packetIndex: 0,
                uptime: 101,
                sequence: 11,
                scope: "capture-session-A",
                totalLength: 1
            ),
            try observation(
                payload: [3],
                packetIndex: 0,
                uptime: 101,
                sequence: 12,
                scope: "capture-session-A",
                totalLength: 1
            )
        ]

        let events = TuyaCandidateTranscriptAnalyzer.analyze(
            observations,
            policy: try policy()
        )

        #expect(events.count == 4)
        #expect(events[1] == .rejectedCandidate(
            startObservationIndex: 1,
            lastAcceptedObservationIndex: nil,
            failingObservationIndex: 1,
            error: .nonMonotonicReceiptUptime
        ))
        #expect(events[2] == .rejectedCandidate(
            startObservationIndex: 2,
            lastAcceptedObservationIndex: nil,
            failingObservationIndex: 2,
            error: .nonMonotonicReceiptSequence(previous: 11, actual: 11)
        ))
        guard case let .completed(_, _, message) = events[3] else {
            Issue.record("Expected next genuinely newer sequence to recover")
            return
        }
        #expect(message.encryptedBytes == [3])
        #expect(message.firstReceiptSequenceNumber == 12)
    }

    @Test("receipt authority survives candidate completion")
    func authorityCannotSwitchAfterCompletion() throws {
        let observations = [
            try observation(
                payload: [1],
                packetIndex: 0,
                uptime: 1,
                sequence: 1,
                scope: "capture-session-A",
                totalLength: 1
            ),
            try observation(
                payload: [2],
                packetIndex: 0,
                uptime: 2,
                totalLength: 1
            ),
            try observation(
                payload: [3],
                packetIndex: 0,
                uptime: 2,
                sequence: 2,
                scope: "capture-session-A",
                totalLength: 1
            )
        ]

        let events = TuyaCandidateTranscriptAnalyzer.analyze(
            observations,
            policy: try policy()
        )

        #expect(events.count == 3)
        #expect(events[1] == .rejectedCandidate(
            startObservationIndex: 1,
            lastAcceptedObservationIndex: nil,
            failingObservationIndex: 1,
            error: .receiptOrderingAuthorityChanged
        ))
        guard case let .completed(start, end, message) = events[2] else {
            Issue.record("Expected original receipt authority to remain usable")
            return
        }
        #expect(start == 2)
        #expect(end == 2)
        #expect(message.encryptedBytes == [3])
        #expect(message.firstReceiptSequenceNumber == 2)
    }

    @Test("real boundary is emitted before foreign receipt scope is rejected")
    func boundaryPrecedesScopeRejection() throws {
        let observations = [
            try observation(
                payload: [1],
                packetIndex: 0,
                uptime: 1,
                sequence: 1,
                scope: "capture-session-A",
                generation: 7,
                peripheral: "peripheral-A",
                totalLength: 2
            ),
            try observation(
                payload: [9],
                packetIndex: 0,
                uptime: 2,
                sequence: 2,
                scope: "capture-session-B",
                generation: 8,
                peripheral: "peripheral-B",
                totalLength: 1
            ),
            try observation(
                payload: [8],
                packetIndex: 0,
                uptime: 2,
                sequence: 2,
                scope: "capture-session-A",
                generation: 8,
                peripheral: "peripheral-B",
                totalLength: 1
            )
        ]

        let events = TuyaCandidateTranscriptAnalyzer.analyze(
            observations,
            policy: try policy()
        )

        #expect(events.count == 3)
        #expect(events[0] == .incompleteAtBoundary(
            startObservationIndex: 0,
            lastAcceptedObservationIndex: 0,
            nextObservationIndex: 1,
            boundary: .streamIdentityAndContinuityGenerationChanged
        ))
        #expect(events[1] == .rejectedCandidate(
            startObservationIndex: 1,
            lastAcceptedObservationIndex: nil,
            failingObservationIndex: 1,
            error: .receiptSequenceScopeChanged(
                expected: "capture-session-A",
                actual: "capture-session-B"
            )
        ))
        guard case let .completed(start, end, message) = events[2] else {
            Issue.record("Expected same-scope boundary evidence to remain admissible")
            return
        }
        #expect(start == 2)
        #expect(end == 2)
        #expect(message.streamIdentity == try identity("peripheral-B"))
        #expect(message.continuityGeneration == 8)
    }

    @Test("chronology-admitted equal-tick packet zero restarts the candidate")
    func freshScopedPacketZeroMayRestart() throws {
        let observations = [
            try observation(
                payload: [1],
                packetIndex: 0,
                uptime: 5,
                sequence: 10,
                scope: "capture-session-A",
                totalLength: 2
            ),
            try observation(
                payload: [9],
                packetIndex: 0,
                uptime: 5,
                sequence: 11,
                scope: "capture-session-A",
                totalLength: 1
            )
        ]

        let events = TuyaCandidateTranscriptAnalyzer.analyze(
            observations,
            policy: try policy()
        )

        #expect(events.count == 2)
        #expect(events[0] == .incompleteAtBoundary(
            startObservationIndex: 0,
            lastAcceptedObservationIndex: 0,
            nextObservationIndex: 1,
            boundary: .candidatePacketZeroRestart
        ))
        guard case let .completed(start, end, message) = events[1] else {
            Issue.record("Expected admitted restart observation to seed the new candidate")
            return
        }
        #expect(start == 1)
        #expect(end == 1)
        #expect(message.encryptedBytes == [9])
        #expect(message.firstReceiptSequenceNumber == 11)
    }

    @Test("replayed packet zero is rejected before restart classification")
    func staleScopedPacketZeroCannotRestart() throws {
        let observations = [
            try observation(
                payload: [1],
                packetIndex: 0,
                uptime: 5,
                sequence: 10,
                scope: "capture-session-A",
                totalLength: 2
            ),
            try observation(
                payload: [9],
                packetIndex: 0,
                uptime: 5,
                sequence: 10,
                scope: "capture-session-A",
                totalLength: 1
            )
        ]

        let events = TuyaCandidateTranscriptAnalyzer.analyze(
            observations,
            policy: try policy()
        )

        #expect(events == [
            .rejectedCandidate(
                startObservationIndex: 0,
                lastAcceptedObservationIndex: 0,
                failingObservationIndex: 1,
                error: .nonMonotonicReceiptSequence(previous: 10, actual: 10)
            )
        ])
    }
}
