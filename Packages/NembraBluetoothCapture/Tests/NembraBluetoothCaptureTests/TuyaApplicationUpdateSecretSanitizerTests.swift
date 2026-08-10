import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya application update secret sanitizer")
struct TuyaApplicationUpdateSecretSanitizerTests {
    @Test("credential-shaped top-level keys redact their values")
    func topLevelCredentialKeysAreRedacted() {
        let input: [AnyHashable: Any] = [
            "local_key": "local-secret",
            "ACCESS-TOKEN": "access-secret",
            "refresh.token": "refresh-secret",
            "authKey": "auth-secret",
            "sec_key": "session-secret",
            "speed": 17,
        ]

        let output = TuyaApplicationUpdateSecretSanitizer.sanitize(input)

        #expect(output["local_key"] == "<redacted>")
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
            "refresh_token": "two",
        ]

        let output = TuyaApplicationUpdateSecretSanitizer.sanitize(input)

        #expect(output.count == 2)
        #expect(output.values.allSatisfy { $0 == TuyaApplicationUpdateSecretSanitizer.redactedValue })
    }
}
