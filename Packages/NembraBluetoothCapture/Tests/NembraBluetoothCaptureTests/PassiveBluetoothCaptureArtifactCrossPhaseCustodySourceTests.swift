import Foundation
import Testing

@Suite("Passive capture artifact cross-phase source custody")
struct PassiveBluetoothCaptureArtifactCrossPhaseCustodySourceTests {
    private static func source(_ name: String) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: packageRoot
                .appendingPathComponent("Sources")
                .appendingPathComponent("NembraBluetoothCapture")
                .appendingPathComponent(name),
            encoding: .utf8
        )
    }

    @Test("admitted source identity must remain bound through derived report publication")
    func admissionReceiptMustReachPublication() throws {
        let input = try Self.source("PassiveBluetoothCaptureArtifactInputPolicy.swift")
        let output = try Self.source("PassiveBluetoothCaptureArtifactOutputPolicy.swift")

        let inputHasDurableIdentityReceipt =
            input.contains("ArtifactInputReceipt") ||
            input.contains("admittedSourceIdentity") ||
            input.contains("sourceIdentityReceipt")
        #expect(
            inputHasDurableIdentityReceipt,
            "Input admission currently returns only bytes; publication cannot prove it is preserving the same filesystem subject that those bytes came from."
        )

        let outputConsumesExpectedIdentity =
            output.contains("expectedInputIdentity") ||
            output.contains("inputReceipt") ||
            output.contains("sourceIdentityReceipt")
        #expect(
            outputConsumesExpectedIdentity,
            "Output publication reopens the input path but does not require the exact descriptor identity admitted during report generation."
        )
    }
}
