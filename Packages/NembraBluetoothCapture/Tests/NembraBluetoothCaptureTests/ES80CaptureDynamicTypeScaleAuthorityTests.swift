import Foundation
import Testing

@Suite("ES80 Capture Dynamic Type scale authority")
struct ES80CaptureDynamicTypeScaleAuthorityTests {
    private static func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func source(at components: String...) throws -> String {
        let url = components.reduce(repositoryRoot()) { partial, component in
            partial.appendingPathComponent(component)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static func fieldNoGoSection() throws -> Substring {
        let source = try source(at: "NembraApp", "App", "NembraApp.swift")
        let start = try #require(
            source.range(of: "private struct ES80ExperimentOneFieldNoGoView: View {")
        )
        return source[start.lowerBound...]
    }

    private static func hasLocalDynamicTypeScaleOverride(_ source: some StringProtocol) -> Bool {
        let compact = String(String(source).filter { !$0.isWhitespace })
        return compact.contains(".dynamicTypeSize(")
            || compact.contains(".environment(\\.dynamicTypeSize")
    }

    @Test("locked physical NO-GO honors the user's real accessibility text scale")
    func fieldNoGoDoesNotCapDynamicType() throws {
        let section = try Self.fieldNoGoSection()

        #expect(section.contains("@Environment(\\.dynamicTypeSize)"))
        #expect(section.contains("dynamicTypeSize.isAccessibilitySize"))
        #expect(
            !Self.hasLocalDynamicTypeScaleOverride(section),
            "The physical NO-GO surface must recompose for Accessibility sizes; it must not cap or replace the user's Dynamic Type environment."
        )
    }

    @Test("real Capture shell honors the user's real accessibility text scale")
    func captureShellDoesNotCapDynamicType() throws {
        let source = try Self.source(
            at: "NembraApp", "Features", "Research", "ES80CaptureShellView.swift"
        )

        #expect(source.contains("@Environment(\\.dynamicTypeSize)"))
        #expect(source.contains("dynamicTypeSize.isAccessibilitySize"))
        #expect(
            !Self.hasLocalDynamicTypeScaleOverride(source),
            "The real Capture shell must solve Accessibility XXXL with semantic recomposition, not a subtree Dynamic Type cap or environment replacement."
        )
    }
}
