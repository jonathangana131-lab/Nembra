import Testing
@testable import NembraCore

@Suite("Tuya public-family candidate offline analysis")
struct TuyaCandidateOfflineAnalysisTests {
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
            let length = totalLength ?? bytes.count
            packet += encodeVarint(UInt64(length))
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

    private func be16(_ value: UInt16) -> [UInt8] {
        [UInt8(value >> 8), UInt8(value & 0xFF)]
    }

    private func be32(_ value: UInt32) -> [UInt8] {
        [
            UInt8(value >> 24),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF)
        ]
    }

    private func logicalPacket(
        sequence: UInt32 = 0x01020304,
        responseTo: UInt32 = 0x05060708,
        code: UInt16 = 0x8001,
        data: [UInt8] = [0xAA, 0xBB, 0xCC],
        padded: Bool
    ) -> [UInt8] {
        var raw = be32(sequence) + be32(responseTo) + be16(code) + be16(UInt16(data.count)) + data
        raw += be16(TuyaCandidateLogicalPacket.crc16A001(raw))
        if padded {
            while raw.count % 16 != 0 { raw.append(0) }
        }
        return raw
    }

    @Test("public-family varint uses low seven bits first and supports multi-byte values")
    func decodesCandidateVarint() throws {
        var cursor = 0
        let bytes = encodeVarint(16_511)
        let decoded = try TuyaCandidateFragmentReassembler.decodeCandidateVarint(bytes, cursor: &cursor)
        #expect(decoded == 16_511)
        #expect(cursor == bytes.count)
    }

    @Test("malformed and overflowing varints fail closed")
    func rejectsBadVarints() {
        var truncatedCursor = 0
        #expect(throws: TuyaCandidateOfflineAnalysisError.malformedVarint) {
            try TuyaCandidateFragmentReassembler.decodeCandidateVarint([0x80], cursor: &truncatedCursor)
        }

        var overflowCursor = 0
        #expect(throws: TuyaCandidateOfflineAnalysisError.varintOverflow) {
            try TuyaCandidateFragmentReassembler.decodeCandidateVarint(
                [0x80, 0x80, 0x80, 0x80, 0x00],
                cursor: &overflowCursor
            )
        }
    }

    @Test("multi-fragment reconstruction preserves stream, generation, timing, and version evidence")
    func reconstructsOneContinuityGeneration() throws {
        let policy = try TuyaCandidateFragmentReassemblyPolicy(
            maximumEncryptedMessageBytes: 256,
            maximumFragmentCount: 16
        )
        var reassembler = TuyaCandidateFragmentReassembler(policy: policy)
        let encrypted = Array(0..<49).map(UInt8.init)

        let first = try observation(
            Array(encrypted[0..<14]),
            index: 0,
            uptime: 1_000,
            totalLength: encrypted.count,
            versionByte: 0x20
        )
        let second = try observation(Array(encrypted[14..<32]), index: 1, uptime: 2_000)
        let third = try observation(Array(encrypted[32...]), index: 2, uptime: 3_000)

        #expect(try reassembler.ingest(first) == .awaitingMore(nextPacketIndex: 1, remainingBytes: 35))
        #expect(try reassembler.ingest(second) == .awaitingMore(nextPacketIndex: 2, remainingBytes: 17))
        let final = try reassembler.ingest(third)
        let message = try #require({
            if case let .complete(message) = final { return message }
            return nil
        }())
        #expect(message.encryptedBytes == encrypted)
        #expect(message.fragmentCount == 3)
        #expect(message.continuityGeneration == 7)
        #expect(message.protocolVersionByte == 0x20)
        #expect(message.protocolVersionHighNibble == 2)
        #expect(message.firstReceiptUptimeNanoseconds == 1_000)
        #expect(message.lastReceiptUptimeNanoseconds == 3_000)
    }

    @Test("stream identity change cannot splice bytes into one candidate message")
    func rejectsCrossStreamSplice() throws {
        let policy = try TuyaCandidateFragmentReassemblyPolicy(maximumEncryptedMessageBytes: 64, maximumFragmentCount: 4)
        var reassembler = TuyaCandidateFragmentReassembler(policy: policy)
        _ = try reassembler.ingest(try observation([1, 2], index: 0, uptime: 100, totalLength: 4))

        #expect(throws: TuyaCandidateOfflineAnalysisError.streamChanged) {
            try reassembler.ingest(
                try observation([3, 4], index: 1, uptime: 200, stream: identity("B"))
            )
        }
    }

    @Test("continuity generation change cannot bridge a capture gap")
    func rejectsCrossGapSplice() throws {
        let policy = try TuyaCandidateFragmentReassemblyPolicy(maximumEncryptedMessageBytes: 64, maximumFragmentCount: 4)
        var reassembler = TuyaCandidateFragmentReassembler(policy: policy)
        _ = try reassembler.ingest(try observation([1, 2], index: 0, uptime: 100, totalLength: 4))

        #expect(throws: TuyaCandidateOfflineAnalysisError.continuityGenerationChanged) {
            try reassembler.ingest(try observation([3, 4], index: 1, uptime: 200, generation: 8))
        }
    }

    @Test("non-monotonic receipt timing and packet gaps are rejected atomically")
    func rejectsChronologyAndPacketGaps() throws {
        let policy = try TuyaCandidateFragmentReassemblyPolicy(maximumEncryptedMessageBytes: 64, maximumFragmentCount: 6)
        var reassembler = TuyaCandidateFragmentReassembler(policy: policy)
        _ = try reassembler.ingest(try observation([1], index: 0, uptime: 100, totalLength: 3))

        #expect(throws: TuyaCandidateOfflineAnalysisError.nonMonotonicReceiptUptime) {
            try reassembler.ingest(try observation([2], index: 1, uptime: 100))
        }
        #expect(throws: TuyaCandidateOfflineAnalysisError.unexpectedPacketIndex(expected: 1, actual: 2)) {
            try reassembler.ingest(try observation([2], index: 2, uptime: 200))
        }

        #expect(try reassembler.ingest(try observation([2], index: 1, uptime: 200)) == .awaitingMore(nextPacketIndex: 2, remainingBytes: 1))
    }

    @Test("declared length and fragment-count bounds are caller policy, not guessed ES80 constants")
    func enforcesInjectedBounds() throws {
        let policy = try TuyaCandidateFragmentReassemblyPolicy(maximumEncryptedMessageBytes: 4, maximumFragmentCount: 1)
        var tooLarge = TuyaCandidateFragmentReassembler(policy: policy)
        #expect(throws: TuyaCandidateOfflineAnalysisError.declaredLengthExceedsPolicy(declared: 5, maximum: 4)) {
            try tooLarge.ingest(try observation([1], index: 0, uptime: 1, totalLength: 5))
        }

        var tooMany = TuyaCandidateFragmentReassembler(policy: policy)
        _ = try tooMany.ingest(try observation([1], index: 0, uptime: 1, totalLength: 2))
        #expect(throws: TuyaCandidateOfflineAnalysisError.fragmentCountExceedsPolicy(maximum: 1)) {
            try tooMany.ingest(try observation([2], index: 1, uptime: 2))
        }
    }

    @Test("reassembly rejects payload beyond declared length and cannot accept bytes after completion")
    func rejectsLengthOverrunAndPostCompletionData() throws {
        let policy = try TuyaCandidateFragmentReassemblyPolicy(maximumEncryptedMessageBytes: 16, maximumFragmentCount: 4)
        var overrun = TuyaCandidateFragmentReassembler(policy: policy)
        #expect(throws: TuyaCandidateOfflineAnalysisError.assembledLengthExceeded(declared: 2, actual: 3)) {
            try overrun.ingest(try observation([1, 2, 3], index: 0, uptime: 1, totalLength: 2))
        }

        var complete = TuyaCandidateFragmentReassembler(policy: policy)
        _ = try complete.ingest(try observation([1, 2], index: 0, uptime: 1, totalLength: 2))
        #expect(throws: TuyaCandidateOfflineAnalysisError.messageAlreadyComplete) {
            try complete.ingest(try observation([3], index: 1, uptime: 2))
        }
    }

    @Test("encrypted-envelope inspection preserves flag and IV while enforcing CBC shape")
    func inspectsEncryptedEnvelopeShape() throws {
        let bytes = [UInt8(0x05)] + Array(repeating: UInt8(0x11), count: 16) + Array(repeating: UInt8(0x22), count: 32)
        let envelope = try TuyaCandidateEncryptedEnvelope.inspect(bytes)
        #expect(envelope.securityFlag == 0x05)
        #expect(envelope.initializationVector == Array(repeating: 0x11, count: 16))
        #expect(envelope.ciphertext.count == 32)

        #expect(throws: TuyaCandidateOfflineAnalysisError.encryptedEnvelopeTooShort) {
            try TuyaCandidateEncryptedEnvelope.inspect(Array(repeating: 0, count: 32))
        }
        #expect(throws: TuyaCandidateOfflineAnalysisError.encryptedCiphertextNotBlockAligned) {
            try TuyaCandidateEncryptedEnvelope.inspect(Array(repeating: 0, count: 34))
        }
    }

    @Test("logical parser validates public-family big-endian header and CRC without interpreting code or data")
    func parsesLogicalPacket() throws {
        let raw = logicalPacket(padded: false)
        let packet = try TuyaCandidateLogicalPacket.parse(raw, paddingPolicy: .exact)
        #expect(packet.sequenceNumber == 0x01020304)
        #expect(packet.responseTo == 0x05060708)
        #expect(packet.code == 0x8001)
        #expect(packet.data == [0xAA, 0xBB, 0xCC])
        #expect(packet.paddingByteCount == 0)
    }

    @Test("zero-padded decrypted logical candidate requires exact block length and zero padding")
    func validatesLogicalZeroPadding() throws {
        let padded = logicalPacket(data: [1, 2, 3, 4, 5, 6], padded: true)
        let packet = try TuyaCandidateLogicalPacket.parse(padded, paddingPolicy: .zeroPaddedTo16ByteBoundary)
        #expect(packet.paddingByteCount == padded.count - (12 + 6 + 2))

        var nonZero = padded
        nonZero[nonZero.count - 1] = 1
        #expect(throws: TuyaCandidateOfflineAnalysisError.nonZeroLogicalPacketPadding) {
            try TuyaCandidateLogicalPacket.parse(nonZero, paddingPolicy: .zeroPaddedTo16ByteBoundary)
        }
    }

    @Test("CRC corruption fails closed")
    func rejectsBadCRC() throws {
        var raw = logicalPacket(padded: false)
        raw[12] ^= 0xFF
        do {
            _ = try TuyaCandidateLogicalPacket.parse(raw, paddingPolicy: .exact)
            Issue.record("Expected CRC failure")
        } catch let error as TuyaCandidateOfflineAnalysisError {
            guard case .logicalPacketCRCFailed = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        }
    }

    @Test("exact and padded policies do not silently reinterpret one another")
    func paddingPoliciesRemainExplicit() throws {
        let exact = logicalPacket(data: [1], padded: false)
        let padded = logicalPacket(data: [1], padded: true)

        #expect(throws: TuyaCandidateOfflineAnalysisError.logicalPacketLengthMismatch(expected: exact.count, actual: padded.count)) {
            try TuyaCandidateLogicalPacket.parse(padded, paddingPolicy: .exact)
        }
        #expect(throws: TuyaCandidateOfflineAnalysisError.logicalPacketPaddingLengthMismatch(expected: padded.count, actual: exact.count)) {
            try TuyaCandidateLogicalPacket.parse(exact, paddingPolicy: .zeroPaddedTo16ByteBoundary)
        }
    }
}
