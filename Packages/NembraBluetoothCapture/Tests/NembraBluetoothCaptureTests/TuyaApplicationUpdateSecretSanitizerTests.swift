import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya application update secret sanitizer")
struct TuyaApplicationUpdateSecretSanitizerTests {
    @Test("classifier covers every credential class promised absent from Capture export")
    func exportPromiseCredentialClassesAreSecret() {
        let spellings = [
            "local_key",
            "session-key",
            "app.key",
            "appSecret",
            "password",
            "account_token",
            "accessToken",
            "refresh-token",
            "auth_key",
            "secKey",
        ]

        for spelling in spellings {
            #expect(TuyaApplicationUpdateSecretSanitizer.isSecretKey(spelling))
        }
    }

    @Test("normalization is punctuation and case insensitive")
    func normalizationIsStable() {
        #expect(TuyaApplicationUpdateSecretSanitizer.normalizedKey("Session_Key") == "sessionkey")
        #expect(TuyaApplicationUpdateSecretSanitizer.normalizedKey("APP-SECRET") == "appsecret")
        #expect(TuyaApplicationUpdateSecretSanitizer.normalizedKey("Account.Token") == "accounttoken")
    }

    @Test("nested dictionaries and arrays redact before projection")
    func recursiveStructuredRedaction() throws {
        let input: [AnyHashable: Any] = [
            "outer": [
                "session_key": "session-value",
                "battery": 73,
            ],
            "items": [
                ["appSecret": "app-secret-value"],
                ["watts": 120],
            ],
        ]

        let sanitized = TuyaApplicationUpdateSecretSanitizer.sanitize(input)
        let root = try #require(sanitized as? [String: Any])
        let outer = try #require(root["outer"] as? [String: Any])
        let items = try #require(root["items"] as? [Any])
        let firstItem = try #require(items.first as? [String: Any])
        let secondItem = try #require(items.last as? [String: Any])

        #expect(outer["session_key"] as? String == TuyaApplicationUpdateSecretSanitizer.redactedValue)
        #expect(outer["battery"] as? Int == 73)
        #expect(firstItem["appSecret"] as? String == TuyaApplicationUpdateSecretSanitizer.redactedValue)
        #expect(secondItem["watts"] as? Int == 120)
    }

    @Test("string projection redacts top-level secrets and preserves ordinary evidence")
    func projectionBoundary() {
        let projected = TuyaApplicationUpdateSecretSanitizer.sanitizeForStringProjection([
            "password": "do-not-export",
            "1": true,
            "nested": ["account_token": "token", "mode": "eco"],
        ])

        #expect(projected["password"] == TuyaApplicationUpdateSecretSanitizer.redactedValue)
        #expect(projected["1"] == "true")
        #expect(projected["nested"]?.contains("token") == false)
        #expect(projected["nested"]?.contains("<redacted>") == true)
        #expect(projected["nested"]?.contains("eco") == true)
    }

    @Test("ordinary key names do not gain credential meaning")
    func ordinaryEvidenceStaysVisible() {
        for key in ["battery", "speed", "mode", "deviceID", "timestamp"] {
            #expect(!TuyaApplicationUpdateSecretSanitizer.isSecretKey(key))
        }
    }
}
