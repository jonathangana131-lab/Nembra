import Foundation
import Testing

@Suite("ES80 Capture progress-rail Dynamic Type acceptance")
struct ES80CaptureProgressRailDynamicTypeAcceptanceTests {
    private static func captureShellSource() throws -> String {
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

    private static func progressRail(in source: String) throws -> Substring {
        let start = try #require(source.range(of: "private func progressRail("))
        let end = try #require(
            source.range(
                of: "@ViewBuilder\n    private func primaryContent(",
                range: start.lowerBound..<source.endIndex
            )
        )
        return source[start.lowerBound..<end.lowerBound]
    }

    @Test("progress rail has an explicit Accessibility-size visual fallback")
    func progressRailAdaptsAtAccessibilityDynamicType() throws {
        let source = try Self.captureShellSource()
        let rail = try Self.progressRail(in: source)

        let hasDynamicTypeEnvironment = source.contains("@Environment(\\.dynamicTypeSize)")
        let hasAccessibilityBranch = rail.contains("isAccessibilitySize")
        let hasAdaptiveLayout = rail.contains("ViewThatFits")
            || rail.contains("AnyLayout")
            || rail.contains("if dynamicTypeSize.isAccessibilitySize")

        #expect(
            hasDynamicTypeEnvironment && hasAccessibilityBranch && hasAdaptiveLayout,
            "The six fixed OFF 1 / ON 1 / OFF 2 / ON 2 / READY / SEAL labels currently share one horizontal HStack with no Accessibility Dynamic Type fallback. Add an explicit large-type presentation (for example a compact current-stage summary or adaptive layout) instead of relying on compression/clipping."
        )
    }

    @Test("accessibility fallback must preserve stage meaning without shrinking text")
    func accessibilityFallbackPreservesTruthfulStageMeaning() throws {
        let source = try Self.captureShellSource()
        let rail = try Self.progressRail(in: source)

        #expect(!rail.contains("minimumScaleFactor("), "Do not solve the progress rail by shrinking already-small labels at Accessibility sizes.")
        #expect(rail.contains("progressAccessibilityLabel("), "VoiceOver stage truth must remain package-derived and intact.")
        #expect(rail.contains("OFF 1"))
        #expect(rail.contains("ON 1"))
        #expect(rail.contains("OFF 2"))
        #expect(rail.contains("ON 2"))
        #expect(rail.contains("READY"))
        #expect(rail.contains("SEAL"))
    }
}
