from pathlib import Path

app_path = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
app = app_path.read_text()

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
    raise SystemExit(f"expected exactly one Apple OAuth failure callback, found {app.count(old_failure)}")
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

test_path = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaAppleOAuthCredentialCustodySourceTests.swift")
test_path.write_text('''import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture Apple OAuth credential custody source boundary")
struct TuyaAppleOAuthCredentialCustodySourceTests {
    @Test("Apple OAuth failure presentation never consumes credential-shaped values or raw SDK error text")
    func oauthCredentialMaterialCannotReachPresentation() throws {
        let source = try read("NembraApp/App/NembraCaptureEntrypoint.swift")

        #expect(source.contains("finishAppleLoginFailure(error)"))
        #expect(source.contains("let code = (error as NSError?)?.code ?? -1"))
        #expect(source.contains("Tuya rejected the Apple-account login (code \\(code))"))
        #expect(!source.contains("submittedIdentityToken:"))
        #expect(!source.contains("redactedAppleOAuthError"))
        #expect(!source.contains("<redacted-apple-oauth>"))
        #expect(!source.contains("Tuya rejected the Apple-account login: \\(error?.localizedDescription"))
        #expect(!source.contains("log(\\\"apple_identity_token"))
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
''')
