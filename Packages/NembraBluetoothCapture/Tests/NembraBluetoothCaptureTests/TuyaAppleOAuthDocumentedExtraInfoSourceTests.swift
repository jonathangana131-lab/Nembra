import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture Apple OAuth documented extraInfo")
struct TuyaAppleOAuthDocumentedExtraInfoSourceTests {
    @Test("Apple Auth2 forwards Tuya's documented optional nickname fields without weakening membership authority")
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

        // OAuth transport is not scooter authority. Success must still flow through the
        // existing SDK-session re-read and exact current-account scooter membership gates.
        #expect(entrypoint.contains("loggedIn = OfficialTuyaFactory.accountLoggedIn"))
        #expect(entrypoint.contains("if loggedIn { test.verifySDKMembership() }"))
        #expect(entrypoint.contains("sdkDeviceMembershipVerified && test.accountIdentityLeaseIsAuthorized"))
        #expect(!body.contains("loggedIn = true"))
    }

    @Test("nickname handed to Tuya is covered by the same transient-error redaction boundary")
    func appleNicknameIsRedactedFromOAuthFailureText() throws {
        let entrypoint = try read("NembraApp/App/NembraCaptureEntrypoint.swift")
        let redaction = try section(
            in: entrypoint,
            from: "private static func redactedAppleOAuthError(",
            to: "private static func redactedError("
        )
        let body = String(redaction)

        #expect(body.contains("appleNickname: String?"))
        #expect(body.contains("appleNickname ?? \"\""))
        #expect(body.contains("<redacted-apple-oauth>"))
        #expect(!entrypoint.contains("UserDefaults.standard.set(identityToken"))
        #expect(!entrypoint.contains("print(identityToken"))
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
