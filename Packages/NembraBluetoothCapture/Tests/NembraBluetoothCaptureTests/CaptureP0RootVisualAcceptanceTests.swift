import Foundation
import Testing

@Suite("Capture P0 root visual acceptance")
struct CaptureP0RootVisualAcceptanceTests {
    @Test("unstamped public root explains its lock and cannot start SDK authorization")
    func publicRootIsExplanatoryAndFailClosed() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let root = String(try section(
            in: source,
            from: "@MainActor\nprivate struct CaptureP0Root: View",
            to: "@MainActor\nprivate final class SecureLinkController:"
        ))

        #expect(root.contains("private let buildIdentity = NembraCaptureBuildIdentity.current"))
        #expect(root.contains("private var fieldBuildCanPrepareAuthorization: Bool { buildIdentity.hasCompleteFieldBuildMetadata }"))
        #expect(root.contains("private var fieldBuildIsAuthoritative: Bool { buildIdentity.isAuthoritativeFieldBuild }"))
        #expect(root.contains("guard fieldBuildCanPrepareAuthorization else { return }\n        sdkAccount.bootstrap()"))
        #expect(root.contains("if !fieldBuildCanPrepareAuthorization {"))
        #expect(root.contains("Label(\"Review field requirements\", systemImage: \"lock.shield\")"))
        #expect(root.contains("Shows why this public build cannot start account or Bluetooth authorization."))
        #expect(root.contains("This public build cannot authorize Bluetooth or collect physical evidence."))
        #expect(root.contains(".accessibilityIdentifier(\"nembra.capture.root.account-link-action\")"))

        let publicBranch = try #require(root.range(of: "if !fieldBuildCanPrepareAuthorization {"))
        let loggedInBranch = try #require(root.range(
            of: "} else if sdkAccount.loggedIn {",
            range: publicBranch.upperBound..<root.endIndex
        ))
        let appleAction = try #require(root.range(
            of: "SignInWithAppleButton(.signIn)",
            range: loggedInBranch.upperBound..<root.endIndex
        ))
        #expect(publicBranch.lowerBound < loggedInBranch.lowerBound)
        #expect(loggedInBranch.lowerBound < appleAction.lowerBound)
    }

    @Test("metadata-complete root prepares only the non-authorizing app-container transport")
    func metadataCompleteRootPreparesTransportBeforeSDKSetup() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let root = String(try section(
            in: source,
            from: "@MainActor\nprivate struct CaptureP0Root: View",
            to: "@MainActor\nprivate final class SecureLinkController:"
        ))

        #expect(root.contains("@State private var authorizationTransportBootstrapError: String?"))
        #expect(root.contains(".prepareAuthorizationTransferDirectoryForFieldTransport()"))
        #expect(root.contains("authorizationTransportBootstrapError = nil"))
        #expect(root.contains("One-time authorization transfer storage could not be prepared. Bluetooth remains locked."))
        #expect(root.contains("fieldBuildCanPrepareAuthorization && authorizationTransportBootstrapError == nil && sdkAccount.loggedIn"))
        #expect(root.contains("SecureLinkView(device: selected, sdkAccount: sdkAccount)"))

        let body = try section(
            in: root,
            from: "var body: some View",
            to: "@ViewBuilder\n    private var rootHero"
        )
        let bootstrap = try #require(body.range(of: "prepareAuthorizationTransport()"))
        let synchronize = try #require(body.range(of: "synchronizeSDKSession()", range: bootstrap.upperBound..<body.endIndex))
        #expect(bootstrap.lowerBound < synchronize.lowerBound)

        let prepare = try section(
            in: root,
            from: "private func prepareAuthorizationTransport()",
            to: "private func synchronizeSDKSession()"
        )
        #expect(prepare.contains("guard fieldBuildCanPrepareAuthorization else { return }"))
        #expect(prepare.contains("prepareAuthorizationTransferDirectoryForFieldTransport()"))
        #expect(!prepare.contains("advanceInboxHandoffIfAvailable()"))
        #expect(!prepare.contains("admitOFF1Start()"))
        #expect(!prepare.contains("authorizeFromInbox()"))
    }

    @Test("field root uses one official SDK Apple action with disclosed email or phone recovery")
    func officialSDKLoginIsSingleAndRecoverable() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let root = String(try section(
            in: source,
            from: "@MainActor\nprivate struct CaptureP0Root: View",
            to: "@MainActor\nprivate final class SecureLinkController:"
        ))

        #expect(root.occurrenceCount(of: "SignInWithAppleButton(.signIn)") == 1)
        #expect(root.contains("request.requestedScopes = [.fullName, .email]"))
        #expect(root.contains("sdkAccount.loginWithApple(credential: credential)"))
        #expect(root.contains("DisclosureGroup(\"Use email or phone instead\", isExpanded: $showAlternativeLogin)"))
        #expect(root.contains("ForEach(OfficialTuyaAccountAuthorizer.LoginMethod.allCases)"))
        #expect(root.contains("TextField(sdkAccount.method == .email ? \"Tuya account email\" : \"Tuya account phone number\""))
        #expect(root.contains("Button(sdkAccount.busy ? \"Contacting Tuya…\" : \"Send verification code\") { sdkAccount.sendCode() }"))
        #expect(root.contains("SecureField(\"Verification code\", text: $sdkAccount.verificationCode)"))
        #expect(root.contains("Button(\"Continue\") { sdkAccount.login() }"))
        #expect(root.contains(".privacySensitive()"))
        #expect(root.contains("SecureLinkView(device: selected, sdkAccount: sdkAccount)"))
        #expect(!root.contains("TuyaAccountBridge"))
        #expect(!root.contains("Create approval QR"))
        #expect(!root.contains("Paste user code"))
    }

    @Test("large type keeps lock authority and the only safe public action in the first fold")
    func accessibilityRootKeepsSafeActionAheadOfDetails() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let root = String(try section(
            in: source,
            from: "@MainActor\nprivate struct CaptureP0Root: View",
            to: "@MainActor\nprivate final class SecureLinkController:"
        ))

        #expect(root.contains("@Environment(\\.dynamicTypeSize) private var dynamicTypeSize"))
        #expect(root.contains("private var isAccessibilityLayout: Bool { dynamicTypeSize.isAccessibilitySize }"))
        #expect(root.contains("if !isAccessibilityLayout"))
        #expect(root.contains(".dynamicTypeSize(...DynamicTypeSize.accessibility1)"))
        #expect(root.contains(".accessibilitySortPriority(isAccessibilityLayout ? 100 : 0)"))
        #expect(root.contains(".frame(maxWidth: .infinity, minHeight: 52)"))
        #expect(root.contains(".accessibilityIdentifier(\"capture.p0-root\")"))

        let body = String(try section(
            in: root,
            from: "var body: some View",
            to: "@ViewBuilder\n    private var rootHero"
        ))
        let authority = try #require(body.range(of: "buildAuthorityStatus"))
        let account = try #require(body.range(of: "accountSetupPanel", range: authority.upperBound..<body.endIndex))
        let details = try #require(body.range(of: "engineeringDisclosure", range: account.upperBound..<body.endIndex))
        #expect(authority.lowerBound < account.lowerBound)
        #expect(account.lowerBound < details.lowerBound)
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

private extension String {
    func occurrenceCount(of needle: String) -> Int {
        var count = 0
        var searchStart = startIndex
        while searchStart < endIndex,
              let match = range(of: needle, range: searchStart..<endIndex) {
            count += 1
            searchStart = match.upperBound
        }
        return count
    }
}
