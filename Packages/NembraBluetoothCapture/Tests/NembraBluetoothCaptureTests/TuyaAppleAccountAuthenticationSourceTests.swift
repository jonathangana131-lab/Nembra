import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture Apple-backed Tuya account authority")
struct TuyaAppleAccountAuthenticationSourceTests {
    @Test("scooter-owning Apple account has a supported Tuya OAuth path")
    func appleAccountUsesOfficialTuyaOAuth() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let authorizer = try section(
            in: app,
            from: "private final class OfficialTuyaAccountAuthorizer",
            to: "private struct SecureLinkView"
        )
        let body = String(authorizer)

        #expect(app.contains("import AuthenticationServices"), Comment(rawValue: "The field account is Apple-backed; Capture needs Apple's supported authorization framework instead of assuming email/phone OTP reaches the same Tuya UID."))
        #expect(body.contains("ASAuthorizationAppleIDCredential"))
        #expect(body.contains("identityToken"))
        #expect(body.contains("loginByAuth2"))
        #expect(body.contains("withType: \"ap\""), Comment(rawValue: "Tuya documents OAuth type `ap` for Sign in with Apple."))
        #expect(body.contains("finishLoginSuccess()"), Comment(rawValue: "Apple/Tuya success must re-enter the existing SDK-session authority path rather than minting a parallel logged-in flag."))
    }

    @Test("native Apple login remains upstream of exact scooter membership")
    func appleLoginDoesNotBypassMembershipAuthority() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let secureLink = try section(
            in: app,
            from: "private struct SecureLinkView",
            to: "private extension View"
        )
        let body = String(secureLink)

        #expect(body.contains("SignInWithAppleButton"), Comment(rawValue: "The normal Capture account surface must expose the native Apple login path used by the scooter-owning Tuya account."))
        #expect(body.contains(".onChange(of: sdkAccount.loggedIn)"))
        #expect(body.contains("if loggedIn { test.verifySDKMembership() }"), Comment(rawValue: "Apple login establishes only the Tuya SDK account session; fresh exact-device membership remains mandatory before Capture authority."))
        #expect(body.contains("test.sdkDeviceMembershipVerified"))
        #expect(body.contains("test.accountIdentityLeaseIsAuthorized"))
    }

    @Test("credential material stays below Capture evidence")
    func appleCredentialMaterialIsNotExportAuthority() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let export = try section(
            in: app,
            from: "private func makeExport(",
            to: "func prepareExport()"
        )
        let body = String(export)

        #expect(body.contains("secretsRedacted: true"))
        #expect(!body.contains("identityToken"))
        #expect(!body.contains("authorizationCode"))
        #expect(!body.contains("appleIDCredential"))
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
