import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture Apple-account login source boundary")
struct TuyaAppleAccountLoginSourceTests {
    @Test("Apple account transport uses system authorization and preserves exact scooter membership authority")
    func appleLoginPathIsPresentAndFailClosed() throws {
        let entrypoint = try read("NembraApp/App/NembraCaptureEntrypoint.swift")
        let project = try read("NembraCapture.xcodeproj/project.pbxproj")
        let entitlements = try read("NembraCapture.entitlements")
        let runbook = try read("docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md")

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

        #expect(runbook.contains("For this Apple-backed Smart Life account, use **Sign in with Apple**."))
        #expect(runbook.contains("Apple third-party-login capability configured"))
        #expect(runbook.contains("a different Tuya account must never be substituted"))
        #expect(!runbook.contains("has an authorized verification-code account session"))
        #expect(!runbook.contains("log in to the official Tuya SDK account by verification code if needed"))
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