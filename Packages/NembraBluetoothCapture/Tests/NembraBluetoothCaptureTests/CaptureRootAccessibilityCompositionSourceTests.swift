import Foundation
import Testing

@Suite("Capture root accessibility composition")
struct CaptureRootAccessibilityCompositionSourceTests {
    private static func repositoryRoot() -> URL {
        let testFile = URL(fileURLWithPath: #filePath)
        return testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func rootSource() throws -> Substring {
        let source = try String(
            contentsOf: repositoryRoot()
                .appendingPathComponent("NembraApp")
                .appendingPathComponent("App")
                .appendingPathComponent("NembraCaptureEntrypoint.swift"),
            encoding: .utf8
        )
        let beginning = try #require(source.range(of: "private struct CaptureP0Root: View"))
        let controller = try #require(
            source.range(
                of: "private final class SecureLinkController",
                range: beginning.lowerBound..<source.endIndex
            )
        )
        return source[beginning.lowerBound..<controller.lowerBound]
    }

    @Test("Accessibility Dynamic Type keeps the initial account task compact and reachable")
    func accessibilityLayoutIsTaskFirst() throws {
        let root = try Self.rootSource()

        #expect(root.contains("@Environment(\\.dynamicTypeSize) private var dynamicTypeSize"))
        #expect(root.contains("dynamicTypeSize.isAccessibilitySize"))
        #expect(root.contains("VStack(alignment: .leading, spacing: accessibilityLayout ? 14 : 22)"))
        #expect(root.contains("VStack(alignment: .leading, spacing: accessibilityLayout ? 6 : 8)"))
        #expect(root.contains("Text(accessibilityLayout ? \"Prepare scooter link\" : \"Prepare the scooter link\")"))
        #expect(root.contains(".font(accessibilityLayout ? .title2.bold() : .largeTitle.bold())"))
        #expect(root.contains("Read-only setup. Scooter settings stay unchanged."))
        #expect(root.contains("Approve access to continue."))
        #expect(root.contains(".font(accessibilityLayout ? .headline.bold() : .title3.bold())"))
        #expect(root.contains(".dynamicTypeSize(.xSmall ... .xxxLarge)"))
        #expect(root.contains(".padding(.top, accessibilityLayout ? 12 : 22)"))
        #expect(root.contains(".padding(accessibilityLayout ? 14 : 18)"))
    }

    @Test("Standard Dynamic Type copy remains the accepted preflight wording")
    func standardCopyIsPreserved() throws {
        let root = try Self.rootSource()

        #expect(root.contains("Prepare the scooter link"))
        #expect(root.contains("One guided setup establishes the account and bound-device context Nembra will use before passive target correlation begins."))
        #expect(root.contains("Text(accessibilityLayout && !tuya.isLinked ? \"Approve access to continue.\" : tuya.statusMessage)"))
    }
}
