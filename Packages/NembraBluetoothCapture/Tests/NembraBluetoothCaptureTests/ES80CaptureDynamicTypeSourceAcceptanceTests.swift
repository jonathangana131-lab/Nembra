import Foundation
import Testing

@Suite("ES80 Capture Dynamic Type source acceptance")
struct ES80CaptureDynamicTypeSourceAcceptanceTests {
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

    private static func researchUITestSource() throws -> String {
        try String(
            contentsOf: repositoryRoot()
                .appendingPathComponent("NembraUITests")
                .appendingPathComponent("ES80ResearchCaptureUITests.swift"),
            encoding: .utf8
        )
    }

    private static func section(
        _ source: String,
        from startNeedle: String,
        to endNeedle: String
    ) throws -> Substring {
        let start = try #require(source.range(of: startNeedle))
        let end = try #require(
            source.range(
                of: endNeedle,
                range: start.lowerBound..<source.endIndex
            )
        )
        return source[start.lowerBound..<end.lowerBound]
    }

    private static func hasIntentionalAdaptiveLayout(_ section: Substring) -> Bool {
        section.contains("dynamicTypeSize.isAccessibilitySize")
            || section.contains("ViewThatFits")
            || section.contains("AnyLayout")
    }

    @Test("Capture explicitly observes Dynamic Type for product recomposition")
    func captureObservesDynamicType() throws {
        let source = try Self.shellSource()

        #expect(
            source.contains("@Environment(\\.dynamicTypeSize)"),
            "Capture must observe system Dynamic Type rather than relying on fixed horizontal layouts to compress implicitly."
        )
        #expect(
            source.contains("dynamicTypeSize.isAccessibilitySize"),
            "Accessibility text sizes require an intentional Capture recomposition path."
        )
    }

    @Test("hero status stops competing horizontally at accessibility sizes")
    func heroStatusRecomposes() throws {
        let source = try Self.shellSource()
        let hero = try Self.section(source, from: "private func hero(for phase:", to: "#if DEBUG && targetEnvironment(simulator)")

        #expect(hero.contains("PASSIVE / READ ONLY"))
        #expect(
            Self.hasIntentionalAdaptiveLayout(hero),
            "Hero state + PASSIVE / READ ONLY must deliberately recompose instead of squeezing at accessibility text sizes."
        )
    }

    @Test("six-stage capture rail has an accessibility-size composition")
    func progressRailRecomposes() throws {
        let source = try Self.shellSource()
        let rail = try Self.section(source, from: "private func progressRail(", to: "@ViewBuilder")

        #expect(rail.contains("CAPTURE PROGRESS"))
        for label in ["OFF 1", "ON 1", "OFF 2", "ON 2", "READY", "SEAL"] {
            #expect(rail.contains(label))
        }
        #expect(
            Self.hasIntentionalAdaptiveLayout(rail),
            "The six fixed horizontal stage labels must not depend on compression to survive accessibility text sizes."
        )
    }

    @Test("capture health stops forcing three metrics into one row at accessibility sizes")
    func captureHealthRecomposes() throws {
        let source = try Self.shellSource()
        let health = try Self.section(source, from: "private func observationHealthStrip(", to: "private var completionPanel")

        #expect(
            health.contains("SIGNAL"),
            "The Dynamic Type contract must follow the accepted rider-facing SIGNAL label rather than reviving the superseded TARGET implementation term."
        )
        #expect(health.contains("DISCOVERY"))
        #expect(health.contains("SEAL"))
        #expect(
            !health.contains("healthItem(\"TARGET\""),
            "Accessibility acceptance must not regress the rider-facing health strip back to TARGET vocabulary."
        )
        #expect(
            Self.hasIntentionalAdaptiveLayout(health),
            "Signal / discovery / seal health must deliberately stack or otherwise adapt for accessibility text sizes."
        )
    }

    @Test("horizon-ready Capture retains Accessibility XXXL visual evidence")
    func horizonReadyAccessibilityXXXLVisualEvidenceIsRequired() throws {
        let source = try Self.researchUITestSource()
        let block = try Self.section(
            source,
            from: "func testV14SimulatorQAHorizonReadyRemainsActionableAtAccessibilityExtraExtraExtraLarge()",
            to: "func testV14SimulatorQAHorizonReadyLandscapeKeepsFinishAndTruthVisible()"
        )

        #expect(block.contains("--es80-capture-qa-scenario=observationHorizonReady"))
        #expect(block.contains("-UIPreferredContentSizeCategoryName"))
        #expect(block.contains("UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"))
        #expect(block.contains("es80.capture-shell"))
        #expect(block.contains("es80.capture.simulator-qa"))
        #expect(block.contains("es80.capture.experiment-progress"))
        #expect(block.contains("es80.capture.finish"))
        #expect(block.contains("Capture can be sealed"))
        #expect(block.contains("Horizon Ready — Accessibility XXXL — Progress"))
        #expect(block.contains("Horizon Ready — Accessibility XXXL — Health"))
        #expect(block.contains("Horizon Ready — Accessibility XXXL — Status"))
        #expect(block.contains("Horizon Ready — Accessibility XXXL — Seal"))
    }

    @Test("existing Accessibility XXXL product evidence is not regressed")
    func existingAccessibilityXXXLProductEvidenceRemains() throws {
        let source = try Self.researchUITestSource()

        #expect(source.contains("UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"))
        #expect(source.contains("Rider NO-GO — Accessibility XXXL"))
        #expect(source.contains("Capture Complete — Accessibility XXXL"))
        #expect(
            source.contains("--es80-capture-qa-scenario=captureComplete"),
            "Capture Complete Accessibility XXXL remains valuable positive-state evidence while horizon/progress/health evidence is added."
        )
    }
}
