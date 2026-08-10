import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya application update secret sanitizer")
struct TuyaApplicationUpdateSecretSanitizerTests {
    @Test("every export-promised credential class redacts after key normalization")
    func exportPromisedCredentialKeysAreRedacted() {
        let sentinels: [(String, String)] = [
            ("local_key", "LOCAL-SECRET"),
            ("session-key", "SESSION-SECRET"),
            ("appKey", "APPKEY-SECRET"),
            ("APP.SECRET", "APPSECRET-SECRET"),
            ("password", "PASSWORD-SECRET"),
            ("account_token", "ACCOUNT-SECRET"),
            ("ACCESS-TOKEN", "ACCESS-SECRET"),
            ("refresh.token", "REFRESH-SECRET"),
            ("authKey", "AUTH-SECRET"),
            ("sec_key", "SEC-SECRET"),
        ]
        var input: [AnyHashable: Any] = ["speed": 17]
        for (key, value) in sentinels { input[key] = value }

        let output = TuyaApplicationUpdateSecretSanitizer.sanitize(input)

        for (key, secret) in sentinels {
            #expect(output[key] == TuyaApplicationUpdateSecretSanitizer.redactedValue)
            #expect(!output.values.contains(where: { $0.contains(secret) }))
        }
        #expect(output["speed"] == "17")
        #expect(output.count == input.count)
    }

    @Test("nested dictionaries and arrays redact before string projection")
    func nestedSecretsNeverReachProjectedStrings() {
        let nestedSecrets = [
            "SESSION-NESTED",
            "APPSECRET-NESTED",
            "PASSWORD-NESTED",
            "ACCOUNT-NESTED",
            "LOCAL-NESTED",
        ]
        let input: [AnyHashable: Any] = [
            "payload": [
                "ordinary": "kept-value",
                "nested": [
                    "session_key": nestedSecrets[0],
                    "items": [
                        ["app-secret": nestedSecrets[1]],
                        ["password": nestedSecrets[2]],
                        ["accountToken": nestedSecrets[3]],
                        ["localKey": nestedSecrets[4]],
                        ["plain": "still-kept"],
                    ],
                ],
            ] as [String: Any],
        ]

        let output = TuyaApplicationUpdateSecretSanitizer.sanitize(input)
        let projected = output["payload"] ?? ""

        #expect(projected.contains(TuyaApplicationUpdateSecretSanitizer.redactedValue))
        for secret in nestedSecrets { #expect(!projected.contains(secret)) }
        #expect(projected.contains("kept-value"))
        #expect(projected.contains("still-kept"))
    }

    @Test("ordinary application values remain opaque and are not semantically decoded")
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
            "account_token": "four",
        ]

        let output = TuyaApplicationUpdateSecretSanitizer.sanitize(input)

        #expect(output.count == input.count)
        #expect(output.values.allSatisfy { $0 == TuyaApplicationUpdateSecretSanitizer.redactedValue })
    }
}
