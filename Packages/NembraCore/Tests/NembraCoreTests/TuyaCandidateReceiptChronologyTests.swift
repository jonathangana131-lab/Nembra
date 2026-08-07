import Testing
@testable import NembraCore

@Suite("Tuya candidate immutable receipt chronology")
struct TuyaCandidateReceiptChronologyTests {
    private func identity(_ suffix: String = "A") throws -> TuyaCandidateValueStreamIdentity {
        try TuyaCandidateValueStreamIdentity(
            peripheralIdentifier: "peripheral-\(suffix)",
            serviceIdentifier: "A201",
            characteristicIdentifier: "2B10"
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

    private func observation(
        payload: [UInt8],
        packetIndex: UInt64,
        uptime: UInt64,
        sequence: UInt64?,
        totalLength: Int? = nil,
        stream: TuyaCandidateValueStreamIdentity? = nil,
        generation: UInt64 = 4
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
            bytes: bytes
        )
    }

    private func policy() throws -> TuyaCandidateFragmentReassemblyPolicy {
        try TuyaCandidateFragmentReassemblyPolicy(
            maximumEncryptedMessageBytes: 64,
            maximumFragmentCount: 8
        )
    }

    @Test("sequence-backed callbacks may share one monotonic clock tick without fabricated time")
    func acceptsEqualUptimeWithIncreasingReceiptSequence() throws {
        var reassembler = TuyaCandidateFragmentReassembler(policy: try policy())

        let first = try observation(
            payload: [0xAA],
            packetIndex: 0,
            uptime: 1_000,
            sequence: 40,
            totalLength: 2
        )
        let second = try observation(
            payload: [0xBB],
            packetIndex: 1,
            uptime: 1_000,
            sequence: 41
        )

        #expect(
            try reassembler.ingest(first)
                == .awaitingMore(nextPacketIndex: 1, remainingBytes: 1)
        )
        let result = try reassembler.ingest(second)
        let message = try #require({
            if case let .complete(message) = result { return message }
            return nil
        }())

        #expect(message.encryptedBytes == [0xAA, 0xBB])
        #expect(message.firstReceiptUptimeNanoseconds == 1_000)
        #expect(message.lastReceiptUptimeNanoseconds == 1_000)
        #expect(message.firstReceiptSequenceNumber == 40)
        #expect(message.lastReceiptSequenceNumber == 41)
    }

    @Test("a rejected newer callback consumes receipt order so delayed older evidence cannot enter")
    func rejectedNewerCallbackBlocksDelayedOlderReceipt() throws {
        var reassembler = TuyaCandidateFragmentReassembler(policy: try policy())

        _ = try reassembler.ingest(
            try observation(
                payload: [1],
                packetIndex: 0,
                uptime: 100,
                sequence: 10,
                totalLength: 2
            )
        )

        #expect(throws: TuyaCandidateOfflineAnalysisError.unexpectedPacketIndex(expected: 1, actual: 2)) {
            try reassembler.ingest(
                try observation(
                    payload: [9],
                    packetIndex: 2,
                    uptime: 300,
                    sequence: 12
                )
            )
        }

        #expect(throws: TuyaCandidateOfflineAnalysisError.nonMonotonicReceiptSequence(previous: 12, actual: 11)) {
            try reassembler.ingest(
                try observation(
                    payload: [2],
                    packetIndex: 1,
                    uptime: 200,
                    sequence: 11
                )
            )
        }

        let completion = try reassembler.ingest(
            try observation(
                payload: [2],
                packetIndex: 1,
                uptime: 300,
                sequence: 13
            )
        )
        let message = try #require({
            if case let .complete(message) = completion { return message }
            return nil
        }())
        #expect(message.encryptedBytes == [1, 2])
        #expect(message.firstReceiptSequenceNumber == 10)
        #expect(message.lastReceiptSequenceNumber == 13)
    }

    @Test("backward uptime consumes the newer sequence and cannot be rewritten in place")
    func backwardUptimeCannotRewriteReceiptIdentity() throws {
        var reassembler = TuyaCandidateFragmentReassembler(policy: try policy())

        _ = try reassembler.ingest(
            try observation(
                payload: [1],
                packetIndex: 0,
                uptime: 500,
                sequence: 20,
                totalLength: 2
            )
        )

        #expect(throws: TuyaCandidateOfflineAnalysisError.nonMonotonicReceiptUptime) {
            try reassembler.ingest(
                try observation(
                    payload: [2],
                    packetIndex: 1,
                    uptime: 499,
                    sequence: 21
                )
            )
        }

        #expect(throws: TuyaCandidateOfflineAnalysisError.nonMonotonicReceiptSequence(previous: 21, actual: 21)) {
            try reassembler.ingest(
                try observation(
                    payload: [2],
                    packetIndex: 1,
                    uptime: 500,
                    sequence: 21
                )
            )
        }

        let completion = try reassembler.ingest(
            try observation(
                payload: [2],
                packetIndex: 1,
                uptime: 500,
                sequence: 22
            )
        )
        if case .complete = completion {
            // Expected: equal uptime is valid because callback identity advanced.
        } else {
            Issue.record("Expected sequence 22 at the preserved uptime floor to complete")
        }
    }

    @Test("one candidate cannot switch between sequence-backed and legacy ordering authority")
    func rejectsMixedReceiptOrderingAuthority() throws {
        var sequenceFirst = TuyaCandidateFragmentReassembler(policy: try policy())
        _ = try sequenceFirst.ingest(
            try observation(
                payload: [1],
                packetIndex: 0,
                uptime: 100,
                sequence: 1,
                totalLength: 2
            )
        )
        #expect(throws: TuyaCandidateOfflineAnalysisError.receiptOrderingAuthorityChanged) {
            try sequenceFirst.ingest(
                try observation(
                    payload: [2],
                    packetIndex: 1,
                    uptime: 200,
                    sequence: nil
                )
            )
        }

        var legacyFirst = TuyaCandidateFragmentReassembler(policy: try policy())
        _ = try legacyFirst.ingest(
            try observation(
                payload: [1],
                packetIndex: 0,
                uptime: 100,
                sequence: nil,
                totalLength: 2
            )
        )
        #expect(throws: TuyaCandidateOfflineAnalysisError.receiptOrderingAuthorityChanged) {
            try legacyFirst.ingest(
                try observation(
                    payload: [2],
                    packetIndex: 1,
                    uptime: 200,
                    sequence: 2
                )
            )
        }
    }

    @Test("legacy observations preserve strict accepted-uptime ordering")
    func legacyModeStillRejectsEqualUptime() throws {
        var reassembler = TuyaCandidateFragmentReassembler(policy: try policy())
        _ = try reassembler.ingest(
            try observation(
                payload: [1],
                packetIndex: 0,
                uptime: 100,
                sequence: nil,
                totalLength: 2
            )
        )

        #expect(throws: TuyaCandidateOfflineAnalysisError.nonMonotonicReceiptUptime) {
            try reassembler.ingest(
                try observation(
                    payload: [2],
                    packetIndex: 1,
                    uptime: 100,
                    sequence: nil
                )
            )
        }

        let completion = try reassembler.ingest(
            try observation(
                payload: [2],
                packetIndex: 1,
                uptime: 101,
                sequence: nil
            )
        )
        if case .complete = completion {
            // Expected legacy compatibility.
        } else {
            Issue.record("Expected legacy strict-uptime retry to complete")
        }
    }

    @Test("foreign stream rejection cannot poison selected-stream receipt chronology")
    func foreignStreamDoesNotConsumeSelectedReceiptSequence() throws {
        var reassembler = TuyaCandidateFragmentReassembler(policy: try policy())
        _ = try reassembler.ingest(
            try observation(
                payload: [1],
                packetIndex: 0,
                uptime: 100,
                sequence: 50,
                totalLength: 2
            )
        )

        #expect(throws: TuyaCandidateOfflineAnalysisError.streamChanged) {
            try reassembler.ingest(
                try observation(
                    payload: [9],
                    packetIndex: 1,
                    uptime: 1_000,
                    sequence: 9_999,
                    stream: identity("B")
                )
            )
        }

        let completion = try reassembler.ingest(
            try observation(
                payload: [2],
                packetIndex: 1,
                uptime: 100,
                sequence: 51
            )
        )
        if case .complete = completion {
            // Exact stream/generation validation occurs before chronology admission.
        } else {
            Issue.record("Expected selected stream to remain recoverable")
        }
    }
}
