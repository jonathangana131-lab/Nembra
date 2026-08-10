import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya application update secret sanitizer")
struct TuyaApplicationUpdateSecretSanitizerTests {
    @Test("classifier covers every credential class promised absent from Capture export")
    func exportPromiseCredentialClassesAreSecret() {
        for spelling in [
            "local_key", "session-key", "app.key", "appSecret", "password",
            "account_token", "accessToken", "refresh-token", "auth_key", "secKey",
        ] {
            #expect(TuyaApplicationUpdateSecretSanitizer.isSecretKey(spelling))
        }
    }

    @Test("nested credential values redact before string projection")
    func nestedProjectionRedacts() {
        let projected = TuyaApplicationUpdateSecretSanitizer.sanitizeForStringProjection([
            "password": "do-not-export",
            "ordinary": "evidence",
            "nested": ["session_key": "session-value", "watts": 120],
        ])

        #expect(projected["password"] == "<redacted>")
        #expect(projected["ordinary"] == "evidence")
        #expect(projected["nested"]?.contains("session-value") == false)
        #expect(projected["nested"]?.contains("<redacted>") == true)
    }

    @Test("verified account UID redaction is exact-value-bound and preserves generic UID evidence")
    func accountUIDCustodyIsValueBound() {
        let verifiedUID = "account-uid-7A91"
        let redacted = TuyaApplicationUpdateSecretSanitizer.redactingAccountUID(
            in: [
                "uid": "device-uid-123",
                "status": "owner=account-uid-7A91; mode=eco",
                "account": "account-uid-7A91",
                "field-account-uid-7A91": "present",
            ],
            verifiedAccountUID: verifiedUID
        )

        #expect(redacted["uid"] == "device-uid-123")
        #expect(redacted["status"] == "owner=<redacted-account-uid>; mode=eco")
        #expect(redacted["account"] == "<redacted-account-uid>")
        #expect(redacted["field-<redacted-account-uid>"] == "present")
        #expect(redacted.values.allSatisfy { !$0.contains(verifiedUID) })
        #expect(redacted.keys.allSatisfy { !$0.contains(verifiedUID) })
        #expect(!TuyaApplicationUpdateSecretSanitizer.isSecretKey("uid"))
    }

    @Test("empty exact sensitive value is a no-op")
    func emptyExactValueDoesNotMatchEverywhere() {
        let projected = ["uid": "device-uid", "mode": "eco"]
        #expect(
            TuyaApplicationUpdateSecretSanitizer.redactingAccountUID(
                in: projected,
                verifiedAccountUID: ""
            ) == projected
        )
    }
}
