import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Passive Bluetooth capture artifact input policy")
struct PassiveBluetoothCaptureArtifactInputPolicyTests {
    @Test("bounded reader preserves exact source bytes at the configured limit")
    func exactLimitPreservesBytes() throws {
        let source = Data([0x00, 0x01, 0x7F, 0x80, 0xFF])
        let url = try writeTemporary(source)
        defer { try? FileManager.default.removeItem(at: url) }

        let loaded = try PassiveBluetoothCaptureArtifactInputPolicy.readExactBytes(
            at: url,
            maximumBytes: source.count
        )

        #expect(loaded == source)
        #expect(
            PassiveBluetoothTuyaCaptureArtifactReportBuilder.sha256Hex(of: loaded) ==
                PassiveBluetoothTuyaCaptureArtifactReportBuilder.sha256Hex(of: source)
        )
    }

    @Test("same-length in-place mutation during the first pass fails descriptor stability")
    func sameLengthMutationDuringFirstPassFailsClosed() throws {
        let source = Data([0x10, 0x20, 0x30, 0x40, 0x50])
        let replacement = Data([0x10, 0x20, 0x31, 0x40, 0x50])
        let url = try writeTemporary(source)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(
            throws: PassiveBluetoothCaptureArtifactInputPolicyError
                .sourceArtifactChangedWhileReading
        ) {
            try PassiveBluetoothCaptureArtifactInputPolicy.readExactBytes(
                at: url,
                maximumBytes: source.count,
                afterFirstReadChunk: {
                    try replacement.write(to: url, options: [])
                },
                betweenVerificationPasses: nil
            )
        }
    }

    @Test("same-length in-place mutation across admission fails closed")
    func sameLengthMutationFailsClosed() throws {
        let source = Data([0x10, 0x20, 0x30, 0x40, 0x50])
        let replacement = Data([0x10, 0x20, 0x31, 0x40, 0x50])
        let url = try writeTemporary(source)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(
            throws: PassiveBluetoothCaptureArtifactInputPolicyError
                .sourceArtifactChangedWhileReading
        ) {
            try PassiveBluetoothCaptureArtifactInputPolicy.readExactBytes(
                at: url,
                maximumBytes: source.count,
                betweenVerificationPasses: {
                    try replacement.write(to: url, options: [])
                }
            )
        }
    }

    @Test("non-regular descriptor input fails before any source bytes are admitted")
    func directoryInputFailsClosed() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("nembra-artifact-input-directory-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(
            throws: PassiveBluetoothCaptureArtifactInputPolicyError
                .sourceArtifactIsNotRegularFile
        ) {
            try PassiveBluetoothCaptureArtifactInputPolicy.readExactBytes(
                at: url,
                maximumBytes: 1024
            )
        }
    }

    @Test("bounded reader rejects the first byte beyond the configured limit")
    func oneByteOverFailsClosed() throws {
        let source = Data([0x10, 0x20, 0x30, 0x40, 0x50])
        let url = try writeTemporary(source)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: PassiveBluetoothCaptureArtifactInputPolicyError
            .sourceArtifactExceedsMaximumBytes(maximumBytes: source.count - 1)) {
            try PassiveBluetoothCaptureArtifactInputPolicy.readExactBytes(
                at: url,
                maximumBytes: source.count - 1
            )
        }
    }

    @Test("invalid configured maxima fail before reading")
    func invalidMaximumFailsClosed() throws {
        let url = try writeTemporary(Data([0x01]))
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: PassiveBluetoothCaptureArtifactInputPolicyError
            .invalidMaximumArtifactBytes(0)) {
            try PassiveBluetoothCaptureArtifactInputPolicy.readExactBytes(
                at: url,
                maximumBytes: 0
            )
        }

        #expect(throws: PassiveBluetoothCaptureArtifactInputPolicyError
            .invalidMaximumArtifactBytes(Int.max)) {
            try PassiveBluetoothCaptureArtifactInputPolicy.readExactBytes(
                at: url,
                maximumBytes: Int.max
            )
        }
    }

    @Test("materialized byte-count gate accepts exact limit and rejects limit plus one")
    func materializedByteCountGate() throws {
        try PassiveBluetoothCaptureArtifactInputPolicy.validateByteCount(
            4,
            maximumBytes: 4
        )

        #expect(throws: PassiveBluetoothCaptureArtifactInputPolicyError
            .sourceArtifactExceedsMaximumBytes(maximumBytes: 4)) {
            try PassiveBluetoothCaptureArtifactInputPolicy.validateByteCount(
                5,
                maximumBytes: 4
            )
        }
    }

    @Test("artifact report rejects oversized bytes before attempting JSON decode")
    func reportBuilderChecksArtifactLimitBeforeDecode() throws {
        let malformedJSON = Data("not-json".utf8)
        let policy = try TuyaCandidateFragmentReassemblyPolicy(
            maximumEncryptedMessageBytes: 64,
            maximumFragmentCount: 8
        )

        #expect(throws: PassiveBluetoothCaptureArtifactInputPolicyError
            .sourceArtifactExceedsMaximumBytes(maximumBytes: malformedJSON.count - 1)) {
            try PassiveBluetoothTuyaCaptureArtifactReportBuilder.make(
                captureJSON: malformedJSON,
                policy: policy,
                maximumArtifactBytes: malformedJSON.count - 1
            )
        }
    }

    private func writeTemporary(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("nembra-artifact-input-\(UUID().uuidString).bin")
        try data.write(to: url, options: [.atomic])
        return url
    }
}
