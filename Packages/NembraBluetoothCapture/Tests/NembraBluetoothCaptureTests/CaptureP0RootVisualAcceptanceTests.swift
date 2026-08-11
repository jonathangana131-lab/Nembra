import Foundation
import Testing

@Suite("Capture P0 root visual acceptance")
struct CaptureP0RootVisualAcceptanceTests {
    @Test("public root visibly fails closed while preserving metadata-only setup")
    func publicRootShowsFieldAuthorityBeforeAccountSetup() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let root = try section(
            in: source,
            from: "private struct CaptureP0Root: View",
            to: "private final class SecureLinkController:"
        )
        let body = String(root)

        #expect(body.contains("@Environment(\\.dynamicTypeSize) private var dynamicTypeSize"))
        #expect(body.contains("private let buildIdentity = NembraCaptureBuildIdentity.current"))
        #expect(body.contains("buildIdentity.isAuthoritativeFieldBuild"))
        #expect(body.contains("Text(fieldBuildIsAuthoritative ? \"Build provenance ready\" : \"Physical capture locked\")"))
        #expect(body.contains("This public build can prepare account metadata, but it cannot scan, connect, or collect physical scooter evidence."))
        #expect(body.contains("This step reads Tuya account/device metadata only. It never starts Bluetooth or changes scooter settings."))
        #expect(body.contains("NavigationLink(fieldBuildIsAuthoritative ? \"Continue to preflight\" : \"View locked preflight\")"))

        let heroUse = try #require(body.range(of: "rootHero\n                        buildAuthorityStatus\n                        accountSetupPanel"))
        #expect(heroUse.lowerBound < body.endIndex)
    }

    @Test("Accessibility XXXL receives a compact root hero and labeled metadata input")
    func accessibilityRootRecomposesInsteadOfScalingMarketingCopy() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let root = String(try section(
            in: source,
            from: "private struct CaptureP0Root: View",
            to: "private final class SecureLinkController:"
        ))

        #expect(root.contains("if !dynamicTypeSize.isAccessibilitySize"))
        #expect(root.contains("fieldBuildIsAuthoritative ? \"Prepare Capture\" : \"Capture locked\""))
        #expect(root.contains("Account setup only in this public build."))
        #expect(root.contains(".font(dynamicTypeSize.isAccessibilitySize ? .title2.bold() : .largeTitle.bold())"))
        #expect(root.contains("Text(\"Tuya Smart user code\")"))
        #expect(root.contains("TextField(\"Paste user code\""))
        #expect(root.contains(".accessibilityLabel(\"Tuya Smart user code\")"))
        #expect(root.contains(".accessibilityIdentifier(\"capture.p0-root\")"))
        #expect(root.contains(".accessibilityAddTraits(.isHeader)"))
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let startRange = source.range(of: start),
              let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \(start) ... \(end)")
            throw SourceContractError.sectionMissing
        }
        return source[startRange.lowerBound..<endRange.lowerBound]
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private enum SourceContractError: Error {
        case sectionMissing
    }
}
