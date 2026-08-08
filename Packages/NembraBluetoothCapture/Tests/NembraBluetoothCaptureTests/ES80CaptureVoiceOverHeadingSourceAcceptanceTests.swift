import Foundation
import Testing

@Suite("ES80 Capture VoiceOver heading source acceptance")
struct ES80CaptureVoiceOverHeadingSourceAcceptanceTests {
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

    @Test("Capture exposes deliberate VoiceOver heading semantics for its visual hierarchy")
    func captureHierarchyHasVoiceOverHeadings() throws {
        let source = try Self.shellSource()

        #expect(
            source.contains(".accessibilityAddTraits(.isHeader)"),
            "Capture has a strong visual hierarchy but no explicit VoiceOver heading traits. The primary hero/state hierarchy and major Details sections should expose restrained heading semantics so rotor navigation matches the visible product structure."
        )
    }

    @Test("Heading semantics stay sparse and presentation-only")
    func headingSemanticsStaySparseAndPresentationOnly() throws {
        let source = try Self.shellSource()
        let headingTraitCount = source.components(separatedBy: ".accessibilityAddTraits(.isHeader)").count - 1

        #expect(
            headingTraitCount > 0,
            "At least one deliberate heading semantic is required before this contract can pass."
        )
        #expect(
            headingTraitCount <= 8,
            "Do not mark every label as a heading. Preserve a sparse rotor structure for the hero/current-state hierarchy and major Details sections only."
        )

        #expect(!source.contains("isHeader && coordinator"))
        #expect(!source.contains("isHeader && presentationAnalysisReady"))
        #expect(!source.contains("isHeader && physicalProcedurePermitted"))
    }

    @Test("VoiceOver headings do not weaken existing Capture truth boundaries")
    func headingSemanticsPreserveTruthBoundaries() throws {
        let source = try Self.shellSource()

        #expect(source.contains("PASSIVE / READ ONLY"))
        #expect(source.contains("Truth boundary"))
        #expect(source.contains("physicalProcedureLocked"))
        #expect(source.contains("PassiveBluetoothExperimentOneCoordinator"))
    }
}
