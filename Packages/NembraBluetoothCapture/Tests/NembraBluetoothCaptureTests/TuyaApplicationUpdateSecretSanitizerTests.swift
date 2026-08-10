import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya application update secret sanitizer")
struct TuyaApplicationUpdateSecretSanitizerTests {
    @Test("top-level export-promised secret keys are redacted after normalization")
    func redactsTopLevelCredentialKeys() {
        let update: [AnyHashable: Any] = [
            "local_key": "local-secret",
            "session-key": "session-secret",
            "app_key": "app-key-secret",
            "appSecret": "app-secret",
            "password": "password-secret",
            "account_token": "account-token-secret",
            "ACCESS-TOKEN": "access-secret",
            "refresh.token": "refresh-secret",
            "authKey": "auth-secret",
            "sec_key": "sec-secret",
            "speed": 17,
        ]

        let sanitized = TuyaApplicationUpdateSecretSanitizer.sanitize(update)

        #expect(sanitized["local_key"] == "<redacted>")
        #expect(sanitized["session-key"] == "<redacted>")
        #expect(sanitized["app_key"] == "<redacted>")
        #expect(sanitized["appSecret"] == "<redacted>")
        #expect(sanitized["password"] == "<redacted>")
        #expect(sanitized["account_token"] == "<redacted>")
        #expect(sanitized["ACCESS-TOKEN"] == "<redacted>")
        #expect(sanitized["refresh.token"] == "<redacted>")
        #expect(sanitized["authKey"] == "<redacted>")
        #expect(sanitized["sec_key"] == "<redacted>")
        #expect(sanitized["speed"] == "17")
    }

    @Test("nested dictionaries and arrays are redacted before string projection")
    func redactsNestedCredentialKeys() throws {
        let update: [AnyHashable: Any] = [
            "payload": [
                "battery": 73,
                "nested": [
                    ["local-key": "nested-secret", "value": 1],
                    ["wrapper": ["refresh_token": "refresh-secret"]],
                    ["security": ["session_key": "session-secret"]],
                    ["credentials": ["appSecret": "app-secret", "password": "password-secret"]],
                    ["account": ["account-token": "account-token-secret"]],
                ],
            ] as [String: Any],
        ]

        let sanitized = TuyaApplicationUpdateSecretSanitizer.sanitize(update)
        let payload = try #require(sanitized["payload"])

        #expect(payload.contains("<redacted>"))
        #expect(!payload.contains("nested-secret"))
        #expect(!payload.contains("refresh-secret"))
        #expect(!payload.contains("session-secret"))
        #expect(!payload.contains("app-secret"))
        #expect(!payload.contains("password-secret"))
        #expect(!payload.contains("account-token-secret"))
        #expect(payload.contains("73"))
    }

    @Test("credential-looking values under ordinary keys are preserved")
    func doesNotRedactByValueContent() {
        let update: [AnyHashable: Any] = [
            "note": "literal local_key and appSecret text is evidence, not a credential key",
            "battery": 73,
        ]

        let sanitized = TuyaApplicationUpdateSecretSanitizer.sanitize(update)

        #expect(sanitized["note"] == "literal local_key and appSecret text is evidence, not a credential key")
        #expect(sanitized["battery"] == "73")
    }

    @Test("redaction preserves a non-empty application update")
    func preservesNonEmptyUpdateWhenEveryValueIsSecretShaped() {
        let update: [AnyHashable: Any] = [
            "localKey": "one",
            "session_key": "two",
            "app-key": "three",
            "app_secret": "four",
            "password": "five",
            "accountToken": "six",
        ]

        let sanitized = TuyaApplicationUpdateSecretSanitizer.sanitize(update)

        #expect(sanitized.count == 6)
        #expect(sanitized.values.allSatisfy { $0 == "<redacted>" })
    }

    @Test("empty application update stays empty")
    func preservesEmptyUpdate() {
        #expect(TuyaApplicationUpdateSecretSanitizer.sanitize([:]).isEmpty)
    }
}
