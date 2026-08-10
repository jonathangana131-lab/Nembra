#!/usr/bin/env python3
from pathlib import Path

ENTRYPOINT = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
PROJECT = Path("NembraCapture.xcodeproj/project.pbxproj")
ENTITLEMENTS = Path("NembraCapture.entitlements")
LOGIN_TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaAppleAccountLoginSourceTests.swift")
CUSTODY_TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaAppleOAuthCredentialCustodySourceTests.swift")
DOC = Path("docs/CAPTURE_P0_APPLE_ACCOUNT_LOGIN.md")


def replace_exact(path: Path, old: str, new: str, count: int = 1) -> None:
    text = path.read_text(encoding="utf-8")
    found = text.count(old)
    if found != count:
        raise SystemExit(f"{path}: expected {count} occurrence(s), found {found}: {old!r}")
    path.write_text(text.replace(old, new, count), encoding="utf-8")


replace_exact(
    ENTRYPOINT,
    "import CoreTransferable\n",
    "import AuthenticationServices\nimport CoreTransferable\n",
)

replace_exact(
    ENTRYPOINT,
    "@MainActor\nprivate final class OfficialTuyaAccountAuthorizer: ObservableObject {\n",
    '''private enum AppleAccountAuthorizationError: LocalizedError {
    case unexpectedCredential

    var errorDescription: String? {
        "Apple authorization returned an unexpected credential type."
    }
}

@MainActor
private final class OfficialTuyaAccountAuthorizer: ObservableObject {
''',
)

replace_exact(
    ENTRYPOINT,
    '''    func login() {
        guard OfficialTuyaFactory.bootstrap() else {
''',
    '''    func loginWithApple(credential: ASAuthorizationAppleIDCredential) {
        guard OfficialTuyaFactory.bootstrap() else {
            status = "Tuya SDK initialization failed closed."
            return
        }
        guard !loggedIn else { return }
        let country = countryCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !country.isEmpty else {
            status = "Enter the country code before using Sign in with Apple."
            return
        }
        guard let tokenData = credential.identityToken,
              let identityToken = String(data: tokenData, encoding: .utf8),
              !identityToken.isEmpty else {
            status = "Apple did not provide an identity token, so Tuya login remains locked."
            return
        }
#if canImport(ThingSmartHomeKit)
        let appleUserIdentifier = credential.user
        let appleEmail = credential.email
        var extraInfo: [String: Any] = ["userIdentifier": appleUserIdentifier]
        if let appleEmail, !appleEmail.isEmpty { extraInfo["email"] = appleEmail }
        busy = true
        codeSent = false
        verificationCode = ""
        status = "Completing Sign in with Apple through the official Tuya SDK…"
        ThingSmartUser.sharedInstance()?.loginByAuth2(
            withType: "ap",
            countryCode: country,
            accessToken: identityToken,
            extraInfo: extraInfo,
            success: { [weak self] in
                Task { @MainActor in self?.finishLoginSuccess() }
            },
            failure: { [weak self] error in
                Task { @MainActor in
                    self?.finishAppleLoginFailure(
                        error,
                        submittedIdentityToken: identityToken,
                        appleUserIdentifier: appleUserIdentifier,
                        appleEmail: appleEmail
                    )
                }
            }
        )
#else
        status = "Official Tuya SmartLife SDK is not compiled into this build."
#endif
    }

    func handleAppleAuthorizationFailure(_ error: Error) {
        _ = error
        busy = false
        loggedIn = OfficialTuyaFactory.accountLoggedIn
        status = "Sign in with Apple did not complete. Exact scooter membership remains locked."
    }

    func login() {
        guard OfficialTuyaFactory.bootstrap() else {
''',
)

replace_exact(
    ENTRYPOINT,
    '''    private func finishLoginFailure(_ error: Error?, submittedIdentity: String) {
        busy = false
        verificationCode = ""
        loggedIn = OfficialTuyaFactory.accountLoggedIn
        status = "Tuya SDK login failed: \(Self.redactedError(error, submittedIdentity: submittedIdentity))"
    }

    private static func redactedError(_ error: Error?, submittedIdentity: String) -> String {
''',
    '''    private func finishLoginFailure(_ error: Error?, submittedIdentity: String) {
        busy = false
        verificationCode = ""
        loggedIn = OfficialTuyaFactory.accountLoggedIn
        status = "Tuya SDK login failed: \(Self.redactedError(error, submittedIdentity: submittedIdentity))"
    }

    private func finishAppleLoginFailure(
        _ error: Error?,
        submittedIdentityToken: String,
        appleUserIdentifier: String,
        appleEmail: String?
    ) {
        busy = false
        loggedIn = OfficialTuyaFactory.accountLoggedIn
        status = "Tuya rejected the Apple-account login: \(Self.redactedAppleOAuthError(error, submittedIdentityToken: submittedIdentityToken, appleUserIdentifier: appleUserIdentifier, appleEmail: appleEmail)). Exact scooter membership remains locked."
    }

    private static func redactedAppleOAuthError(
        _ error: Error?,
        submittedIdentityToken: String,
        appleUserIdentifier: String,
        appleEmail: String?
    ) -> String {
        var scrubbed = error?.localizedDescription ?? "unknown error"
        let sensitiveValues = [submittedIdentityToken, appleUserIdentifier, appleEmail ?? ""]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        for value in sensitiveValues {
            scrubbed = scrubbed.replacingOccurrences(
                of: value,
                with: "<redacted-apple-oauth>",
                options: [.caseInsensitive, .literal]
            )
        }
        return scrubbed
    }

    private static func redactedError(_ error: Error?, submittedIdentity: String) -> String {
''',
)

replace_exact(
    ENTRYPOINT,
    '''                Text("Nembra uses Tuya's official verification-code login. Your password is never requested or stored.")
                    .foregroundStyle(.secondary)
                Text(sdkAccount.status)
''',
    '''                Text("Use the same account method that owns this scooter in Tuya. Apple ID uses Apple's system sign-in through Tuya's documented account transport; email/phone verification remains available. Nembra never requests your password.")
                    .foregroundStyle(.secondary)
                Text(sdkAccount.status)
''',
)

replace_exact(
    ENTRYPOINT,
    '''                Picker("Login method", selection: $sdkAccount.method) {
                    ForEach(OfficialTuyaAccountAuthorizer.LoginMethod.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

''',
    '''                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    Task { @MainActor in
                        switch result {
                        case let .success(authorization):
                            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                                sdkAccount.handleAppleAuthorizationFailure(AppleAccountAuthorizationError.unexpectedCredential)
                                return
                            }
                            sdkAccount.loginWithApple(credential: credential)
                        case let .failure(error):
                            sdkAccount.handleAppleAuthorizationFailure(error)
                        }
                    }
                }
                .signInWithAppleButtonStyle(.white)
                .frame(height: 50)
                .disabled(sdkAccount.busy)
                .accessibilityHint("Uses Apple's system authorization, then hands the transient identity token directly to Tuya for account login. Exact scooter membership is still verified separately.")

                HStack(spacing: 10) {
                    Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
                    Text("or use Tuya verification code")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
                }
                .accessibilityHidden(true)

                Picker("Login method", selection: $sdkAccount.method) {
                    ForEach(OfficialTuyaAccountAuthorizer.LoginMethod.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

''',
)

replace_exact(
    PROJECT,
    "\t\t\t\tCODE_SIGN_STYLE = Automatic;\n",
    "\t\t\t\tCODE_SIGN_ENTITLEMENTS = NembraCapture.entitlements;\n\t\t\t\tCODE_SIGN_STYLE = Automatic;\n",
    count=2,
)

ENTITLEMENTS.write_text('''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.developer.applesignin</key>
    <array>
        <string>Default</string>
    </array>
</dict>
</plist>
''', encoding="utf-8")

LOGIN_TEST.write_text(r'''import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture Apple-account login source boundary")
struct TuyaAppleAccountLoginSourceTests {
    @Test("Apple account transport uses system authorization and preserves exact scooter membership authority")
    func appleLoginPathIsPresentAndFailClosed() throws {
        let entrypoint = try read("NembraApp/App/NembraCaptureEntrypoint.swift")
        let project = try read("NembraCapture.xcodeproj/project.pbxproj")
        let entitlements = try read("NembraCapture.entitlements")

        #expect(entrypoint.contains("import AuthenticationServices"))
        #expect(entrypoint.contains("SignInWithAppleButton(.signIn)"))
        #expect(entrypoint.contains("credential.identityToken"))
        #expect(entrypoint.contains("loginByAuth2("))
        #expect(entrypoint.contains("withType: \"ap\""))
        #expect(entrypoint.contains("\"userIdentifier\": appleUserIdentifier"))
        #expect(entrypoint.contains("finishLoginSuccess()"))
        #expect(entrypoint.contains("loggedIn = OfficialTuyaFactory.accountLoggedIn"))
        #expect(entrypoint.contains("if loggedIn { test.verifySDKMembership() }"))
        #expect(entrypoint.contains("sdkDeviceMembershipVerified && test.accountIdentityLeaseIsAuthorized"))
        #expect(entrypoint.contains("email/phone verification remains available"))
        #expect(!entrypoint.contains("loggedIn = true"))
        #expect(!entrypoint.contains("print(identityToken"))
        #expect(!entrypoint.contains("UserDefaults.standard.set(identityToken"))

        #expect(project.components(separatedBy: "CODE_SIGN_ENTITLEMENTS = NembraCapture.entitlements;").count - 1 == 2)
        #expect(entitlements.contains("com.apple.developer.applesignin"))
        #expect(entitlements.contains("<string>Default</string>"))
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
}
''', encoding="utf-8")

CUSTODY_TEST.write_text(r'''import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture Apple OAuth credential custody source boundary")
struct TuyaAppleOAuthCredentialCustodySourceTests {
    @Test("Apple OAuth error presentation scrubs every submitted credential-shaped value")
    func oauthCredentialMaterialCannotReachPresentation() throws {
        let source = try read("NembraApp/App/NembraCaptureEntrypoint.swift")

        #expect(source.contains("redactedAppleOAuthError"))
        #expect(source.contains("submittedIdentityToken:"))
        #expect(source.contains("appleUserIdentifier:"))
        #expect(source.contains("appleEmail:"))
        #expect(source.contains("<redacted-apple-oauth>"))
        #expect(!source.contains("Tuya rejected the Apple-account login: \\(error?.localizedDescription"))
        #expect(!source.contains("log(\"apple_identity_token"))
        #expect(!source.contains("UserDefaults.standard.set(identityToken"))
        #expect(source.contains("loggedIn = OfficialTuyaFactory.accountLoggedIn"))
        #expect(source.contains("if loggedIn { test.verifySDKMembership() }"))
        #expect(source.contains("accountIdentityLeaseIsAuthorized"))
        #expect(source.contains("sdkDeviceMembershipVerified"))
        #expect(!source.contains("loggedIn = true"))
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
}
''', encoding="utf-8")

DOC.write_text('''# Capture P0 — Apple-account Tuya login

STATUS: SOFTWARE PATH REQUIRED / PRIVATE PLATFORM CONFIGURATION + PHYSICAL MEMBERSHIP STILL UNPROVEN

The intended scooter account uses Apple-backed Smart Life sign-in, so Capture must not assume email/phone verification can enter the same Tuya account.

Nembra field contract:
- Apple authorization is owned by AuthenticationServices / Sign in with Apple.
- The transient Apple identity token stays in memory and is handed directly to Tuya's official `loginByAuth2` Apple (`ap`) account transport.
- Any Tuya OAuth failure string is scrubbed against the exact submitted identity token, Apple user identifier and optional email before presentation.
- The identity token is never persisted, exported, logged, or converted into Capture evidence.
- OAuth success is account transport only. Capture re-reads the official SDK login state and still requires fresh exact scooter membership plus the current-account UID lease before Bluetooth discovery.
- Email/phone verification remains an alternate account path.
- Private Tuya third-party-login configuration and signed Apple capability provisioning remain field prerequisites and are not proven by public source.

Official Tuya iOS documentation: https://developer.tuya.com/en/docs/app-development/iOS-user-thirdparty?id=Kaixu9bbogqxi

PHYSICAL STATUS: NO-GO until the final composed exact build passes software, private provisioning, runtime, membership, and stationary field gates.
''', encoding="utf-8")

entry = ENTRYPOINT.read_text(encoding="utf-8")
for needle in [
    "SignInWithAppleButton(.signIn)",
    "credential.identityToken",
    "loginByAuth2(",
    'withType: "ap"',
    "redactedAppleOAuthError",
    "submittedIdentityToken:",
    "Exact scooter membership remains locked.",
    "test.verifySDKMembership()",
]:
    if needle not in entry:
        raise SystemExit(f"missing transformed marker: {needle}")
if "Tuya rejected the Apple-account login: \\(error?.localizedDescription" in entry:
    raise SystemExit("raw Tuya Apple OAuth error reached presentation")
if PROJECT.read_text(encoding="utf-8").count("CODE_SIGN_ENTITLEMENTS = NembraCapture.entitlements;") != 2:
    raise SystemExit("expected Sign in with Apple entitlement binding in Debug and Release")
