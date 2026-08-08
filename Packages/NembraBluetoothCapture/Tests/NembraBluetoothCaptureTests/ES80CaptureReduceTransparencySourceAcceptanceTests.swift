import Foundation
import Testing

@Suite("ES80 Capture Reduce Transparency source acceptance")
struct ES80CaptureReduceTransparencySourceAcceptanceTests {
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

    @Test("Capture observes Reduce Transparency explicitly")
    func captureObservesReduceTransparency() throws {
        let source = try Self.shellSource()

        #expect(
            source.contains("@Environment(\\.accessibilityReduceTransparency)"),
            "Capture must observe Reduce Transparency explicitly instead of relying on low-alpha surfaces to remain legible in every accessibility configuration."
        )
    }

    @Test("reduced-transparency mode increases surface separation")
    func reducedTransparencyStrengthensSurfaceSeparation() throws {
        let source = try Self.shellSource()

        #expect(source.contains("accessibilityReduceTransparency"))

        let hasDedicatedSurfaceToken = source.contains("captureSurfaceFill")
            || source.contains("capturePanelFill")
            || source.contains("surfaceFill")
        let hasExplicitConditionalOpacity = source.contains("accessibilityReduceTransparency ?")

        #expect(
            hasDedicatedSurfaceToken || hasExplicitConditionalOpacity,
            "Reduce Transparency should strengthen panel/card separation through a centralized fill token or an explicit conditional treatment, rather than leaving every low-alpha surface unchanged."
        )
    }

    @Test("truth and physical authority are unchanged by presentation accessibility")
    func presentationAccessibilityDoesNotAlterAuthority() throws {
        let source = try Self.shellSource()

        #expect(source.contains("PassiveBluetoothExperimentOneCoordinator"))
        #expect(source.contains("physicalProcedureLocked"))
        #expect(source.contains("PASSIVE / READ ONLY"))
        #expect(!source.contains("accessibilityReduceTransparency && coordinator"))
    }
}
