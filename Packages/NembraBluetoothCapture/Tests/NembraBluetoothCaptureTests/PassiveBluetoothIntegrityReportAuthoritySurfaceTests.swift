import Foundation
import Testing

@Suite("Capture integrity report authority surface")
struct PassiveBluetoothIntegrityReportAuthoritySurfaceTests {
    @Test("evidence-bearing integrity reports do not expose public initializers")
    func reportsRemainInspectorMinted() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sources = packageRoot
            .appendingPathComponent("Sources/NembraBluetoothCapture", isDirectory: true)
        let reportFiles = [
            "PassiveBluetoothFinalizedArtifactIntegrity.swift",
            "PassiveBluetoothExperimentOneSoftwareExportIntegrity.swift",
            "PassiveBluetoothExperimentOneFinalShareIntegrity.swift",
        ]

        for filename in reportFiles {
            let source = try String(
                contentsOf: sources.appendingPathComponent(filename),
                encoding: .utf8
            )
            #expect(
                !source.contains("public init("),
                "\(filename) must keep report construction package-owned; public clients should earn reports only through inspect(_:)."
            )
        }
    }
}
