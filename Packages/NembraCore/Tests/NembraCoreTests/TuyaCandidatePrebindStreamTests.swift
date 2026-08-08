import Testing
@testable import NembraCore

@Suite("Tuya candidate pre-bind stream identity")
struct TuyaCandidatePrebindStreamTests {
    private func identity(_ suffix: String) throws -> TuyaCandidateValueStreamIdentity {
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

    @Test("a malformed first observation still binds the exact stream")
    func malformedFirstObservationStillBindsExactStream() throws {
        var reassembler = TuyaCandidateFragmentReassembler(policy: try policy())
        let selectedStream = try identity("A")
        let malformedFirst = try TuyaCandidateFragmentObservation(
            streamIdentity: selectedStream,
            continuityGeneration: 1,
            receiptUptimeNanoseconds: 100,
            receiptSequenceNumber: 10,
            receiptSequenceScope: "capture-session-A",
            bytes: [0x01, 0xFF]
        )

        #expect(throws: TuyaCandidateOfflineAnalysisError.unexpectedPacketIndex(expected: 0, actual: 1)) {
            try reassembler.ingest(malformedFirst)
        }

        let foreignStream = try TuyaCandidateFragmentObservation(
            streamIdentity: identity("B"),
            continuityGeneration: 1,
            receiptUptimeNanoseconds: 500,
            receiptSequenceNumber: 999,
            receiptSequenceScope: "capture-session-A",
            bytes: [0x00, 0x01, 0x20, 0xBB]
        )
        #expect(throws: TuyaCandidateOfflineAnalysisError.streamChanged) {
            try reassembler.ingest(foreignStream)
        }

        let selectedRecovery = try TuyaCandidateFragmentObservation(
            streamIdentity: selectedStream,
            continuityGeneration: 1,
            receiptUptimeNanoseconds: 100,
            receiptSequenceNumber: 11,
            receiptSequenceScope: "capture-session-A",
            bytes: [0x00, 0x01, 0x20, 0xAA]
        )
        let completion = try reassembler.ingest(selectedRecovery)
        let message = try #require({
            if case let .complete(message) = completion { return message }
            return nil
        }())

        #expect(message.streamIdentity == selectedStream)
        #expect(message.firstReceiptSequenceNumber == 11)
        #expect(message.lastReceiptSequenceNumber == 11)
    }

    @Test("a malformed first observation still binds continuity generation")
    func malformedFirstObservationStillBindsContinuityGeneration() throws {
        var reassembler = TuyaCandidateFragmentReassembler(policy: try policy())
        let selectedStream = try identity("A")
        let malformedFirst = try TuyaCandidateFragmentObservation(
            streamIdentity: selectedStream,
            continuityGeneration: 7,
            receiptUptimeNanoseconds: 100,
            receiptSequenceNumber: 20,
            receiptSequenceScope: "capture-session-A",
            bytes: [0x01, 0xFF]
        )

        #expect(throws: TuyaCandidateOfflineAnalysisError.unexpectedPacketIndex(expected: 0, actual: 1)) {
            try reassembler.ingest(malformedFirst)
        }

        let foreignGeneration = try TuyaCandidateFragmentObservation(
            streamIdentity: selectedStream,
            continuityGeneration: 8,
            receiptUptimeNanoseconds: 500,
            receiptSequenceNumber: 999,
            receiptSequenceScope: "capture-session-A",
            bytes: [0x00, 0x01, 0x20, 0xBB]
        )
        #expect(throws: TuyaCandidateOfflineAnalysisError.continuityGenerationChanged) {
            try reassembler.ingest(foreignGeneration)
        }

        let selectedRecovery = try TuyaCandidateFragmentObservation(
            streamIdentity: selectedStream,
            continuityGeneration: 7,
            receiptUptimeNanoseconds: 100,
            receiptSequenceNumber: 21,
            receiptSequenceScope: "capture-session-A",
            bytes: [0x00, 0x01, 0x20, 0xAA]
        )
        if case .complete = try reassembler.ingest(selectedRecovery) {
            // Foreign generation was rejected before selected receipt chronology.
        } else {
            Issue.record("Expected selected continuity generation to remain recoverable")
        }
    }

    @Test("a malformed first legacy observation still binds the exact stream")
    func malformedFirstLegacyObservationStillBindsExactStream() throws {
        var reassembler = TuyaCandidateFragmentReassembler(policy: try policy())
        let selectedStream = try identity("L")
        let malformedFirst = try TuyaCandidateFragmentObservation(
            streamIdentity: selectedStream,
            continuityGeneration: 3,
            receiptUptimeNanoseconds: 100,
            bytes: [0x01, 0xFF]
        )

        #expect(throws: TuyaCandidateOfflineAnalysisError.unexpectedPacketIndex(expected: 0, actual: 1)) {
            try reassembler.ingest(malformedFirst)
        }

        let foreignStream = try TuyaCandidateFragmentObservation(
            streamIdentity: identity("X"),
            continuityGeneration: 3,
            receiptUptimeNanoseconds: 500,
            bytes: [0x00, 0x01, 0x20, 0xBB]
        )
        #expect(throws: TuyaCandidateOfflineAnalysisError.streamChanged) {
            try reassembler.ingest(foreignStream)
        }

        let selectedRecovery = try TuyaCandidateFragmentObservation(
            streamIdentity: selectedStream,
            continuityGeneration: 3,
            receiptUptimeNanoseconds: 101,
            bytes: [0x00, 0x01, 0x20, 0xAA]
        )
        let completion = try reassembler.ingest(selectedRecovery)
        let message = try #require({
            if case let .complete(message) = completion { return message }
            return nil
        }())

        #expect(message.streamIdentity == selectedStream)
        #expect(message.receiptSequenceScope == nil)
        #expect(message.firstReceiptSequenceNumber == nil)
        #expect(message.lastReceiptSequenceNumber == nil)
    }
}
