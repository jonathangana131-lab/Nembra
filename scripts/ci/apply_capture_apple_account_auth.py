#!/usr/bin/env python3
from pathlib import Path

ENTRYPOINT = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
PROJECT = Path("NembraCapture.xcodeproj/project.pbxproj")
ENTITLEMENTS = Path("NembraCapture.entitlements")
TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaAppleAccountLoginSourceTests.swift")
DOC = Path("docs/CAPTURE_P0_APPLE_ACCOUNT_LOGIN.md")


def replace_exact(path: Path, old: str, new: str, count: int = 1) -> None:
    text = path.read_text()
    found = text.count(old)
    if found != count:
        raise SystemExit(f"{path}: expected {count} occurrences, found {found}: {old!r}")
    path.write_text(text.replace(old, new, count))


# Apple authorization is a system-owned credential flow. The identity token is handed directly
# to Tuya's documented third-party OAuth login API and is never persisted or logged by Capture.
replace_exact(
    ENTRYPOINT,
    "import CoreTransferable\n",
    "import AuthenticationServices\nimport CoreTransferable\n",
)

replace_exact(
    ENTRYPOINT,
    '''    func login() {\n        guard OfficialTuyaFactory.bootstrap() else {\n''',
    '''    func loginWithApple(credential: ASAuthorizationAppleIDCredential) {\n        guard OfficialTuyaFactory.bootstrap() else {\n            status = "Tuya SDK initialization failed closed."\n            return\n        }\n        guard !loggedIn else { return }\n        let country = countryCode.trimmingCharacters(in: .whitespacesAndNewlines)\n        guard !country.isEmpty else {\n            status = "Enter the country code before using Sign in with Apple."\n            return\n        }\n        guard let tokenData = credential.identityToken,\n              let identityToken = String(data: tokenData, encoding: .utf8),\n              !identityToken.isEmpty else {\n            status = "Apple did not provide an identity token, so Tuya login remains locked."\n            return\n        }\n#if canImport(ThingSmartHomeKit)\n        var extraInfo: [String: Any] = ["userIdentifier": credential.user]\n        if let email = credential.email, !email.isEmpty { extraInfo["email"] = email }\n        if let nickname = credential.fullName?.nickname, !nickname.isEmpty {\n            extraInfo["nickname"] = nickname\n            extraInfo["snsNickname"] = nickname\n        }\n        busy = true\n        codeSent = false\n        verificationCode = ""\n        status = "Completing Sign in with Apple through the official Tuya SDK…"\n        ThingSmartUser.sharedInstance()?.loginByAuth2(\n            withType: "ap",\n            countryCode: country,\n            accessToken: identityToken,\n            extraInfo: extraInfo,\n            success: { [weak self] in\n                Task { @MainActor in self?.finishLoginSuccess() }\n            },\n            failure: { [weak self] error in\n                Task { @MainActor in self?.finishAppleLoginFailure(error) }\n            }\n        )\n#else\n        status = "Official Tuya SmartLife SDK is not compiled into this build."\n#endif\n    }\n\n    func handleAppleAuthorizationFailure(_ error: Error) {\n        busy = false\n        loggedIn = OfficialTuyaFactory.accountLoggedIn\n        status = "Sign in with Apple did not complete: \\(error.localizedDescription)"\n    }\n\n    func login() {\n        guard OfficialTuyaFactory.bootstrap() else {\n''',
)

replace_exact(
    ENTRYPOINT,
    '''    private func finishLoginFailure(_ error: Error?, submittedIdentity: String) {\n        busy = false\n        verificationCode = ""\n        loggedIn = OfficialTuyaFactory.accountLoggedIn\n        status = "Tuya SDK login failed: \\(Self.redactedError(error, submittedIdentity: submittedIdentity))"\n    }\n\n''',
    '''    private func finishLoginFailure(_ error: Error?, submittedIdentity: String) {\n        busy = false\n        verificationCode = ""\n        loggedIn = OfficialTuyaFactory.accountLoggedIn\n        status = "Tuya SDK login failed: \\(Self.redactedError(error, submittedIdentity: submittedIdentity))"\n    }\n\n    private func finishAppleLoginFailure(_ error: Error?) {\n        busy = false\n        loggedIn = OfficialTuyaFactory.accountLoggedIn\n        status = "Tuya rejected the Apple-account login: \\(error?.localizedDescription ?? \"unknown error\"). Exact scooter membership remains locked."\n    }\n\n''',
)

replace_exact(
    ENTRYPOINT,
    '''                Text("Nembra uses Tuya's official verification-code login. Your password is never requested or stored.")\n                    .foregroundStyle(.secondary)\n                Text(sdkAccount.status)\n''',
    '''                Text("Use the same account method that owns this scooter in Tuya. Apple ID is supported through Apple's system sign-in and Tuya's documented third-party login; email/phone verification remains available. Nembra never requests your password.")\n                    .foregroundStyle(.secondary)\n                Text(sdkAccount.status)\n''',
)

replace_exact(
    ENTRYPOINT,
    '''                Picker("Login method", selection: $sdkAccount.method) {\n                    ForEach(OfficialTuyaAccountAuthorizer.LoginMethod.allCases) { Text($0.rawValue).tag($0) }\n                }\n                .pickerStyle(.segmented)\n\n''',
    '''                SignInWithAppleButton(.signIn) { request in\n                    request.requestedScopes = [.fullName, .email]\n                } onCompletion: { result in\n                    Task { @MainActor in\n                        switch result {\n                        case let .success(authorization):\n                            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {\n                                sdkAccount.handleAppleAuthorizationFailure(AppleAccountAuthorizationError.unexpectedCredential)\n                                return\n                            }\n                            sdkAccount.loginWithApple(credential: credential)\n                        case let .failure(error):\n                            sdkAccount.handleAppleAuthorizationFailure(error)\n                        }\n                    }\n                }\n                .signInWithAppleButtonStyle(.white)\n                .frame(height: 50)\n                .disabled(sdkAccount.busy)\n                .accessibilityHint("Uses Apple's system authorization, then passes the short-lived identity token directly to Tuya for account login.")\n\n                HStack(spacing: 10) {\n                    Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)\n                    Text("or use Tuya verification code")\n                        .font(.caption)\n                        .foregroundStyle(.secondary)\n                    Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)\n                }\n\n                Picker("Login method", selection: $sdkAccount.method) {\n                    ForEach(OfficialTuyaAccountAuthorizer.LoginMethod.allCases) { Text($0.rawValue).tag($0) }\n                }\n                .pickerStyle(.segmented)\n\n''',
)

# Add a tiny local error without creating a credential-bearing data type.
replace_exact(
    ENTRYPOINT,
    '''@MainActor\nprivate final class OfficialTuyaAccountAuthorizer: ObservableObject {\n''',
    '''private enum AppleAccountAuthorizationError: LocalizedError {\n    case unexpectedCredential\n\n    var errorDescription: String? {\n        "Apple authorization returned an unexpected credential type."\n    }\n}\n\n@MainActor\nprivate final class OfficialTuyaAccountAuthorizer: ObservableObject {\n''',
)

# Device signing must request the Apple capability. Public CODE_SIGNING_ALLOWED=NO builds still
# compile this file, while a real field install will fail signing if the provisioning profile is not enabled.
replace_exact(
    PROJECT,
    "\t\t\t\tCODE_SIGN_STYLE = Automatic;\n",
    "\t\t\t\tCODE_SIGN_ENTITLEMENTS = NembraCapture.entitlements;\n\t\t\t\tCODE_SIGN_STYLE = Automatic;\n",
    count=2,
)

ENTITLEMENTS.write_text('''<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0">\n<dict>\n    <key>com.apple.developer.applesignin</key>\n    <array>\n        <string>Default</string>\n    </array>\n</dict>\n</plist>\n''')

TEST.write_text('''import Foundation\nimport Testing\n@testable import NembraBluetoothCapture\n\n@Suite("Capture Apple-account login source boundary")\nstruct TuyaAppleAccountLoginSourceTests {\n    @Test("guided Capture supports system Apple authorization through Tuya OAuth without weakening membership authority")\n    func appleLoginPathIsPresentAndFailClosed() throws {\n        let entrypoint = try read("NembraApp/App/NembraCaptureEntrypoint.swift")\n        let project = try read("NembraCapture.xcodeproj/project.pbxproj")\n        let entitlements = try read("NembraCapture.entitlements")\n\n        #expect(entrypoint.contains("import AuthenticationServices"))\n        #expect(entrypoint.contains("SignInWithAppleButton(.signIn)"))\n        #expect(entrypoint.contains("credential.identityToken"))\n        #expect(entrypoint.contains("loginByAuth2("))\n        #expect(entrypoint.contains("withType: \"ap\""))\n        #expect(entrypoint.contains("\"userIdentifier\": credential.user"))\n        #expect(entrypoint.contains("Exact scooter membership remains locked."))\n        #expect(entrypoint.contains("test.verifySDKMembership()"))\n        #expect(entrypoint.contains("sdkDeviceMembershipVerified && test.accountIdentityLeaseIsAuthorized"))\n        #expect(entrypoint.contains("email/phone verification remains available"))\n        #expect(!entrypoint.contains("print(identityToken"))\n        #expect(!entrypoint.contains("log(\"apple_identity_token"))\n\n        #expect(project.components(separatedBy: "CODE_SIGN_ENTITLEMENTS = NembraCapture.entitlements;").count - 1 == 2)\n        #expect(entitlements.contains("com.apple.developer.applesignin"))\n        #expect(entitlements.contains("<string>Default</string>"))\n    }\n\n    private func read(_ path: String) throws -> String {\n        let root = URL(fileURLWithPath: #filePath)\n            .deletingLastPathComponent()\n            .deletingLastPathComponent()\n            .deletingLastPathComponent()\n            .deletingLastPathComponent()\n            .deletingLastPathComponent()\n        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)\n    }\n}\n''')

DOC.write_text('''# Capture P0 — Apple-account Tuya login\n\nSTATUS: SOFTWARE PATH REQUIRED / PRIVATE PLATFORM CONFIGURATION + PHYSICAL MEMBERSHIP STILL UNPROVEN\n\nThe real scooter account is expected to require the same Apple-account sign-in method used by the stock Tuya-family app. Capture therefore must not assume that an email/phone verification-code login can recover that account.\n\nTuya's official SmartLife App SDK documentation defines third-party OAuth login and explicitly assigns type `ap` to Apple accounts. The iOS flow supplies the Apple identity token plus the Apple user identifier and optional profile fields to Tuya. Tuya also requires third-party login support to be configured for the app in the Tuya Developer Platform.\n\nOfficial source: https://developer.tuya.com/en/docs/app-development/iOS-user-thirdparty?id=Kaixu9bbogqxi\n\nNembra field contract:\n- Apple authorization is owned by AuthenticationServices / Sign in with Apple.\n- The short-lived Apple identity token stays in memory and is passed directly to the official Tuya SDK login API; it is not persisted, exported, logged, or turned into Capture evidence.\n- Email/phone verification-code login remains an alternate account path.\n- A Tuya login-success callback does not identify the scooter. Capture still re-reads the official SDK login state and must freshly prove exact scooter membership before Bluetooth discovery.\n- If Apple authorization, Tuya third-party login configuration, signed Apple capability provisioning, current SDK login state, or exact device membership is unavailable, physical Capture remains fail-closed.\n- Successful Apple login is account transport only. It is not Bluetooth, protocol, telemetry, command, or physical scooter proof.\n\nPrivate deployment prerequisites that cannot be proven by public source alone:\n1. Enable Sign in with Apple for the exact signed Nembra Capture App ID / provisioning profile.\n2. Configure Apple third-party login support for the exact Tuya Developer Platform app identity used by the private SmartLife SDK build.\n3. Build/install the exact accepted source on the intended iPhone 12 / iOS 27.\n4. Complete Apple authorization and require `ThingSmartUser` to report the current logged-in session.\n5. Require the existing exact-device membership gate to find the expected scooter before any Bluetooth discovery.\n\nPHYSICAL STATUS: NO-GO until the final composed exact build passes all software, private provisioning, runtime, membership, and stationary field gates.\n''')

# Mechanical post-transform guard.
for path, needles in {
    ENTRYPOINT: [
        "SignInWithAppleButton(.signIn)",
        "loginByAuth2(",
        'withType: "ap"',
        "credential.identityToken",
        "Exact scooter membership remains locked.",
    ],
    PROJECT: ["CODE_SIGN_ENTITLEMENTS = NembraCapture.entitlements;"],
    ENTITLEMENTS: ["com.apple.developer.applesignin"],
    TEST: ["TuyaAppleAccountLoginSourceTests"],
    DOC: ["Apple-account Tuya login"],
}.items():
    text = path.read_text()
    for needle in needles:
        if needle not in text:
            raise SystemExit(f"{path}: missing expected marker {needle!r}")

if PROJECT.read_text().count("CODE_SIGN_ENTITLEMENTS = NembraCapture.entitlements;") != 2:
    raise SystemExit("expected Sign in with Apple entitlement binding in Debug and Release")
