import Foundation
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
