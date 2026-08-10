import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture Apple OAuth credential custody source boundary")
struct TuyaAppleOAuthCredentialCustodySourceTests {
    @Test("Apple OAuth failure presentation never consumes credential-shaped values or raw SDK error text")
    func oauthCredentialMaterialCannotReachPresentation() throws {
        let source = try read("NembraApp/App/NembraCaptureEntrypoint.swift")
        let login = try section(
            in: source,
            from: "func loginWithApple(credential: ASAuthorizationAppleIDCredential)",
            to: "func handleAppleAuthorizationFailure"
        )
        let failure = try section(
            in: source,
            from: "private func finishAppleLoginFailure(_ error: Error?)",
            to: "private static func redactedError("
        )
        let failureBody = String(failure)

        #expect(login.contains("finishAppleLoginFailure(error)"))
        #expect(!login.contains("submittedIdentityToken:"))
        #expect(!login.contains("appleUserIdentifier: appleUserIdentifier"))
        #expect(!login.contains("appleEmail: appleEmail"))
        #expect(!login.contains("appleNickname: appleNickname"))
        #expect(failureBody.contains("let code = (error as NSError?)?.code ?? -1"))
        #expect(failureBody.contains("Tuya rejected the Apple-account login (code \\(code))"))
        #expect(!source.contains("redactedAppleOAuthError"))
        #expect(!source.contains("<redacted-apple-oauth>"))
        #expect(!failureBody.contains("localizedDescription"))
        #expect(!source.contains("UserDefaults.standard.set(identityToken"))
        #expect(!source.contains("print(identityToken"))
        #expect(source.contains("loggedIn = OfficialTuyaFactory.accountLoggedIn"))
        #expect(source.contains("if loggedIn { test.verifySDKMembership() }"))
        #expect(source.contains("accountIdentityLeaseIsAuthorized"))
        #expect(source.contains("sdkDeviceMembershipVerified"))
        #expect(!source.contains("loggedIn = true"))
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let startRange = source.range(of: start),
              let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \(start) ... \(end)")
            throw SourceContractError.sectionMissing
        }
        return source[startRange.lowerBound..<endRange.lowerBound]
    }

    private func read(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    private enum SourceContractError: Error { case sectionMissing }
}
