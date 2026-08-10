import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya authenticated application event custody")
struct TuyaApplicationEventCustodyTests {
    @Test("verified account UID is removed from application keys and values")
    func accountUIDCannotEnterEventCustody() throws {
        let uid = "acct-UID-42"
        let details = try #require(TuyaApplicationEventCustody.admittedDetails(
            applicationUpdate: [
                "owner": "prefix-\(uid)-suffix",
                "malformed-\(uid)-key": "opaque",
                "uid": "device-opaque-identifier"
            ],
            verifiedAccountUID: uid,
            connectionGeneration: "7"
        ))

        #expect(details["owner"] == "prefix-<redacted-account-uid>-suffix")
        #expect(details["malformed-<redacted-account-uid>-key"] == "opaque")
        #expect(details["uid"] == "device-opaque-identifier")
        #expect(details["generation"] == "7")
        #expect(details.keys.allSatisfy { !$0.contains(uid) })
        #expect(details.values.allSatisfy { !$0.contains(uid) })
    }

    @Test("Nembra generation wins while colliding application evidence is preserved")
    func trustedGenerationCannotBeForged() throws {
        let details = try #require(TuyaApplicationEventCustody.admittedDetails(
            applicationUpdate: [
                "generation": "sdk-forged-generation",
                "application.generation": "sdk-existing-namespaced-value",
                "payload": "opaque"
            ],
            verifiedAccountUID: "account-123",
            connectionGeneration: "19"
        ))

        #expect(details["generation"] == "19")
        #expect(details["payload"] == "opaque")
        #expect(details["application.generation"] == "sdk-existing-namespaced-value")
        #expect(details["application.generation#2"] == "sdk-forged-generation")
    }

    @Test("generation spelling that only differs by case or outer whitespace is non-authoritative")
    func normalizedGenerationSpellingsAreNamespaced() throws {
        let details = try #require(TuyaApplicationEventCustody.admittedDetails(
            applicationUpdate: ["  GeNeRaTiOn  ": "untrusted"],
            verifiedAccountUID: "account-123",
            connectionGeneration: "21"
        ))

        #expect(details["generation"] == "21")
        #expect(details["application.generation"] == "untrusted")
        #expect(details["  GeNeRaTiOn  "] == nil)
    }

    @Test("every exact account UID occurrence is scrubbed without case-insensitive guessing")
    func exactIdentityRedactionIsLiteral() throws {
        let uid = "AbC-123"
        let details = try #require(TuyaApplicationEventCustody.admittedDetails(
            applicationUpdate: ["echo": "\(uid)/\(uid)/abc-123"],
            verifiedAccountUID: uid,
            connectionGeneration: "1"
        ))

        #expect(details["echo"] == "<redacted-account-uid>/<redacted-account-uid>/abc-123")
    }

    @Test("custody refuses empty updates, missing verified identity, or missing generation")
    func incompleteAuthorityFailsClosed() {
        #expect(TuyaApplicationEventCustody.admittedDetails(
            applicationUpdate: [:],
            verifiedAccountUID: "account-123",
            connectionGeneration: "1"
        ) == nil)
        #expect(TuyaApplicationEventCustody.admittedDetails(
            applicationUpdate: ["payload": "opaque"],
            verifiedAccountUID: "   ",
            connectionGeneration: "1"
        ) == nil)
        #expect(TuyaApplicationEventCustody.admittedDetails(
            applicationUpdate: ["payload": "opaque"],
            verifiedAccountUID: "account-123",
            connectionGeneration: "   "
        ) == nil)
    }
}
