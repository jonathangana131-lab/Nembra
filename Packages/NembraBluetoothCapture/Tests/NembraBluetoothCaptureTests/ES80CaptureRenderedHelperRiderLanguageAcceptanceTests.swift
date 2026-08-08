import Foundation
import Testing

@Suite("ES80 Capture rendered-helper rider-language acceptance")
struct ES80CaptureRenderedHelperRiderLanguageAcceptanceTests {
    private static func shellSource() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let repositoryRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        return try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("NembraApp")
                .appendingPathComponent("Features")
                .appendingPathComponent("Research")
                .appendingPathComponent("ES80CaptureShellView.swift"),
            encoding: .utf8
        )
    }

    @Test("rendered helper messages stay rider-first outside the primary declaration slice")
    func renderedHelpersStayHumanFirst() throws {
        let source = try Self.shellSource()
        let forbidden = [
            "This evidence life cannot regain capture authority",
            "replaying consumed authority",
            "package-owned CoreBluetooth controller",
            "package-issued observation authority",
            "package-owned Experiment One workflow",
            "foreground-invalidated evidence life",
            "fresh package-owned Experiment One workflow"
        ]
        for phrase in forbidden {
            #expect(!source.contains(phrase), "Rendered helper still exposes implementation vocabulary: \(phrase)")
        }
        #expect(source.contains("This capture cannot safely continue; start a fresh Experiment One."))
        #expect(source.contains("Bluetooth capture is unavailable for this run."))
        #expect(source.contains("Start again from OFF 1."))
        #expect(source.contains("Experiment One has no active OFF / ON progress. Start a fresh run."))
        #expect(source.contains("Nembra could not start a fresh Experiment One. Close Capture and try again."))
    }

    @Test("fallback cleanup keeps lifecycle and physical gates intact")
    func truthGuardsRemain() throws {
        let source = try Self.shellSource()
        #expect(source.contains("guard status.physicalProcedurePermitted else"))
        #expect(source.contains("PassiveBluetoothExperimentOneFinalShareIntegrity.inspect(artifact.json)"))
        #expect(source.contains("coordinator.invalidateForForegroundLoss()"))
        #expect(source.contains("coordinator.abandonExperiment()"))
    }
}
