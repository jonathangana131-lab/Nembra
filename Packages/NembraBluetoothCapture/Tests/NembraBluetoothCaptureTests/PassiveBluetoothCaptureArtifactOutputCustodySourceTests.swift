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
        for token in ["O_NOFOLLOW", "openat(", "renameat("] {
            #expect(source.contains(token))
        }
        #expect(!source.contains("try data.write(to: outputURL, options: [.atomic])"))
        #expect(!source.contains("try fileManager.moveItem(at: temporaryURL, to: outputURL)"))
    }

    @Test("force-output retains an explicit source-subject re-proof before publication")
    func forceOutputReprovesSourceSeparation() throws {
        let source = try Self.source()
        #expect(source.contains("fstat") || source.contains("stat("))
        #expect(source.contains("st_dev") && source.contains("st_ino"))
    }
}
