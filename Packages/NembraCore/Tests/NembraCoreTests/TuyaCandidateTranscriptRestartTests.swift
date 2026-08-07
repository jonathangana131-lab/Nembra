import Testing
@testable import NembraCore

@Suite("Tuya candidate transcript packet-zero restart")
struct TuyaCandidateTranscriptRestartTests {
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
        totalLength: Int? = nil,
        generation: UInt64 = 7
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

    private func encodeVarint(_ value: UInt64) -> [UInt8] {
        var remaining = value
        var result: [UInt8] = []
        repeat {
            var byte = UInt8(remaining & 0x7F)
            remaining >>= 7
            if remaining != 0 {
                byte |= 0x80
            }
            result.append(byte)
        } while remaining != 0
        return result
    }

    @Test("same-stream packet zero closes truncated candidate and starts the next message")
    func sameStreamPacketZeroRestartsWithoutDroppingObservation() throws {
        let policy = try TuyaCandidateFragmentReassemblyPolicy(
            maximumEncryptedMessageBytes: 64,
            maximumFragmentCount: 8
        )
        let observations = [
            try observation(payload: [1], packetIndex: 0, uptime: 1, totalLength: 2),
            try observation(payload: [7], packetIndex: 0, uptime: 2, totalLength: 2),
            try observation(payload: [8], packetIndex: 1, uptime: 3)
        ]

        let events = TuyaCandidateTranscriptAnalyzer.analyze(observations, policy: policy)
        #expect(events.count == 2)
        #expect(events[0] == .incompleteAtBoundary(
            startObservationIndex: 0,
            lastAcceptedObservationIndex: 0,
            nextObservationIndex: 1,
            boundary: .candidatePacketZeroRestart
        ))

        guard case let .completed(start, end, message) = events[1] else {
            Issue.record("Expected the exact restart observation to seed a completed candidate")
            return
        }
        #expect(start == 1)
        #expect(end == 2)
        #expect(message.encryptedBytes == [7, 8])
        #expect(message.fragmentCount == 2)
        #expect(message.firstReceiptUptimeNanoseconds == 2)
        #expect(message.lastReceiptUptimeNanoseconds == 3)
    }

    @Test("malformed new packet zero is preserved as its own rejected candidate")
    func malformedRestartRemainsExplicitEvidence() throws {
        let policy = try TuyaCandidateFragmentReassemblyPolicy(
            maximumEncryptedMessageBytes: 64,
            maximumFragmentCount: 8
        )
        let first = try observation(payload: [1], packetIndex: 0, uptime: 1, totalLength: 2)
        let malformedRestart = try TuyaCandidateFragmentObservation(
            streamIdentity: identity(),
            continuityGeneration: 7,
            receiptUptimeNanoseconds: 2,
            bytes: [0x00]
        )

        let events = TuyaCandidateTranscriptAnalyzer.analyze(
            [first, malformedRestart],
            policy: policy
        )

        #expect(events == [
            .incompleteAtBoundary(
                startObservationIndex: 0,
                lastAcceptedObservationIndex: 0,
                nextObservationIndex: 1,
                boundary: .candidatePacketZeroRestart
            ),
            .rejectedCandidate(
                startObservationIndex: 1,
                lastAcceptedObservationIndex: nil,
                failingObservationIndex: 1,
                error: .malformedVarint
            )
        ])
    }

    @Test("stream-generation boundary remains stronger than packet-zero restart")
    func continuityBoundaryKeepsExistingClassification() throws {
        let policy = try TuyaCandidateFragmentReassemblyPolicy(
            maximumEncryptedMessageBytes: 64,
            maximumFragmentCount: 8
        )
        let observations = [
            try observation(payload: [1], packetIndex: 0, uptime: 1, totalLength: 2, generation: 7),
            try observation(payload: [9], packetIndex: 0, uptime: 2, totalLength: 1, generation: 8)
        ]

        let events = TuyaCandidateTranscriptAnalyzer.analyze(observations, policy: policy)
        #expect(events.count == 2)
        #expect(events[0] == .incompleteAtBoundary(
            startObservationIndex: 0,
            lastAcceptedObservationIndex: 0,
            nextObservationIndex: 1,
            boundary: .continuityGenerationChanged
        ))
        guard case let .completed(start, end, message) = events[1] else {
            Issue.record("Expected new continuity generation to start normally")
            return
        }
        #expect(start == 1)
        #expect(end == 1)
        #expect(message.continuityGeneration == 8)
        #expect(message.encryptedBytes == [9])
    }

    @Test("non-monotonic packet zero cannot bypass the active candidate chronology check")
    func nonMonotonicRestartRemainsRejected() throws {
        let policy = try TuyaCandidateFragmentReassemblyPolicy(
            maximumEncryptedMessageBytes: 64,
            maximumFragmentCount: 8
        )
        let observations = [
            try observation(payload: [1], packetIndex: 0, uptime: 2, totalLength: 2),
            try observation(payload: [9], packetIndex: 0, uptime: 2, totalLength: 1)
        ]

        let events = TuyaCandidateTranscriptAnalyzer.analyze(observations, policy: policy)
        #expect(events == [
            .rejectedCandidate(
                startObservationIndex: 0,
                lastAcceptedObservationIndex: 0,
                failingObservationIndex: 1,
                error: .nonMonotonicReceiptUptime
            )
        ])
    }
}
