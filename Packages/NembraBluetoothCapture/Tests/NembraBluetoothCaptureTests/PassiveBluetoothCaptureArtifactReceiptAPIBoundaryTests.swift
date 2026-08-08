import Foundation
import Testing

@Suite("Passive capture artifact receipt API boundary")
struct PassiveBluetoothCaptureArtifactReceiptAPIBoundaryTests {
    @Test("path-only report publication must not remain a public API")
    func pathOnlyPublicationIsNotPublic() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let outputSource = try String(
            contentsOf: packageRoot
                .appendingPathComponent("Sources")
                .appendingPathComponent("NembraBluetoothCapture")
                .appendingPathComponent("PassiveBluetoothCaptureArtifactOutputPolicy.swift"),
            encoding: .utf8
        )

        let publicReceiptSignature = "public static func writeDerivedReport(\n        _ data: Data,\n        inputReceipt: PassiveBluetoothCaptureArtifactInputReceipt,"
        let publicPathOnlySignature = "public static func writeDerivedReport(\n        _ data: Data,\n        inputURL: URL,"

        #expect(outputSource.contains(publicReceiptSignature))
        #expect(!outputSource.contains(publicPathOnlySignature))
        #expect(outputSource.contains("Package-internal compatibility seam"))
    }
}
