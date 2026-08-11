import Foundation
import Testing

@Suite("Capture root Accessibility XXXL recompose")
struct TuyaCaptureRootAccessibilityXXXLRecompositionTests {
    @Test("root moves supporting copy behind the account-link action at accessibility sizes")
    func rootUsesActionFirstAccessibilityComposition() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let root = String(try section(
            in: app,
            from: "private struct CaptureP0Root: View",
            to: "private final class SecureLinkController"
        ))

        #expect(root.contains("@Environment(\\.dynamicTypeSize) private var dynamicTypeSize"))
        #expect(root.contains("if !dynamicTypeSize.isAccessibilitySize"))
        #expect(root.contains("private var rootAccountPanel: some View"))
        #expect(root.contains("private var accountLinkPrimaryFieldsAndAction: some View"))
        #expect(root.contains("private var accountLinkSupportingCopy: some View"))
        #expect(root.contains("nembra.capture.root.account-link-action"))

        let panel = String(try section(
            in: root,
            from: "private var rootAccountPanel: some View",
            to: "private var accountLinkPrimaryFieldsAndAction: some View"
        ))
        let accessibilityBranch = try #require(panel.range(of: "if dynamicTypeSize.isAccessibilitySize"))
        let primaryAction = try #require(
            panel.range(
                of: "accountLinkPrimaryFieldsAndAction",
                range: accessibilityBranch.upperBound..<panel.endIndex
            )
        )
        let supportingCopy = try #require(
            panel.range(
                of: "accountLinkSupportingCopy",
                range: primaryAction.upperBound..<panel.endIndex
            )
        )
        #expect(primaryAction.lowerBound < supportingCopy.lowerBound)

        let hero = String(try section(
            in: root,
            from: "private var rootHero: some View",
            to: "private var rootAccountPanel: some View"
        ))
        #expect(hero.contains("if !dynamicTypeSize.isAccessibilitySize"))
        #expect(hero.contains("One guided setup establishes the account and bound-device context"))
    }

    @Test("root recompose remains presentation-only")
    func rootRecomposeDoesNotChangeCaptureAuthority() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let root = String(try section(
            in: app,
            from: "private struct CaptureP0Root: View",
            to: "private final class SecureLinkController"
        ))

        #expect(!root.contains("writeValue"))
        #expect(!root.contains("publishDps"))
        #expect(!root.contains("NEMBRA_SIMULATION_"))
        #expect(!root.contains("SIMCTL_CHILD_"))
        #expect(root.contains("TuyaAccountBridge()"))
        #expect(root.contains("SecureLinkView(device: device)"))
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
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private enum SourceContractError: Error { case sectionMissing }
}
