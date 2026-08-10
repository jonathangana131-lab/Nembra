import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya authenticated read-only evidence ledger")
struct TuyaAuthenticatedReadOnlyEvidenceLedgerTests {
    @Test("wrong generation and wrong characteristic fail closed")
    func authorityFences() async throws {
        let ledger = try TuyaAuthenticatedReadOnlyEvidenceLedger(
            connectionGeneration: 7,
            connectionStartedAtUptimeNanoseconds: 1,
            authenticatedAtUptimeNanoseconds: 10,
            authMethod: .documentedDeviceSharing
        )

        await #expect(throws: TuyaAuthenticatedReadOnlyEvidenceLedger.AdmissionError.generationMismatch) {
            try await ledger.admitApplicationNotification(
                connectionGeneration: 6,
                monotonicNanoseconds: 11,
                characteristicUUID: TuyaFD50AuthenticatedReadOnlyTarget.notificationCharacteristicUUID,
                payload: Data([0x01])
            )
        }
        await #expect(throws: TuyaAuthenticatedReadOnlyEvidenceLedger.AdmissionError.unexpectedCharacteristic) {
            try await ledger.admitApplicationNotification(
                connectionGeneration: 7,
                monotonicNanoseconds: 11,
                characteristicUUID: "00000001-0000-1001-8001-00805F9B07D0",
                payload: Data([0x01])
            )
        }

        let snapshot = await ledger.currentPreflightSnapshot()
        #expect(snapshot.applicationPayloadCount == 0)
        #expect(snapshot.latestObservedUptimeNanoseconds == 10)
    }

    @Test("empty and retrograde receipts cannot become evidence")
    func chronologyAndPayloadIntegrity() async throws {
        let ledger = try TuyaAuthenticatedReadOnlyEvidenceLedger(
            connectionGeneration: 1,
            connectionStartedAtUptimeNanoseconds: 50,
            authenticatedAtUptimeNanoseconds: 100,
            authMethod: .smartLifeAppSDK
        )

        await #expect(throws: TuyaAuthenticatedReadOnlyEvidenceLedger.AdmissionError.emptyPayload) {
            try await ledger.admitApplicationNotification(
                connectionGeneration: 1,
                monotonicNanoseconds: 101,
                characteristicUUID: TuyaFD50AuthenticatedReadOnlyTarget.notificationCharacteristicUUID,
                payload: Data()
            )
        }
        try await ledger.observeAuthenticatedConnectionAlive(connectionGeneration: 1, monotonicNanoseconds: 120)
        await #expect(throws: TuyaAuthenticatedReadOnlyEvidenceLedger.AdmissionError.nonMonotonicUptime) {
            try await ledger.admitApplicationNotification(
                connectionGeneration: 1,
                monotonicNanoseconds: 119,
                characteristicUUID: TuyaFD50AuthenticatedReadOnlyTarget.notificationCharacteristicUUID,
                payload: Data([0x02])
            )
        }

        let snapshot = await ledger.currentPreflightSnapshot()
        #expect(snapshot.applicationPayloadCount == 0)
        #expect(snapshot.latestObservedUptimeNanoseconds == 120)
    }

    @Test("payload plus 45 seconds of observed authenticated continuity unlocks only stationary mapping")
    func acceptedPreflightProjection() async throws {
        let authenticatedAt: UInt64 = 1_000
        let ledger = try TuyaAuthenticatedReadOnlyEvidenceLedger(
            connectionGeneration: 9,
            connectionStartedAtUptimeNanoseconds: 500,
            authenticatedAtUptimeNanoseconds: authenticatedAt,
            authMethod: .documentedDeviceSharing
        )
        try await ledger.admitApplicationNotification(
            connectionGeneration: 9,
            monotonicNanoseconds: authenticatedAt + 1,
            characteristicUUID: TuyaFD50AuthenticatedReadOnlyTarget.notificationCharacteristicUUID.lowercased(),
            payload: Data([0x00, 0x11, 0x22])
        )
        try await ledger.observeAuthenticatedConnectionAlive(
            connectionGeneration: 9,
            monotonicNanoseconds: authenticatedAt + TuyaAuthenticatedReadOnlyPreflight.minimumAuthenticatedConnectionNanoseconds
        )

        let artifact = try await ledger.seal()
        #expect(artifact.preflightVerdict == .readyForStationaryMapping)
        #expect(artifact.notifications.count == 1)
        #expect(artifact.notifications[0].receiptIndex == 1)
        #expect(artifact.notifications[0].connectionGeneration == 9)
        #expect(artifact.preflightSnapshot.connectionStartedAtUptimeNanoseconds == 500)
        #expect(artifact.preflightSnapshot.latestApplicationPayloadUptimeNanoseconds == authenticatedAt + 1)
    }

    @Test("seal freezes the admitted prefix and cannot manufacture survival time")
    func immutableSeal() async throws {
        let ledger = try TuyaAuthenticatedReadOnlyEvidenceLedger(
            connectionGeneration: 2,
            connectionStartedAtUptimeNanoseconds: 40,
            authenticatedAtUptimeNanoseconds: 50,
            authMethod: .smartLifeAppSDK
        )
        try await ledger.admitApplicationNotification(
            connectionGeneration: 2,
            monotonicNanoseconds: 60,
            characteristicUUID: TuyaFD50AuthenticatedReadOnlyTarget.notificationCharacteristicUUID,
            payload: Data([0xAA])
        )

        let first = try await ledger.seal()
        let second = try await ledger.seal()
        #expect(first == second)
        #expect(first.latestObservedUptimeNanoseconds == 60)
        #expect(first.preflightVerdict == .blocked(reason: "Authenticated connection has not survived the physical stability window yet."))

        await #expect(throws: TuyaAuthenticatedReadOnlyEvidenceLedger.AdmissionError.sealed) {
            try await ledger.observeAuthenticatedConnectionAlive(
                connectionGeneration: 2,
                monotonicNanoseconds: 50_000_000_060
            )
        }
    }

    @Test("authentication cannot predate the connection generation")
    func authenticationChronologyIsConstructorBound() {
        #expect(throws: TuyaAuthenticatedReadOnlyEvidenceLedger.AdmissionError.authenticationPredatesConnection) {
            _ = try TuyaAuthenticatedReadOnlyEvidenceLedger(
                connectionGeneration: 3,
                connectionStartedAtUptimeNanoseconds: 200,
                authenticatedAtUptimeNanoseconds: 199,
                authMethod: .smartLifeAppSDK
            )
        }
    }

    @Test("JSON exports exact raw bytes with structural credential-field exclusion")
    func exportIsRawAndStructurallyRedacted() async throws {
        let ledger = try TuyaAuthenticatedReadOnlyEvidenceLedger(
            connectionGeneration: 4,
            connectionStartedAtUptimeNanoseconds: 1,
            authenticatedAtUptimeNanoseconds: 10,
            authMethod: .documentedDeviceSharing
        )
        let payload = Data([0xDE, 0xAD, 0xBE, 0xEF])
        try await ledger.admitApplicationNotification(
            connectionGeneration: 4,
            monotonicNanoseconds: 20,
            characteristicUUID: TuyaFD50AuthenticatedReadOnlyTarget.notificationCharacteristicUUID,
            payload: payload
        )
        let artifact = try await ledger.seal()
        let data = try artifact.encodedJSON()
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(object["transportFamily"] as? String == "tuya-fd50")
        #expect(object["authMethod"] as? String == "tuya-device-sharing")
        #expect(object["applicationNotificationCount"] as? Int == 1)
        #expect(object["serviceUUID"] as? String == "FD50")
        #expect(object["notificationCharacteristicUUID"] as? String == TuyaFD50AuthenticatedReadOnlyTarget.notificationCharacteristicUUID)
        #expect(object["latestApplicationPayloadUptimeNanoseconds"] as? UInt64 == 20)
        let notifications = try #require(object["notifications"] as? [[String: Any]])
        #expect(notifications[0]["payloadHex"] as? String == "deadbeef")
        #expect(notifications[0]["payloadBase64"] as? String == payload.base64EncodedString())

        let redactions = try #require(object["redactions"] as? [String: Any])
        for key in ["accountPasswordExcluded", "cloudTokenExcluded", "appSecretExcluded", "localKeyExcluded", "sessionKeyExcluded", "authKeyExcluded", "qrAuthorizationTokenExcluded"] {
            #expect(redactions[key] as? Bool == true)
        }
        for forbiddenKey in ["localKey", "sessionKey", "authKey", "appSecret", "accessToken", "refreshToken", "password"] {
            #expect(object[forbiddenKey] == nil)
        }
    }
}
