import Foundation
import Testing

@Suite("ES80 Capture Increase Contrast source acceptance")
struct ES80CaptureIncreaseContrastSourceAcceptanceTests {
    private static func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func shellSource() throws -> String {
        try String(
            contentsOf: repositoryRoot()
                .appendingPathComponent("NembraApp")
                .appendingPathComponent("Features")
                .appendingPathComponent("Research")
                .appendingPathComponent("ES80CaptureShellView.swift"),
            encoding: .utf8
        )
    }

    @Test("Capture observes Increase Contrast explicitly")
    func captureObservesIncreaseContrast() throws {
        let source = try Self.shellSource()

        #expect(
            source.contains("@Environment(\\.colorSchemeContrast)"),
            "Capture uses low-alpha rider-facing surfaces on black and must explicitly observe Increase Contrast instead of assuming the default hierarchy remains legible outdoors."
        )
    }

    @Test("increased contrast strengthens rider-facing separation without adding decorative chrome")
    func increasedContrastStrengthensSeparation() throws {
        let source = try Self.shellSource()

        #expect(source.contains("colorSchemeContrast"))

        let hasContrastAwareToken = source.contains("captureSurfaceFill")
            || source.contains("capturePanelFill")
            || source.contains("captureSurfaceStroke")
            || source.contains("contrastSurface")
            || source.contains("increasedContrast")
        let hasExplicitContrastBranch = source.contains("colorSchemeContrast == .increased")
            || source.contains("colorSchemeContrast == .standard")

        #expect(
            hasContrastAwareToken || hasExplicitContrastBranch,
            "Increase Contrast should strengthen neutral panel/status separation or stroke hierarchy through one deliberate presentation treatment; do not solve outdoor readability with louder decorative color."
        )
    }

    @Test("contrast adaptation stays presentation-only and preserves field authority")
    func contrastDoesNotAlterAuthority() throws {
        let source = try Self.shellSource()

        #expect(source.contains("PassiveBluetoothExperimentOneCoordinator"))
        #expect(source.contains("physicalProcedureLocked"))
        #expect(source.contains("PASSIVE / READ ONLY"))
        #expect(!source.contains("colorSchemeContrast == .increased && coordinator"))
        #expect(!source.contains("colorSchemeContrast == .increased && presentationAnalysisReady"))
    }
}
