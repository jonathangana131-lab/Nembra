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
        let end = try #require(source.range(of: endNeedle, range: start.lowerBound..<source.endIndex))
        return source[start.lowerBound..<end.lowerBound]
    }

    private static func hasAdaptiveLayout(_ section: Substring) -> Bool {
        section.contains("dynamicTypeSize.isAccessibilitySize")
            || section.contains("ViewThatFits")
            || section.contains("AnyLayout")
    }

    @Test("Capture explicitly observes Dynamic Type")
    func captureObservesDynamicType() throws {
        let source = try Self.shellSource()
        #expect(source.contains("@Environment(\\.dynamicTypeSize)"))
        #expect(source.contains("dynamicTypeSize.isAccessibilitySize"))
    }

    @Test("hero status recomposes at accessibility sizes")
    func heroStatusRecomposes() throws {
        let source = try Self.shellSource()
        let hero = try Self.section(
            source,
            from: "private func hero(for phase:",
            to: "#if DEBUG && targetEnvironment(simulator)"
        )
        #expect(hero.contains("PASSIVE / READ ONLY"))
        #expect(Self.hasAdaptiveLayout(hero))
    }

    @Test("six-stage Capture rail recomposes at accessibility sizes")
    func progressRailRecomposes() throws {
        let source = try Self.shellSource()
        let rail = try Self.section(source, from: "private func progressRail(", to: "@ViewBuilder")
        for label in ["OFF 1", "ON 1", "OFF 2", "ON 2", "READY", "SEAL"] {
            #expect(rail.contains(label))
        }
        #expect(rail.contains("CAPTURE PROGRESS"))
        #expect(Self.hasAdaptiveLayout(rail))
    }

    @Test("Capture health recomposes at accessibility sizes")
    func captureHealthRecomposes() throws {
        let source = try Self.shellSource()
        let health = try Self.section(
            source,
            from: "private func observationHealthStrip(",
            to: "private var completionPanel"
        )
        #expect(health.contains("TARGET"))
        #expect(health.contains("DISCOVERY"))
        #expect(health.contains("SEAL"))
        #expect(Self.hasAdaptiveLayout(health))
        #expect(health.contains("es80.capture.health"))
    }
}