import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture AX source regressions")
struct CaptureAXScopeRegressionSourceTests {
    @Test("SecureLink owns its accessibility-size decision")
    func secureLinkUsesItsOwnDynamicTypeEnvironment() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let secureLink = String(try section(
            in: app,
            from: "private struct SecureLinkView: View",
            to: "private struct SecureTransfer: Transferable"
        ))

        #expect(secureLink.contains("@Environment(\\.dynamicTypeSize) private var dynamicTypeSize"))
        #expect(secureLink.contains("Label(dynamicTypeSize.isAccessibilitySize ? \"Details\" : \"Engineering details\", systemImage: \"wrench.and.screwdriver\")"))
        #expect(!secureLink.contains("Label(isAccessibilityLayout ? \"Details\" : \"Engineering details\", systemImage: \"wrench.and.screwdriver\")"))
        #expect(secureLink.contains(".accessibilityLabel(\"Engineering details\")"))
    }

    @Test("AX user-code field keeps persistent sighted identity without duplicate VoiceOver")
    func accessibilityUserCodeFieldKeepsPersistentIdentity() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let account = String(try section(
            in: app,
            from: "private var accountSetupPanel: some View",
            to: "private var statusText: some View"
        ))

        let visibleLabel = try #require(account.range(of: "Text(isAccessibilityLayout ? \"Tuya user code\" : \"Tuya Smart user code\")"))
        let hiddenDuplicate = try #require(account.range(
            of: ".accessibilityHidden(true)",
            range: visibleLabel.upperBound..<account.endIndex
        ))
        let field = try #require(account.range(
            of: "TextField(isAccessibilityLayout ? \"Tuya user code\" : \"Paste user code\"",
            range: hiddenDuplicate.upperBound..<account.endIndex
        ))
        let semanticLabel = try #require(account.range(
            of: ".accessibilityLabel(\"Tuya Smart user code\")",
            range: field.upperBound..<account.endIndex
        ))
        let action = try #require(account.range(
            of: "Label(isAccessibilityLayout ? \"Create QR\" : \"Create approval QR\"",
            range: semanticLabel.upperBound..<account.endIndex
        ))

        #expect(account.contains(".dynamicTypeSize(...DynamicTypeSize.accessibility1)"))
        #expect(visibleLabel.lowerBound < hiddenDuplicate.lowerBound)
        #expect(hiddenDuplicate.lowerBound < field.lowerBound)
        #expect(field.lowerBound < semanticLabel.lowerBound)
        #expect(semanticLabel.lowerBound < action.lowerBound)
    }

    @Test("AX sighted compaction preserves full VoiceOver authority identity")
    func accessibilityCompactCopyKeepsFullSemantics() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let strings = try readRepositoryFile("NembraApp/Resources/Localizable.strings")

        #expect(strings.contains("\"Capture locked\" = \"Locked\";"))
        #expect(strings.contains("\"Tuya user code\" = \"Tuya code\";"))
        #expect(app.contains(".accessibilityLabel(fieldBuildIsAuthoritative ? \"Build provenance ready\" : \"Physical capture locked\")"))
        #expect(app.contains(".accessibilityLabel(\"Tuya Smart user code\")"))
        #expect(!strings.contains("\"Physical capture locked\" ="))
        #expect(!strings.contains("\"Tuya Smart user code\" ="))
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
