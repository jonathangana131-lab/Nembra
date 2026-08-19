import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Exact-byte artifact seal")
struct ExactByteArtifactSealTests {
    private struct Fixture: Codable, Equatable {
        let label: String
        let value: Int
    }

    private enum FixtureError: Error, Equatable {
        case decodeRejected
        case encodeRejected
    }

    @Test("seal records the known SHA-256 and byte count for the exact bytes")
    func recordsDigestAndByteCount() throws {
        let bytes = Data("abc".utf8)
        let seal = ExactByteArtifactSeal(sealing: bytes)

        #expect(seal.byteCount == 3)
        #expect(
            seal.sha256 ==
                "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
        #expect(try seal.verifiedBytes() == bytes)
    }

    @Test("candidate verification requires the exact sealed byte sequence")
    func verifiesOnlyExactCandidate() {
        let exact = Data([0x00, 0x7F, 0x80, 0xFF])
        let seal = ExactByteArtifactSeal(sealing: exact)

        #expect(seal.verifies(exact))
        #expect(!seal.verifies(Data([0x00, 0x7F, 0x81, 0xFF])))
        #expect(!seal.verifies(Data([0x00, 0x7F, 0x80])))
        #expect(!seal.verifies(exact + Data([0x00])))
    }

    @Test("caller mutation cannot change the private sealed snapshot")
    func ownsImmutableSnapshot() throws {
        var callerBytes = Data([0x01, 0x02, 0x03])
        let seal = ExactByteArtifactSeal(sealing: callerBytes)

        callerBytes[0] = 0xFF

        #expect(!seal.verifies(callerBytes))
        #expect(try seal.verifiedBytes() == Data([0x01, 0x02, 0x03]))
    }

    @Test("mutating retrieved bytes cannot change the private sealed snapshot")
    func retrievalReturnsIndependentBytes() throws {
        let exact = Data([0x10, 0x20, 0x30])
        let seal = ExactByteArtifactSeal(sealing: exact)
        var retrieved = try seal.verifiedBytes()

        retrieved[1] = 0xFF

        #expect(!seal.verifies(retrieved))
        #expect(seal.verifies(exact))
        #expect(try seal.verifiedBytes() == exact)
    }

    @Test("empty artifact remains a valid exact-byte seal")
    func supportsEmptyArtifact() throws {
        let seal = ExactByteArtifactSeal(sealing: Data())

        #expect(seal.byteCount == 0)
        #expect(
            seal.sha256 ==
                "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        )
        #expect(seal.verifies(Data()))
        #expect(try seal.verifiedBytes().isEmpty)
    }

    @Test("verified canonical decode returns the value for exact canonical bytes")
    func decodesKnownCanonicalBytes() throws {
        let bytes = Data(#"{"label":"field","value":42}"#.utf8)
        let seal = ExactByteArtifactSeal(sealing: bytes)
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        let decoded = try seal.verifiedCanonicalValue(
            strictlyDecoding: { try decoder.decode(Fixture.self, from: $0) },
            canonicalEncoding: { try encoder.encode($0) }
        )

        #expect(decoded == Fixture(label: "field", value: 42))
        #expect(try seal.verifiedBytes() == bytes)
    }

    @Test("noncanonical sealed bytes fail the exact canonical round trip")
    func rejectsNoncanonicalRoundTrip() {
        let noncanonicalBytes = Data(#"{"value":42,"label":"field"}"#.utf8)
        let seal = ExactByteArtifactSeal(sealing: noncanonicalBytes)
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        #expect(throws: ExactByteArtifactSealError.canonicalRoundTripMismatch) {
            try seal.verifiedCanonicalValue(
                strictlyDecoding: { try decoder.decode(Fixture.self, from: $0) },
                canonicalEncoding: { try encoder.encode($0) }
            )
        }
    }

    @Test("strict decoder errors propagate unchanged")
    func propagatesDecodeFailure() {
        let seal = ExactByteArtifactSeal(sealing: Data("not-json".utf8))

        #expect(throws: FixtureError.decodeRejected) {
            try seal.verifiedCanonicalValue(
                strictlyDecoding: { (_: Data) throws(FixtureError) -> Fixture in
                    throw .decodeRejected
                },
                canonicalEncoding: { (_: Fixture) in Data() }
            )
        }
    }

    @Test("canonical encoder errors propagate unchanged")
    func propagatesEncodeFailure() {
        let seal = ExactByteArtifactSeal(sealing: Data("42".utf8))

        #expect(throws: FixtureError.encodeRejected) {
            try seal.verifiedCanonicalValue(
                strictlyDecoding: { _ in Fixture(label: "field", value: 42) },
                canonicalEncoding: { (_: Fixture) throws(FixtureError) -> Data in
                    throw .encodeRejected
                }
            )
        }
    }

    @Test("decoder-side mutation cannot alter the private sealed snapshot")
    func decodeInputMutationCannotAlterSnapshot() throws {
        let bytes = Data("42".utf8)
        let seal = ExactByteArtifactSeal(sealing: bytes)
        var mutatedDecoderInput: Data?

        let decoded = try seal.verifiedCanonicalValue(
            strictlyDecoding: { input in
                var mutableInput = input
                mutableInput[mutableInput.startIndex] = Character("9").asciiValue!
                mutatedDecoderInput = mutableInput
                return Int(String(decoding: input, as: UTF8.self))!
            },
            canonicalEncoding: { Data(String($0).utf8) }
        )

        #expect(decoded == 42)
        #expect(mutatedDecoderInput == Data("92".utf8))
        #expect(try seal.verifiedBytes() == bytes)
        #expect(seal.verifies(bytes))
    }
}
