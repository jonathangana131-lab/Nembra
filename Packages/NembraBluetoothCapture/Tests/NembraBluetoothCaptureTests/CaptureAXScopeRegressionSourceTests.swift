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

    @Test("root exposes one system Apple action and disclosed private recovery fields")
    func accessibilityAccountActionsRemainScopedAndPrivate() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let root = String(try section(
            in: app,
            from: "@MainActor\nprivate struct CaptureP0Root: View",
            to: "@MainActor\nprivate final class SecureLinkController:"
        ))
        let account = String(try section(
            in: root,
            from: "private var accountSetupPanel: some View",
            to: "private var scooterChooserPanel: some View"
        ))

        let apple = try #require(account.range(of: "SignInWithAppleButton(.signIn)"))
        let identifier = try #require(account.range(
            of: ".accessibilityIdentifier(\"nembra.capture.root.account-link-action\")",
            range: apple.upperBound..<account.endIndex
        ))
        let recovery = try #require(account.range(
            of: "DisclosureGroup(\"Use email or phone instead\"",
            range: identifier.upperBound..<account.endIndex
        ))
        let accountField = try #require(account.range(
            of: "TextField(sdkAccount.method == .email ? \"Tuya account email\" : \"Tuya account phone number\"",
            range: recovery.upperBound..<account.endIndex
        ))
        let privateAccount = try #require(account.range(
            of: ".privacySensitive()",
            range: accountField.upperBound..<account.endIndex
        ))
        let codeField = try #require(account.range(
            of: "SecureField(\"Verification code\"",
            range: privateAccount.upperBound..<account.endIndex
        ))
        let privateCode = try #require(account.range(
            of: ".privacySensitive()",
            range: codeField.upperBound..<account.endIndex
        ))

        #expect(apple.lowerBound < identifier.lowerBound)
        #expect(identifier.lowerBound < recovery.lowerBound)
        #expect(recovery.lowerBound < accountField.lowerBound)
        #expect(accountField.lowerBound < privateAccount.lowerBound)
        #expect(privateAccount.lowerBound < codeField.lowerBound)
        #expect(codeField.lowerBound < privateCode.lowerBound)
        #expect(!account.contains("Paste user code"))
        #expect(!account.contains("approval QR"))
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
