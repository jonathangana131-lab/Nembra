import Foundation
import Testing

@Suite("ES80 Capture accessibility touch-target acceptance")
struct ES80CaptureAccessibilityTouchTargetTests {
    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func source(_ components: String...) throws -> String {
        let url = components.reduce(repositoryRoot) { partial, component in
            partial.appendingPathComponent(component)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static func slice(
        _ source: String,
        from startToken: String,
        through endToken: String
    ) throws -> Substring {
        let start = try #require(source.range(of: startToken))
        let end = try #require(
            source.range(of: endToken, range: start.lowerBound..<source.endIndex)
        )
        return source[start.lowerBound..<end.upperBound]
    }

    @Test("field-lock engineering disclosure keeps a 44-point minimum interactive target")
    func engineeringDetailsDisclosureKeepsMinimumTouchTarget() throws {
        let app = try Self.source("NembraApp", "App", "NembraApp.swift")
        let disclosure = try Self.slice(
            app,
            from: "Button {\n                        engineeringDetailsExpanded.toggle()",
            through: ".accessibilityIdentifier(\"es80.capture.engineering-details\")"
        )

        #expect(disclosure.contains(".frame(maxWidth: .infinity, alignment: .leading)"))
        #expect(disclosure.contains(".frame(minHeight: 44)"))
        #expect(disclosure.contains(".contentShape(Rectangle())"))
        #expect(disclosure.contains(".buttonStyle(.plain)"))
    }

    @Test("Capture primary and secondary controls retain large minimum touch targets")
    func captureShellControlsKeepLargeMinimumTouchTargets() throws {
        let shell = try Self.source(
            "NembraApp", "Features", "Research", "ES80CaptureShellView.swift"
        )

        let primary = try Self.slice(
            shell,
            from: "private func primaryButton(",
            through: ".accessibilityIdentifier(identifier)"
        )
        #expect(primary.contains(".frame(minHeight: 56)"))
        #expect(primary.contains(".buttonStyle(.plain)"))

        let secondary = try Self.slice(
            shell,
            from: "private func secondaryButton(",
            through: ".accessibilityIdentifier(identifier)"
        )
        #expect(secondary.contains(".frame(minHeight: 50)"))
        #expect(secondary.contains(".buttonStyle(.plain)"))
    }

    @Test("final Share action keeps the same large touch-target contract")
    func finalShareActionKeepsLargeMinimumTouchTarget() throws {
        let shell = try Self.source(
            "NembraApp", "Features", "Research", "ES80CaptureShellView.swift"
        )
        let share = try Self.slice(
            shell,
            from: "ShareLink(item: shareURL)",
            through: ".accessibilityIdentifier(\"es80.capture.share\")"
        )

        #expect(share.contains("Label(\"Share Capture\", systemImage: \"square.and.arrow.up\")"))
        #expect(share.contains(".frame(minHeight: 56)"))
        #expect(share.contains(".buttonStyle(.plain)"))
    }
}
