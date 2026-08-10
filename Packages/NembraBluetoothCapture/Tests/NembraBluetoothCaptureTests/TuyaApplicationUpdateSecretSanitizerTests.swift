import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya application update secret sanitizer")
struct TuyaApplicationUpdateSecretSanitizerTests {
    @Test("credential-shaped top-level keys match the accepted export secret promise")
    func topLevelCredentialKeysAreRedacted() {
        let input: [AnyHashable: Any] = [
            "local_key": "local-secret",
            "session-key": "session-secret",
            "App-Key": "app-key-secret",
            "appSecret": "app-secret",
            "password": "password-secret",
            "account_token": "account-token-secret",
            "ACCESS-TOKEN": "access-secret",
            "refresh.token": "refresh-secret",
            "authKey": "auth-secret",
            "sec_key": "security-secret",
            "speed": 17,
        ]

        let output = TuyaApplicationUpdateSecretSanitizer.sanitize(input)

        #expect(output["local_key"] == "<redacted>")
        #expect(output["session-key"] == "<redacted>")
        #expect(output["App-Key"] == "<redacted>")
        #expect(output["appSecret"] == "<redacted>")
        #expect(output["password"] == "<redacted>")
        #expect(output["account_token"] == "<redacted>")
        #expect(output["ACCESS-TOKEN"] == "<redacted>")
        #expect(output["refresh.token"] == "<redacted>")
        #expect(output["authKey"] == "<redacted>")
        #expect(output["sec_key"] == "<redacted>")
        #expect(output["speed"] == "17")
        #expect(output.count == input.count)
    }

    @Test("nested dictionaries and arrays redact before string projection")
    func nestedSecretsNeverReachProjectedStrings() {
        let nestedSecret = "NESTED-SECRET-SENTINEL"
        let input: [AnyHashable: Any] = [
            "payload": [
                "ordinary": "kept-value",
                "nested": [
                    "access_token": nestedSecret,
                    "items": [
                        ["localKey": nestedSecret],
                        ["session_key": nestedSecret],
                        ["app_secret": nestedSecret],
                        ["plain": "still-kept"],
                    ],
                ],
            ] as [String: Any],
        ]

        let output = TuyaApplicationUpdateSecretSanitizer.sanitize(input)
        let projected = output["payload"] ?? ""

        #expect(projected.contains("<redacted>"))
        #expect(!projected.contains(nestedSecret))
        #expect(projected.contains("kept-value"))
        #expect(projected.contains("still-kept"))
    }

    @Test("ordinary application values are preserved without semantic decoding")
    func ordinaryValuesRemainOpaqueApplicationEvidence() {
        let input: [AnyHashable: Any] = [
            1: true,
            "2": 42,
            "mode": "sport",
        ]

        let output = TuyaApplicationUpdateSecretSanitizer.sanitize(input)

        #expect(output["1"] == "true")
        #expect(output["2"] == "42")
        #expect(output["mode"] == "sport")
    }

    @Test("an all-secret update remains a non-empty sanitized receipt")
    func allSecretUpdatePreservesReceiptStructure() {
        let input: [AnyHashable: Any] = [
            "localKey": "one",
            "session_key": "two",
            "appSecret": "three",
            "password": "four",
            "account-token": "five",
        ]

        let output = TuyaApplicationUpdateSecretSanitizer.sanitize(input)

        #expect(output.count == input.count)
        #expect(output.values.allSatisfy { $0 == TuyaApplicationUpdateSecretSanitizer.redactedValue })
    }
}
