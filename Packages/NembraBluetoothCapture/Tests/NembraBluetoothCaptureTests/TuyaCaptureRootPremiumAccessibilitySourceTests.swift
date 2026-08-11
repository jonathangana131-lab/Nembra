import Foundation
import Testing

@Suite("Capture premium root accessibility source acceptance")
struct TuyaCaptureRootPremiumAccessibilitySourceTests {
    @Test("accessibility layout prioritizes the account field and primary action")
    func accessibilityCompositionIsActionFirst() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let root = String(try section(
            in: app,
            from: "private struct CaptureP0Root: View",
            to: "private final class SecureLinkController"
        ))

        #expect(root.contains("@Environment(\\.dynamicTypeSize) private var dynamicTypeSize"))
        #expect(root.contains("private var isAccessibilityLayout: Bool { dynamicTypeSize.isAccessibilitySize }"))

        let intro = String(try section(
            in: root,
            from: "private var intro: some View",
            to: "private var accountSection: some View"
        ))
        #expect(intro.contains("if !isAccessibilityLayout"))
        #expect(intro.contains("Set up Capture"))
        #expect(intro.contains(".font(isAccessibilityLayout ? .title.bold() : .largeTitle.bold())"))

        let account = String(try section(
            in: root,
            from: "private var accountSection: some View",
            to: "private var statusText: some View"
        ))
        let unlinked = try #require(account.range(of: "if tuya.isLinked"))
        let accessibilityStatus = try #require(
            account.range(
                of: "if isAccessibilityLayout {\n                        statusText",
                range: unlinked.upperBound..<account.endIndex
            )
        )
        let field = try #require(
            account.range(
                of: "TextField(\"Tuya Smart User Code\"",
                range: unlinked.upperBound..<accessibilityStatus.lowerBound
            )
        )
        let action = try #require(
            account.range(
                of: "Label(\"Create approval QR\", systemImage: \"qrcode\")",
                range: field.upperBound..<accessibilityStatus.lowerBound
            )
        )

        #expect(field.lowerBound < action.lowerBound)
        #expect(action.lowerBound < accessibilityStatus.lowerBound)
        #expect(account.contains(".frame(maxWidth: .infinity, minHeight: 50)"))
        #expect(account.contains(".accessibilityHint("))
    }

    @Test("root redesign remains presentation-only and preserves the no-command boundary")
    func rootRedesignDoesNotMintAuthority() throws {
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
        #expect(!root.contains("local_key"))
        #expect(root.contains("No scooter commands are sent by this setup flow."))
        #expect(root.contains("NavigationLink(\"Continue to Capture\") { SecureLinkView(device: device) }"))
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
