import Foundation
import Testing

@Suite("Capture P0 root visual acceptance")
struct CaptureP0RootVisualAcceptanceTests {
    @Test("public root visibly fails closed while preserving metadata-only setup")
    func publicRootShowsBuildAuthorityBeforeAccountSetup() throws {
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
        #expect(body.contains("isAccessibilityLayout ? \"Physical lock\" : \"Physical capture locked\""))
        #expect(body.contains(".accessibilityLabel(fieldBuildIsAuthoritative ? \"Build provenance ready\" : \"Physical capture locked\")"))
        #expect(body.contains("This public build can prepare account metadata only. Bluetooth and physical evidence collection are locked."))
        #expect(body.contains("Account setup is available. Bluetooth scanning, connection, and physical evidence stay locked until the reviewed field build is installed."))
        #expect(body.contains("This step reads Tuya account/device metadata only. It never starts Bluetooth or changes scooter settings."))
        #expect(body.contains("NavigationLink(fieldBuildIsAuthoritative ? \"Continue to preflight\" : \"View locked preflight\")"))

        let heroUse = try #require(body.range(of: "rootHero\n                        buildAuthorityStatus\n                        accountSetupPanel"))
        #expect(heroUse.lowerBound < body.endIndex)
    }

    @Test("Accessibility XXXL exposes the metadata action before support copy")
    func accessibilityRootRecomposesForTheFirstFold() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let root = String(try section(
            in: source,
            from: "private struct CaptureP0Root: View",
            to: "private final class SecureLinkController:"
        ))

        #expect(root.contains("private var isAccessibilityLayout: Bool"))
        #expect(root.contains("private var rootHero: some View"))
        #expect(root.contains("if !isAccessibilityLayout"))
        #expect(root.contains("isAccessibilityLayout ? \"Physical lock\" : \"Physical capture locked\""))
        #expect(root.contains(".font(isAccessibilityLayout ? .body.weight(.semibold) : .headline)"))
        #expect(root.contains(".dynamicTypeSize(...DynamicTypeSize.accessibility1)"))
        #expect(root.contains("isAccessibilityLayout ? \"Account setup\" : \"Prepare account metadata\""))
        #expect(root.contains("TextField(isAccessibilityLayout ? \"Tuya user code\" : \"Paste user code\""))
        #expect(root.contains("Label(isAccessibilityLayout ? \"Create QR\" : \"Create approval QR\""))
        #expect(root.contains(".accessibilityLabel(\"Create approval QR\")"))
        #expect(root.contains(".accessibilityIdentifier(\"nembra.capture.root.account-link-action\")"))
        #expect(root.contains(".accessibilityIdentifier(\"capture.p0-root\")"))
        #expect(root.contains("private func rootSection"))
        #expect(!root.contains("private func rootPanel"))

        let panel = String(try section(
            in: root,
            from: "private var accountSetupPanel: some View",
            to: "private var statusText: some View"
        ))
        let field = try #require(panel.range(of: "TextField(isAccessibilityLayout ? \"Tuya user code\" : \"Paste user code\""))
        let action = try #require(panel.range(of: "Label(isAccessibilityLayout ? \"Create QR\" : \"Create approval QR\""))
        let accessibilitySupport = try #require(
            panel.range(
                of: "if isAccessibilityLayout, tuya.phase != .needsUserCode",
                range: action.upperBound..<panel.endIndex
            )
        )
        #expect(field.lowerBound < action.lowerBound)
        #expect(action.lowerBound < accessibilitySupport.lowerBound)
        #expect(!panel.contains("Account setup only in this public build."))

        let authority = String(try section(
            in: root,
            from: "private var buildAuthorityStatus: some View",
            to: "private var accountSetupPanel: some View"
        ))
        #expect(authority.contains("if !isAccessibilityLayout"))
        #expect(authority.contains(".accessibilityLabel(fieldBuildIsAuthoritative ? \"Build provenance ready\" : \"Physical capture locked\")"))
        #expect(authority.contains("This public build can prepare account metadata only. Bluetooth and physical evidence collection are locked."))
    }

    @Test("Accessibility action remains full-width and precedes verbose status")
    func accessibilityActionRemainsFullWidthAndBeforeVerboseStatus() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let panel = String(try section(
            in: source,
            from: "private var accountSetupPanel: some View",
            to: "private var statusText: some View"
        ))

        let standardSupport = try #require(panel.range(of: "This step reads Tuya account/device metadata only. It never starts Bluetooth or changes scooter settings."))
        let field = try #require(panel.range(of: "TextField(isAccessibilityLayout ? \"Tuya user code\" : \"Paste user code\""))
        let action = try #require(panel.range(of: "Label(isAccessibilityLayout ? \"Create QR\" : \"Create approval QR\""))
        let standardStatus = try #require(panel.range(
            of: "statusText",
            range: standardSupport.upperBound..<field.lowerBound
        ))
        let accessibilityBranch = try #require(panel.range(
            of: "if isAccessibilityLayout, tuya.phase != .needsUserCode",
            range: action.upperBound..<panel.endIndex
        ))
        let accessibilityStatus = try #require(panel.range(
            of: "statusText",
            range: accessibilityBranch.upperBound..<panel.endIndex
        ))

        #expect(standardStatus.lowerBound < field.lowerBound)
        #expect(field.lowerBound < action.lowerBound)
        #expect(action.lowerBound < accessibilityBranch.lowerBound)
        #expect(accessibilityBranch.lowerBound < accessibilityStatus.lowerBound)
        #expect(panel.contains(".frame(maxWidth: .infinity, minHeight: 50)"))
        #expect(panel.contains(".tint(.cyan)"))
        #expect(panel.contains(".accessibilityLabel(\"Create approval QR\")"))
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
