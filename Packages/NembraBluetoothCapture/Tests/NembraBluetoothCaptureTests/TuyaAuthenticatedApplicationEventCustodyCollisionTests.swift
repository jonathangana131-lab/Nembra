import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya authenticated application event custody collisions")
struct TuyaAuthenticatedApplicationEventCustodyCollisionTests {
    @Test("trusted generation cannot destroy colliding SDK application evidence")
    func generationCollisionPreservesBothAuthorities() {
        let details = TuyaAuthenticatedApplicationEventCustody.eventDetails(
            applicationUpdate: [
                "generation": "sdk-generation",
                "application.generation": "sdk-namespaced-generation",
            ],
            trustedGeneration: "42",
            accountUID: nil
        )

        #expect(details["generation"] == "42")
        #expect(details.values.contains("sdk-generation"))
        #expect(details.values.contains("sdk-namespaced-generation"))
        #expect(details.count == 3)
    }

    @Test("UID redaction key collisions preserve every SDK field deterministically")
    func uidRedactionCollisionDoesNotOverwriteEvidence() {
        let uid = "account-uid-123"
        let update = [
            "owner.\(uid)": "first",
            "owner.<redacted-account-uid>": "second",
        ]

        let first = TuyaAuthenticatedApplicationEventCustody.eventDetails(
            applicationUpdate: update,
            trustedGeneration: "43",
            accountUID: uid
        )
        let second = TuyaAuthenticatedApplicationEventCustody.eventDetails(
            applicationUpdate: update,
            trustedGeneration: "43",
            accountUID: uid
        )

        #expect(first == second)
        #expect(first["generation"] == "43")
        #expect(first.values.contains("first"))
        #expect(first.values.contains("second"))
        #expect(first.count == update.count + 1)
        #expect(!first.keys.contains(where: { $0.contains(uid) }))
    }

    @Test("nested reserved-name collisions do not discard application evidence")
    func reservedNamespaceCollisionPreservesAllValues() {
        let update = [
            "generation": "raw-0",
            "application.generation": "raw-1",
            "application.application.generation": "raw-2",
        ]
        let details = TuyaAuthenticatedApplicationEventCustody.eventDetails(
            applicationUpdate: update,
            trustedGeneration: "44",
            accountUID: nil
        )

        #expect(details["generation"] == "44")
        #expect(details.values.contains("raw-0"))
        #expect(details.values.contains("raw-1"))
        #expect(details.values.contains("raw-2"))
        #expect(details.count == update.count + 1)
    }
}
