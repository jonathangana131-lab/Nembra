import Testing
@testable import NembraCore

@Suite("Tuya candidate receipt sequence scope")
struct TuyaCandidateReceiptScopeTests {
    private func identity() throws -> TuyaCandidateValueStreamIdentity {
        try TuyaCandidateValueStreamIdentity(
            peripheralIdentifier: "peripheral-A",
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

    private func observation(
        packetIndex: UInt64,
        payload: [UInt8],
        uptime: UInt64,
        sequence: UInt64?,
        scope: String? = nil,
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
            continuityGeneration: 9,
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
            if value != 0 { byte |= 0x80 }
            bytes.append(byte)
        } while value != 0
        return bytes
    }

    @Test("capture scope is preserved with completed sequence provenance")
    func preservesSequenceScope() throws {
        var reassembler = TuyaCandidateFragmentReassembler(policy: try policy())
        _ = try reassembler.ingest(
            try observation(
                packetIndex: 0,
                payload: [0xAA],
                uptime: 100,
                sequence: 40,
                scope: "capture-session-A",
                totalLength: 2
            )
        )

        let result = try reassembler.ingest(
            try observation(
                packetIndex: 1,
                payload: [0xBB],
                uptime: 100,
                sequence: 41,
                scope: "capture-session-A"
            )
        )
        let message = try #require({
            if case let .complete(message) = result { return message }
            return nil
        }())

        #expect(message.receiptSequenceScope == "capture-session-A")
        #expect(message.firstReceiptSequenceNumber == 40)
        #expect(message.lastReceiptSequenceNumber == 41)
        #expect(message.firstReceiptUptimeNanoseconds == 100)
        #expect(message.lastReceiptUptimeNanoseconds == 100)
    }

    @Test("a different capture scope cannot consume selected-scope chronology")
    func rejectsScopeChangeWithoutPoisoningSelectedScope() throws {
        var reassembler = TuyaCandidateFragmentReassembler(policy: try policy())
        _ = try reassembler.ingest(
            try observation(
                packetIndex: 0,
                payload: [0xAA],
                uptime: 100,
                sequence: 40,
                scope: "capture-session-A",
                totalLength: 2
            )
        )

        #expect(throws: TuyaCandidateOfflineAnalysisError.receiptSequenceScopeChanged(
            expected: "capture-session-A",
            actual: "capture-session-B"
        )) {
            try reassembler.ingest(
                try observation(
                    packetIndex: 1,
                    payload: [0xFF],
                    uptime: 500,
                    sequence: 999,
                    scope: "capture-session-B"
                )
            )
        }

        let result = try reassembler.ingest(
            try observation(
                packetIndex: 1,
                payload: [0xBB],
                uptime: 100,
                sequence: 41,
                scope: "capture-session-A"
            )
        )
        if case .complete = result {
            // A foreign capture epoch never advanced this candidate's high-water.
        } else {
            Issue.record("Expected selected capture scope to remain recoverable")
        }
    }

    @Test("a sequence scope without an immutable sequence is invalid")
    func scopeRequiresSequence() throws {
        #expect(throws: TuyaCandidateOfflineAnalysisError.receiptSequenceScopeRequiresSequence) {
            _ = try observation(
                packetIndex: 0,
                payload: [1],
                uptime: 100,
                sequence: nil,
                scope: "capture-session-A",
                totalLength: 1
            )
        }
    }

    @Test("blank scoped provenance is rejected at construction")
    func blankScopeRejected() throws {
        #expect(throws: TuyaCandidateOfflineAnalysisError.emptyReceiptSequenceScope) {
            _ = try observation(
                packetIndex: 0,
                payload: [1],
                uptime: 100,
                sequence: 1,
                scope: "   ",
                totalLength: 1
            )
        }
    }

    @Test("sequence-only generic research callers remain supported")
    func unscopedSequenceCompatibility() throws {
        var reassembler = TuyaCandidateFragmentReassembler(policy: try policy())
        _ = try reassembler.ingest(
            try observation(
                packetIndex: 0,
                payload: [1],
                uptime: 100,
                sequence: 1,
                totalLength: 2
            )
        )
        let result = try reassembler.ingest(
            try observation(
                packetIndex: 1,
                payload: [2],
                uptime: 100,
                sequence: 2
            )
        )
        let message = try #require({
            if case let .complete(message) = result { return message }
            return nil
        }())
        #expect(message.receiptSequenceScope == nil)
        #expect(message.encryptedBytes == [1, 2])
    }
}
