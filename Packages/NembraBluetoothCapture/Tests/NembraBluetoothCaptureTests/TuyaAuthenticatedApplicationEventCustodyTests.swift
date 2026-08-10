import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya authenticated application event custody")
struct TuyaAuthenticatedApplicationEventCustodyTests {
    @Test("trusted generation wins while colliding SDK generation remains application evidence")
    func trustedGenerationCannotDestroyApplicationEvidence() {
        let details = TuyaAuthenticatedApplicationEventCustody.eventDetails(
            applicationUpdate: [
                "generation": "sdk-forged-generation",
                "speed": "42",
            ],
            trustedGeneration: "7",
            accountUID: nil
        )

        #expect(details["generation"] == "7")
        #expect(details["application.generation"] == "sdk-forged-generation")
        #expect(details["speed"] == "42")
        #expect(details.count == 3)
    }

    @Test("exact leased account UID is redacted from application keys and values")
    func accountUIDDoesNotCrossEventCustody() {
        let uid = "Account-UID-123"
        let details = TuyaAuthenticatedApplicationEventCustody.eventDetails(
            applicationUpdate: [
                "owner.account-uid-123": "same=ACCOUNT-UID-123",
                "uid": "device-uid-456",
            ],
            trustedGeneration: "8",
            accountUID: "  \(uid)  "
        )

        #expect(details["owner.<redacted-account-uid>"] == "same=<redacted-account-uid>")
        #expect(details["uid"] == "device-uid-456")
        #expect(details["generation"] == "8")
    }

    @Test("reserved namespace collisions preserve every SDK value deterministically")
    func reservedNamespaceCollisionDoesNotDiscardEvidence() {
        let update = [
            "generation": "raw-generation",
            "application.generation": "raw-application-generation",
            "application.application.generation": "raw-double-application-generation",
        ]

        let first = TuyaAuthenticatedApplicationEventCustody.eventDetails(
            applicationUpdate: update,
            trustedGeneration: "9",
            accountUID: nil
        )
        let second = TuyaAuthenticatedApplicationEventCustody.eventDetails(
            applicationUpdate: update,
            trustedGeneration: "9",
            accountUID: nil
        )

        #expect(first == second)
        #expect(first["generation"] == "9")
        #expect(first.values.contains("raw-generation"))
        #expect(first.values.contains("raw-application-generation"))
        #expect(first.values.contains("raw-double-application-generation"))
        #expect(first.count == update.count + 1)
    }

    @Test("UID redaction key collisions preserve every SDK field")
    func uidRedactionCollisionDoesNotOverwriteEvidence() {
        let uid = "account-uid-123"
        let update = [
            "owner.\(uid)": "first",
            "owner.<redacted-account-uid>": "second",
        ]

        let details = TuyaAuthenticatedApplicationEventCustody.eventDetails(
            applicationUpdate: update,
            trustedGeneration: "10",
            accountUID: uid
        )

        #expect(details["generation"] == "10")
        #expect(details.values.contains("first"))
        #expect(details.values.contains("second"))
        #expect(details.count == update.count + 1)
        #expect(!details.keys.contains(where: { $0.localizedCaseInsensitiveContains(uid) }))
    }
}
