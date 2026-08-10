from pathlib import Path

APP = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
PBX = Path("NembraCapture.xcodeproj/project.pbxproj")
TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaAppleAccountAuthenticationSourceTests.swift")

app = APP.read_text(encoding="utf-8")

old_import = "import CoreTransferable\nimport Foundation\n"
new_import = "import AuthenticationServices\nimport CoreTransferable\nimport Foundation\n"
assert app.count(old_import) == 1, "import anchor changed"
app = app.replace(old_import, new_import, 1)

old_status = '            : "SDK initialized. Sign in with a verification code; metadata QR approval does not count as SDK device authority."\n'
new_status = '            : "SDK initialized. Continue with Apple or use a Tuya verification code; exact scooter membership is still required."\n'
assert app.count(old_status) == 1, "bootstrap copy anchor changed"
app = app.replace(old_status, new_status, 1)

send_code_anchor = "    func sendCode() {\n"
assert app.count(send_code_anchor) == 1, "sendCode anchor changed"
apple_method = '''    func loginWithApple(_ result: Result<ASAuthorization, Error>) {
        bootstrap()
        guard !loggedIn else { return }
        let country = countryCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !country.isEmpty else {
            status = "Enter the Tuya country code before continuing with Apple."
            return
        }

        switch result {
        case .failure:
            busy = false
            status = "Sign in with Apple did not complete. No Apple credential material was retained."
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let identityToken = credential.identityToken,
                  let accessToken = String(data: identityToken, encoding: .utf8),
                  !accessToken.isEmpty else {
                busy = false
                status = "Apple did not provide a usable identity token. Tuya login remains locked."
                return
            }
#if canImport(ThingSmartHomeKit)
            guard let user = ThingSmartUser.sharedInstance() else {
                busy = false
                status = "The official Tuya user session is unavailable. Bluetooth remains disabled."
                return
            }
            var extraInfo: [String: Any] = ["userIdentifier": credential.user]
            if let email = credential.email, !email.isEmpty {
                extraInfo["email"] = email
            }
            if let nickname = credential.fullName?.nickname?.trimmingCharacters(in: .whitespacesAndNewlines), !nickname.isEmpty {
                extraInfo["nickname"] = nickname
                extraInfo["snsNickname"] = nickname
            }

            busy = true
            codeSent = false
            verificationCode = ""
            status = "Signing in to the official Tuya SDK with Apple…"
            user.loginByAuth2(
                withType: "ap",
                countryCode: country,
                accessToken: accessToken,
                extraInfo: extraInfo,
                success: { [weak self] in
                    Task { @MainActor in self?.finishLoginSuccess() }
                },
                failure: { [weak self] _ in
                    Task { @MainActor in self?.finishAppleLoginFailure() }
                }
            )
#else
            busy = false
            status = "Official Tuya SmartLife SDK is not compiled into this build."
#endif
        }
    }

'''
app = app.replace(send_code_anchor, apple_method + send_code_anchor, 1)

failure_anchor = "    private func finishLoginFailure(_ error: Error?, submittedIdentity: String) {\n"
assert app.count(failure_anchor) == 1, "login failure anchor changed"
apple_failure = '''    private func finishAppleLoginFailure() {
        busy = false
        verificationCode = ""
        loggedIn = OfficialTuyaFactory.accountLoggedIn
        status = "Tuya could not complete Sign in with Apple. No Apple credential material was retained."
    }

'''
app = app.replace(failure_anchor, apple_failure + failure_anchor, 1)

old_copy = '                Text("Nembra uses Tuya\'s official verification-code login. Your password is never requested or stored.")\n'
new_copy = '                Text("Use the same Tuya sign-in method that owns this scooter. Apple credentials stay in the system authorization flow; Nembra never stores them in Capture evidence.")\n'
assert app.count(old_copy) == 1, "account copy anchor changed"
app = app.replace(old_copy, new_copy, 1)

country_block = '''                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("+")
                        .foregroundStyle(.secondary)
                    TextField("Country code", text: $sdkAccount.countryCode)
                        .keyboardType(.numberPad)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .inputSurface()

'''
assert app.count(country_block) == 1, "country-code UI anchor changed"
apple_ui = '''                SignInWithAppleButton(.continue) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    sdkAccount.loginWithApple(result)
                }
                .signInWithAppleButtonStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 50)
                .disabled(sdkAccount.busy)
                .accessibilityHint("Signs in to the official Tuya SDK using your Apple account, then Nembra freshly verifies this exact scooter in that account before Bluetooth can start.")

                HStack(spacing: 10) {
                    Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
                    Text("OR USE TUYA CODE")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                    Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
                }

'''
app = app.replace(country_block, country_block + apple_ui, 1)
APP.write_text(app, encoding="utf-8")

pbx = PBX.read_text(encoding="utf-8")
sign_anchor = "\t\t\t\tCODE_SIGN_STYLE = Automatic;\n"
assert pbx.count(sign_anchor) == 2, "expected exactly two target signing anchors"
pbx = pbx.replace(sign_anchor, "\t\t\t\tCODE_SIGN_ENTITLEMENTS = NembraApp/App/NembraCapture.entitlements;\n" + sign_anchor)
PBX.write_text(pbx, encoding="utf-8")

TEST.write_text(r'''import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture Apple-backed Tuya account authority")
struct TuyaAppleAccountAuthenticationSourceTests {
    @Test("scooter-owning Apple account has a supported Tuya OAuth path")
    func appleAccountUsesOfficialTuyaOAuth() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let authorizer = try section(in: app, from: "private final class OfficialTuyaAccountAuthorizer", to: "private struct SecureLinkView")
        let body = String(authorizer)
        #expect(app.contains("import AuthenticationServices"))
        #expect(body.contains("ASAuthorizationAppleIDCredential"))
        #expect(body.contains("identityToken"))
        #expect(body.contains("loginByAuth2"))
        #expect(body.contains("withType: \"ap\""))
        #expect(body.contains("finishLoginSuccess()"))
    }

    @Test("native Apple login remains upstream of exact scooter membership")
    func appleLoginDoesNotBypassMembershipAuthority() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let secureLink = try section(in: app, from: "private struct SecureLinkView", to: "private extension View")
        let body = String(secureLink)
        #expect(body.contains("SignInWithAppleButton"))
        #expect(body.contains(".onChange(of: sdkAccount.loggedIn)"))
        #expect(body.contains("if loggedIn { test.verifySDKMembership() }"))
        #expect(body.contains("test.sdkDeviceMembershipVerified"))
        #expect(body.contains("test.accountIdentityLeaseIsAuthorized"))
    }

    @Test("credential material stays below Capture evidence")
    func appleCredentialMaterialIsNotExportAuthority() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let export = try section(in: app, from: "private func makeExport(", to: "func prepareExport()")
        let body = String(export)
        #expect(body.contains("secretsRedacted: true"))
        #expect(!body.contains("identityToken"))
        #expect(!body.contains("authorizationCode"))
        #expect(!body.contains("appleIDCredential"))
    }

    @Test("field target carries Sign in with Apple entitlement")
    func targetDeclaresAppleEntitlement() throws {
        let pbx = try readRepositoryFile("NembraCapture.xcodeproj/project.pbxproj")
        let entitlements = try readRepositoryFile("NembraApp/App/NembraCapture.entitlements")
        #expect(pbx.contains("CODE_SIGN_ENTITLEMENTS = NembraApp/App/NembraCapture.entitlements;"))
        #expect(entitlements.contains("com.apple.developer.applesignin"))
        #expect(entitlements.contains("<string>Default</string>"))
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let startRange = source.range(of: start), let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
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
''', encoding="utf-8")

app = APP.read_text(encoding="utf-8")
pbx = PBX.read_text(encoding="utf-8")
ents = Path("NembraApp/App/NembraCapture.entitlements").read_text(encoding="utf-8")
for token in (
    "import AuthenticationServices",
    "ASAuthorizationAppleIDCredential",
    "loginByAuth2(",
    'withType: "ap"',
    "SignInWithAppleButton(.continue)",
    "if loggedIn { test.verifySDKMembership() }",
):
    assert token in app, f"missing contract token: {token}"
assert app.count("SignInWithAppleButton(.continue)") == 1
assert pbx.count("CODE_SIGN_ENTITLEMENTS = NembraApp/App/NembraCapture.entitlements;") == 2
assert "com.apple.developer.applesignin" in ents
export = app.split("private func makeExport(", 1)[1].split("func prepareExport()", 1)[0]
for forbidden in ("identityToken", "authorizationCode", "appleIDCredential"):
    assert forbidden not in export, f"credential material leaked into export source: {forbidden}"
