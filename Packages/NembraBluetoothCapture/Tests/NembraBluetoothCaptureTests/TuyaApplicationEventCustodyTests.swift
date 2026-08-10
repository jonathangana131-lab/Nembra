import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya application event custody")
struct TuyaApplicationEventCustodyTests {
    private let accountUID = "acct-7F94A2"

    @Test("exact leased account UID is scrubbed from values and malformed keys without generic uid erasure")
    func accountUIDCannotEnterEitherDictionaryDimension() throws {
        let details = try #require(TuyaApplicationEventCustody.acceptedEventDetails(
            applicationUpdate: [
                "owner": "before-acct-7F94A2-after",
                "key-acct-7F94A2-tail": "present",
                "uid": "opaque-device-uid",
            ],
            leasedAccountUID: accountUID,
            trustedGeneration: "42"
        ))

        #expect(details["owner"] == "before-<redacted-account-uid>-after")
        #expect(details["key-<redacted-account-uid>-tail"] == "present")
        #expect(details["uid"] == "opaque-device-uid")
        #expect(details["generation"] == "42")
        #expect(details.keys.allSatisfy { !$0.contains(accountUID) })
        #expect(details.values.allSatisfy { !$0.contains(accountUID) })
    }

    @Test("untrusted generation key is preserved but cannot replace trusted provenance")
    func applicationGenerationCannotForgeNembraGeneration() throws {
        let details = try #require(TuyaApplicationEventCustody.acceptedEventDetails(
            applicationUpdate: [
                "generation": "forged-999",
                "application.generation": "opaque-existing-field",
                "7": "opaque-dp-value",
            ],
            leasedAccountUID: accountUID,
            trustedGeneration: "73"
        ))

        #expect(details["generation"] == "73")
        #expect(details["application.generation"] == "opaque-existing-field")
        #expect(details["application.generation#2"] == "forged-999")
        #expect(details["7"] == "opaque-dp-value")
    }

    @Test("key collisions caused by UID redaction preserve both opaque application fields deterministically")
    func redactedKeyCollisionDoesNotSilentlyDropEvidence() throws {
        let details = try #require(TuyaApplicationEventCustody.acceptedEventDetails(
            applicationUpdate: [
                "field-acct-7F94A2": "first",
                "field-<redacted-account-uid>": "second",
            ],
            leasedAccountUID: accountUID,
            trustedGeneration: "9"
        ))

        let preservedValues = Set(details.filter { $0.key.hasPrefix("field-<redacted-account-uid>") }.map(\.value))
        #expect(preservedValues == Set(["first", "second"]))
        #expect(details.keys.filter { $0.hasPrefix("field-<redacted-account-uid>") }.count == 2)
        #expect(details["generation"] == "9")
    }

    @Test("custody fails closed without exact account and generation authority")
    func missingAuthorityCannotProduceAcceptedDetails() {
        #expect(TuyaApplicationEventCustody.acceptedEventDetails(
            applicationUpdate: ["7": "value"],
            leasedAccountUID: "   ",
            trustedGeneration: "1"
        ) == nil)
        #expect(TuyaApplicationEventCustody.acceptedEventDetails(
            applicationUpdate: ["7": "value"],
            leasedAccountUID: accountUID,
            trustedGeneration: "  "
        ) == nil)
    }

    @Test("ambiguous trusted generation containing exact account identity fails closed")
    func generationCannotReintroduceAccountIdentity() {
        #expect(TuyaApplicationEventCustody.acceptedEventDetails(
            applicationUpdate: ["7": "value"],
            leasedAccountUID: accountUID,
            trustedGeneration: "generation-\(accountUID)-1"
        ) == nil)
    }
}
