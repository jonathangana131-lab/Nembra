import Foundation
import Testing

@Suite("ES80 Capture Differentiate Without Color source acceptance")
struct ES80CaptureDifferentiateWithoutColorSourceAcceptanceTests {
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

    @Test("Capture observes Differentiate Without Color explicitly")
    func captureObservesDifferentiateWithoutColor() throws {
        let source = try Self.shellSource()

        #expect(
            source.contains("@Environment(\\.accessibilityDifferentiateWithoutColor)"),
            "Capture should explicitly observe Differentiate Without Color instead of making sighted progress/state recognition depend on tint/fill alone."
        )
    }

    @Test("progress rail gains a non-color current/completed cue")
    func progressRailProvidesNonColorCue() throws {
        let source = try Self.shellSource()

        #expect(source.contains("accessibilityDifferentiateWithoutColor"))

        let hasSemanticDecoration = source.contains("progressSegmentDecoration")
            || source.contains("progressSegmentSymbol")
            || source.contains("progressSegmentStroke")
            || source.contains("differentiateWithoutColor ?")
            || source.contains("accessibilityDifferentiateWithoutColor ?")

        #expect(
            hasSemanticDecoration,
            "When Differentiate Without Color is enabled, completed/current progress must gain a restrained shape/stroke/symbol distinction in addition to fill color. Do not solve this with louder color."
        )
    }

    @Test("non-color treatment remains presentation-only")
    func nonColorTreatmentDoesNotAlterCaptureAuthority() throws {
        let source = try Self.shellSource()

        #expect(source.contains("PassiveBluetoothExperimentOneCoordinator"))
        #expect(source.contains("physicalProcedureLocked"))
        #expect(source.contains("PASSIVE / READ ONLY"))
        #expect(!source.contains("accessibilityDifferentiateWithoutColor && coordinator"))
        #expect(!source.contains("accessibilityDifferentiateWithoutColor && physical"))
    }
}