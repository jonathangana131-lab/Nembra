import Foundation
import Testing

@Suite("ES80 Capture Dynamic Type source acceptance")
struct ES80CaptureDynamicTypeSourceAcceptanceTests {
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

    @Test("six-stage experiment rail has an accessibility-size composition")
    func progressRailRecomposes() throws {
        let source = try Self.shellSource()
        let rail = try Self.section(source, from: "private func progressRail(", to: "@ViewBuilder")

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

        #expect(health.contains("TARGET"))
        #expect(health.contains("DISCOVERY"))
        #expect(health.contains("SEAL"))
        #expect(
            Self.hasIntentionalAdaptiveLayout(health),
            "Target / discovery / seal health must deliberately stack or otherwise adapt for accessibility text sizes."
        )
    }
}
