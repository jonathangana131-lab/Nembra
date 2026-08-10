import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya authenticated application event custody")
struct TuyaAuthenticatedApplicationEventCustodyTests {
    @Test("trusted generation wins while colliding SDK generation remains application evidence")
    func trustedGenerationCannotBeForgedByApplicationPayload() {
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
        let uid = "account-uid-123"
        let details = TuyaAuthenticatedApplicationEventCustody.eventDetails(
            applicationUpdate: [
                "owner.\(uid)": "same=\(uid)",
                "uid": "device-uid-456",
            ],
            trustedGeneration: "8",
            accountUID: "  \(uid)  "
        )

        #expect(details["owner.<redacted-account-uid>"] == "same=<redacted-account-uid>")
        #expect(details["uid"] == "device-uid-456")
        #expect(details["generation"] == "8")
        #expect(!details.keys.contains(where: { $0.contains(uid) }))
        #expect(!details.values.contains(where: { $0.contains(uid) }))
    }

    @Test("reserved namespace collisions preserve all SDK fields deterministically")
    func reservedNamespaceCollisionDoesNotDiscardEvidence() {
        let update = [
            "generation": "raw-generation",
            "application.generation": "raw-application-generation",
            "application.application.generation": "raw-double-application-generation",
        ]

        let details = TuyaAuthenticatedApplicationEventCustody.eventDetails(
            applicationUpdate: update,
            trustedGeneration: "9",
            accountUID: nil
        )

        #expect(details["generation"] == "9")
        #expect(details["application.generation"] == "raw-application-generation")
        #expect(details["application.application.generation"] == "raw-double-application-generation")
        #expect(details["application.application.application.generation"] == "raw-generation")
        #expect(details.count == update.count + 1)
    }

    @Test("missing account UID leaves unrelated application evidence unchanged")
    func missingAccountUIDIsNoOpForApplicationValues() {
        let details = TuyaAuthenticatedApplicationEventCustody.eventDetails(
            applicationUpdate: [
                "uid": "device-uid",
                "payload": "raw application evidence",
            ],
            trustedGeneration: "10",
            accountUID: "   "
        )

        #expect(details["uid"] == "device-uid")
        #expect(details["payload"] == "raw application evidence")
        #expect(details["generation"] == "10")
    }
}
