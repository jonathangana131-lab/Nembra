import Testing
@testable import NembraCore

@Suite("Tuya candidate capture transcript analysis")
struct TuyaCandidateTranscriptAnalysisTests {
    private func identity(_ suffix: String = "A") throws -> TuyaCandidateValueStreamIdentity {
        try TuyaCandidateValueStreamIdentity(
            peripheralIdentifier: "peripheral-\(suffix)",
            serviceIdentifier: "A201",
            characteristicIdentifier: "2B10"
        )
    }

    private func observation(
        _ bytes: [UInt8],
        index: UInt64,
        uptime: UInt64,
        stream: TuyaCandidateValueStreamIdentity? = nil,
        generation: UInt64 = 7,
        totalLength: Int? = nil,
        versionByte: UInt8 = 0x20
    ) throws -> TuyaCandidateFragmentObservation {
        var packet = encodeVarint(index)
        if index == 0 {
            packet += encodeVarint(UInt64(totalLength ?? bytes.count))
            packet.append(versionByte)
        }
        packet += bytes
        return try TuyaCandidateFragmentObservation(
            streamIdentity: stream ?? identity(),
            continuityGeneration: generation,
            receiptUptimeNanoseconds: uptime,
            bytes: packet
        )
    }

    private func encodeVarint(_ value: UInt64) -> [UInt8] {
        var value = value
        var result: [UInt8] = []
        repeat {
            var byte = UInt8(value & 0x7F)
            value >>= 7
            if value != 0 { byte |= 0x80 }
            result.append(byte)
        } while value != 0
        return result
    }

    @Test("automatically advances across complete candidate messages")
    func completesSequentialMessages() throws {
        let policy = try TuyaCandidateFragmentReassemblyPolicy(
            maximumEncryptedMessageBytes: 64,
            maximumFragmentCount: 8
        )
        let observations = [
            try observation([1, 2], index: 0, uptime: 1, totalLength: 2),
            try observation([3], index: 0, uptime: 2, totalLength: 1)
        ]
        let events = TuyaCandidateTranscriptAnalyzer.analyze(observations, policy: policy)
        #expect(events.count == 2)

        guard case let .completed(firstStart, firstEnd, firstMessage) = events[0] else {
            Issue.record("Expected first completed candidate")
            return
        }
        #expect(firstStart == 0)
        #expect(firstEnd == 0)
        #expect(firstMessage.encryptedBytes == [1, 2])

        guard case let .completed(secondStart, secondEnd, secondMessage) = events[1] else {
            Issue.record("Expected second completed candidate")
            return
        }
        #expect(secondStart == 1)
        #expect(secondEnd == 1)
        #expect(secondMessage.encryptedBytes == [3])
    }

    @Test("evidence boundary preserves incomplete candidate instead of splicing generations")
    func preservesBoundaryGap() throws {
        let policy = try TuyaCandidateFragmentReassemblyPolicy(
            maximumEncryptedMessageBytes: 64,
            maximumFragmentCount: 8
        )
        let observations = [
            try observation([1], index: 0, uptime: 1, generation: 7, totalLength: 2),
            try observation([9], index: 0, uptime: 2, generation: 8, totalLength: 1)
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
            Issue.record("Expected new generation to begin only from its own packet zero")
            return
        }
        #expect(start == 1)
        #expect(end == 1)
        #expect(message.continuityGeneration == 8)
        #expect(message.encryptedBytes == [9])
    }

    @Test("records whole failed candidate then recovers at a later packet zero")
    func rejectsAndRecovers() throws {
        let policy = try TuyaCandidateFragmentReassemblyPolicy(
            maximumEncryptedMessageBytes: 64,
            maximumFragmentCount: 8
        )
        let observations = [
            try observation([1], index: 0, uptime: 1, totalLength: 2),
            try observation([2], index: 2, uptime: 2),
            try observation([7], index: 0, uptime: 3, totalLength: 1)
        ]
        let events = TuyaCandidateTranscriptAnalyzer.analyze(observations, policy: policy)
        #expect(events.count == 2)
        #expect(events[0] == .rejectedCandidate(
            startObservationIndex: 0,
            lastAcceptedObservationIndex: 0,
            failingObservationIndex: 1,
            error: .unexpectedPacketIndex(expected: 1, actual: 2)
        ))

        guard case let .completed(start, end, message) = events[1] else {
            Issue.record("Expected later clean packet zero to start a new candidate")
            return
        }
        #expect(start == 2)
        #expect(end == 2)
        #expect(message.encryptedBytes == [7])
    }

    @Test("end of transcript explicitly retains truncated candidate evidence")
    func preservesEndTruncation() throws {
        let policy = try TuyaCandidateFragmentReassemblyPolicy(
            maximumEncryptedMessageBytes: 64,
            maximumFragmentCount: 8
        )
        let observations = [try observation([1], index: 0, uptime: 1, totalLength: 2)]
        let events = TuyaCandidateTranscriptAnalyzer.analyze(observations, policy: policy)
        #expect(events == [
            .incompleteAtEnd(startObservationIndex: 0, lastAcceptedObservationIndex: 0)
        ])
    }
}
