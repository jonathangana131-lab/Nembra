import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture Apple OAuth documented extraInfo")
struct TuyaAppleOAuthDocumentedExtraInfoSourceTests {
    @Test("Apple Auth2 forwards documented optional nickname fields without weakening membership authority")
    func appleAuth2PreservesDocumentedExtraInfo() throws {
        let entrypoint = try read("NembraApp/App/NembraCaptureEntrypoint.swift")
        let login = try section(
            in: entrypoint,
            from: "func loginWithApple(credential: ASAuthorizationAppleIDCredential)",
            to: "func handleAppleAuthorizationFailure"
        )
        let body = String(login)

        #expect(body.contains("let appleUserIdentifier = credential.user"))
        #expect(body.contains("let appleEmail = credential.email"))
        #expect(body.contains("let appleNickname = credential.fullName?.nickname"))
        #expect(body.contains("\"userIdentifier\": appleUserIdentifier"))
        #expect(body.contains("extraInfo[\"email\"] = appleEmail"))
        #expect(body.contains("extraInfo[\"nickname\"] = appleNickname"))
        #expect(body.contains("extraInfo[\"snsNickname\"] = appleNickname"))
        #expect(body.contains("withType: \"ap\""))
        #expect(body.contains("accessToken: identityToken"))
        #expect(body.contains("finishLoginSuccess()"))
        #expect(entrypoint.contains("loggedIn = OfficialTuyaFactory.accountLoggedIn"))
        #expect(entrypoint.contains("if loggedIn { test.verifySDKMembership() }"))
        #expect(entrypoint.contains("sdkDeviceMembershipVerified && test.accountIdentityLeaseIsAuthorized"))
        #expect(!body.contains("loggedIn = true"))
        #expect(body.contains("finishAppleLoginFailure(error)"))
        #expect(!body.contains("submittedIdentityToken:"))
        #expect(!entrypoint.contains("redactedAppleOAuthError"))
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let startRange = source.range(of: start),
              let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \(start) ... \(end)")
            throw SourceContractError.sectionMissing
        }
        return source[startRange.lowerBound..<endRange.lowerBound]
    }

    private func read(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private enum SourceContractError: Error { case sectionMissing }
}
