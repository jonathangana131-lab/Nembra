import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture Apple OAuth credential custody source boundary")
struct TuyaAppleOAuthCredentialCustodySourceTests {
    @Test("Apple account entry must scrub OAuth credential material and still require SDK membership truth")
    func appleOAuthCredentialMaterialCannotReachPresentationOrAuthority() throws {
        let source = try read("NembraApp/App/NembraCaptureEntrypoint.swift")

        // The current product intentionally starts red until the Apple-account owner lands the
        // documented Tuya OAuth path. This contract belongs with that product repair, not alone.
        #expect(source.contains("import AuthenticationServices"))
        #expect(source.contains("SignInWithAppleButton(.signIn)"))
        #expect(source.contains("credential.identityToken"))
        #expect(source.contains("loginByAuth2("))
        #expect(source.contains("withType: \"ap\""))

        // Apple/Tuya credential-shaped values are transient transport inputs, never Capture
        // evidence or user-facing error material. The product repair needs one explicit scrubber
        // that receives every value submitted to Tuya's Apple OAuth call before displaying any
        // SDK failure description.
        #expect(source.contains("redactedAppleOAuthError"))
        #expect(source.contains("submittedIdentityToken:"))
        #expect(source.contains("appleUserIdentifier:"))
        #expect(source.contains("appleEmail:"))
        #expect(!source.contains("Tuya rejected the Apple-account login: \\(error?.localizedDescription"))
        #expect(!source.contains("log(\"apple_identity_token"))
        #expect(!source.contains("UserDefaults.standard.set(identityToken"))

        // A successful third-party callback is account transport only. Existing official-SDK
        // session + exact-device membership/UID lease gates must remain the authority boundary.
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
