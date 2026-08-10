import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya application update secret sanitizer")
struct TuyaApplicationUpdateSecretSanitizerTests {
    @Test("top-level credential-shaped keys are redacted after normalization")
    func redactsTopLevelCredentialKeys() {
        let update: [AnyHashable: Any] = [
            "local_key": "local-secret",
            "ACCESS-TOKEN": "access-secret",
            "refresh.token": "refresh-secret",
            "authKey": "auth-secret",
            "sec_key": "session-secret",
            "speed": 17,
        ]

        let sanitized = TuyaApplicationUpdateSecretSanitizer.sanitize(update)

        #expect(sanitized["local_key"] == "<redacted>")
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
                ],
            ] as [String: Any],
        ]

        let sanitized = TuyaApplicationUpdateSecretSanitizer.sanitize(update)
        let payload = try #require(sanitized["payload"])

        #expect(payload.contains("<redacted>"))
        #expect(!payload.contains("nested-secret"))
        #expect(!payload.contains("refresh-secret"))
        #expect(payload.contains("73"))
    }

    @Test("credential-looking values under ordinary keys are preserved")
    func doesNotRedactByValueContent() {
        let update: [AnyHashable: Any] = [
            "note": "literal local_key text is evidence, not a credential key",
            "battery": 73,
        ]

        let sanitized = TuyaApplicationUpdateSecretSanitizer.sanitize(update)

        #expect(sanitized["note"] == "literal local_key text is evidence, not a credential key")
        #expect(sanitized["battery"] == "73")
    }

    @Test("redaction preserves a non-empty application update")
    func preservesNonEmptyUpdateWhenEveryValueIsSecretShaped() {
        let update: [AnyHashable: Any] = [
            "localKey": "one",
            "access_token": "two",
        ]

        let sanitized = TuyaApplicationUpdateSecretSanitizer.sanitize(update)

        #expect(sanitized.count == 2)
        #expect(sanitized.values.allSatisfy { $0 == "<redacted>" })
    }

    @Test("empty application update stays empty")
    func preservesEmptyUpdate() {
        #expect(TuyaApplicationUpdateSecretSanitizer.sanitize([:]).isEmpty)
    }
}
