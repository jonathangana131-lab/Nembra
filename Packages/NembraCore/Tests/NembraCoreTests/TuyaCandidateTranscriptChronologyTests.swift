import Testing
@testable import NembraCore

@Suite("Tuya candidate transcript seen chronology")
struct TuyaCandidateTranscriptChronologyTests {
    private func identity() throws -> TuyaCandidateValueStreamIdentity {
        try TuyaCandidateValueStreamIdentity(
            peripheralIdentifier: "peripheral-A",
            serviceIdentifier: "A201",
            characteristicIdentifier: "2B10"
        )
    }

    private func observation(
        payload: [UInt8],
        packetIndex: UInt64,
        uptime: UInt64,
        generation: UInt64 = 7,
        totalLength: Int? = nil
    ) throws -> TuyaCandidateFragmentObservation {
        var bytes = encodeVarint(packetIndex)
        if packetIndex == 0 {
            bytes += encodeVarint(UInt64(totalLength ?? payload.count))
            bytes.append(0x20)
        }
        bytes += payload
        return try TuyaCandidateFragmentObservation(
            streamIdentity: identity(),
            continuityGeneration: generation,
            receiptUptimeNanoseconds: uptime,
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

    @Test("receipt rewind cannot become a fresh candidate after completion")
    func rejectsRewindAfterCompletion() throws {
        let observations = [
            try observation(payload: [1], packetIndex: 0, uptime: 10, totalLength: 1),
            try observation(payload: [2], packetIndex: 0, uptime: 9, totalLength: 1)
        ]

        let events = TuyaCandidateTranscriptAnalyzer.analyze(
            observations,
            policy: try policy()
        )

        #expect(events.count == 2)
        guard case let .completed(startObservationIndex, endObservationIndex, _) = events[0] else {
            Issue.record("Expected first candidate to complete")
            return
        }
        #expect(startObservationIndex == 0)
        #expect(endObservationIndex == 0)
        #expect(events[1] == .rejectedCandidate(
            startObservationIndex: 1,
            lastAcceptedObservationIndex: nil,
            failingObservationIndex: 1,
            error: .nonMonotonicReceiptUptime
        ))
    }

    @Test("rejected newer observation still consumes transcript chronology")
    func rejectedObservationConsumesChronology() throws {
        let observations = [
            try observation(payload: [1], packetIndex: 0, uptime: 10, totalLength: 1),
            try observation(payload: [2], packetIndex: 2, uptime: 20),
            try observation(payload: [3], packetIndex: 0, uptime: 15, totalLength: 1),
            try observation(payload: [4], packetIndex: 0, uptime: 21, totalLength: 1)
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
            error: .nonMonotonicReceiptUptime
        ))
        guard case let .completed(startObservationIndex, endObservationIndex, message) = events[3] else {
            Issue.record("Expected a genuinely newer packet zero to recover")
            return
        }
        #expect(startObservationIndex == 3)
        #expect(endObservationIndex == 3)
        #expect(message.encryptedBytes == [4])
        #expect(message.firstReceiptUptimeNanoseconds == 21)
    }

    @Test("boundary evidence is retained before rejecting a receipt rewind")
    func boundaryThenRewindRemainsExplicit() throws {
        let observations = [
            try observation(payload: [1], packetIndex: 0, uptime: 10, generation: 7, totalLength: 2),
            try observation(payload: [9], packetIndex: 0, uptime: 9, generation: 8, totalLength: 1),
            try observation(payload: [8], packetIndex: 0, uptime: 11, generation: 8, totalLength: 1)
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
            boundary: .continuityGenerationChanged
        ))
        #expect(events[1] == .rejectedCandidate(
            startObservationIndex: 1,
            lastAcceptedObservationIndex: nil,
            failingObservationIndex: 1,
            error: .nonMonotonicReceiptUptime
        ))
        guard case let .completed(startObservationIndex, endObservationIndex, message) = events[2] else {
            Issue.record("Expected later monotonic generation evidence to recover")
            return
        }
        #expect(startObservationIndex == 2)
        #expect(endObservationIndex == 2)
        #expect(message.continuityGeneration == 8)
        #expect(message.encryptedBytes == [8])
    }
}
