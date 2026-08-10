from pathlib import Path

app_path = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
app = app_path.read_text()

old_extra = '''        let appleUserIdentifier = credential.user
        let appleEmail = credential.email
        var extraInfo: [String: Any] = ["userIdentifier": appleUserIdentifier]
        if let appleEmail, !appleEmail.isEmpty { extraInfo["email"] = appleEmail }
'''
new_extra = '''        let appleUserIdentifier = credential.user
        let appleEmail = credential.email
        let appleNickname = credential.fullName?.nickname
        var extraInfo: [String: Any] = ["userIdentifier": appleUserIdentifier]
        if let appleEmail, !appleEmail.isEmpty { extraInfo["email"] = appleEmail }
        if let appleNickname, !appleNickname.isEmpty {
            extraInfo["nickname"] = appleNickname
            extraInfo["snsNickname"] = appleNickname
        }
'''
if app.count(old_extra) != 1:
    raise SystemExit(f"expected one Apple extraInfo block, found {app.count(old_extra)}")
app = app.replace(old_extra, new_extra, 1)

old_failure = '''            failure: { [weak self] error in
                Task { @MainActor in
                    self?.finishAppleLoginFailure(
                        error,
                        submittedIdentityToken: identityToken,
                        appleUserIdentifier: appleUserIdentifier,
                        appleEmail: appleEmail
                    )
                }
            }
'''
new_failure = '''            failure: { [weak self] error in
                Task { @MainActor in self?.finishAppleLoginFailure(error) }
            }
'''
if app.count(old_failure) != 1:
    raise SystemExit(f"expected one Apple failure callback, found {app.count(old_failure)}")
app = app.replace(old_failure, new_failure, 1)

start = app.index("    private func finishAppleLoginFailure(")
end = app.index("    private static func redactedError(", start)
new_block = '''    private func finishAppleLoginFailure(_ error: Error?) {
        busy = false
        loggedIn = OfficialTuyaFactory.accountLoggedIn
        let code = (error as NSError?)?.code ?? -1
        status = "Tuya rejected the Apple-account login (code \\(code)). Exact scooter membership remains locked."
    }

'''
app = app[:start] + new_block + app[end:]
app_path.write_text(app)

custody = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaAppleOAuthCredentialCustodySourceTests.swift")
custody.write_text(r'''import Foundation
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
''')

extra = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaAppleOAuthDocumentedExtraInfoSourceTests.swift")
extra.write_text(r'''import Foundation
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
''')
