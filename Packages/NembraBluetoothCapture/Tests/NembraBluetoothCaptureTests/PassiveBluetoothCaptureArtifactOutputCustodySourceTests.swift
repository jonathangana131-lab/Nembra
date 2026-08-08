import Foundation
import Testing

@Suite("Passive capture artifact output custody source contract")
struct PassiveBluetoothCaptureArtifactOutputCustodySourceTests {
    private static func source() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        return try String(
            contentsOf: packageRoot
                .appendingPathComponent("Sources")
                .appendingPathComponent("NembraBluetoothCapture")
                .appendingPathComponent("PassiveBluetoothCaptureArtifactOutputPolicy.swift"),
            encoding: .utf8
        )
    }

    @Test("derived report publication is bound to stable no-follow directory custody")
    func publicationUsesDescriptorBoundCustody() throws {
        let source = try Self.source()

        let requiredDescriptorPrimitives = [
            "O_NOFOLLOW",
            "openat(",
            "renameat("
        ]
        for token in requiredDescriptorPrimitives {
            #expect(
                source.contains(token),
                "Derived report publication must bind output custody through stable no-follow directory descriptors: missing \(token)"
            )
        }

        #expect(
            !source.contains("try data.write(to: outputURL, options: [.atomic])"),
            "Forced report replacement still re-resolves the mutable output pathname after the raw-input safety decision."
        )
        #expect(
            !source.contains("try fileManager.moveItem(at: temporaryURL, to: outputURL)"),
            "Protected publication still re-resolves the mutable destination pathname instead of publishing relative to pinned directory custody."
        )
    }

    @Test("force-output retains an explicit source-subject re-proof before publication")
    func forceOutputReprovesSourceSeparation() throws {
        let source = try Self.source()

        #expect(
            source.contains("fstat") || source.contains("stat("),
            "The output policy must mechanically identify the source/destination filesystem subjects rather than relying only on canonical path text."
        )
        #expect(
            source.contains("st_dev") && source.contains("st_ino"),
            "Source-preservation authority must compare filesystem identity before a forced destination replacement can be admitted."
        )
    }
}
