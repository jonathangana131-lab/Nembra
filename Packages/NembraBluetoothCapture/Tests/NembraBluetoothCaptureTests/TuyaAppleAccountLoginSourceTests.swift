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
