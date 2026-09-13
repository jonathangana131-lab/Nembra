import Testing
@testable import NembraBluetoothCapture

struct C7D09A22DocumentedSmartLifeReadOnlyConnectorTests {
    @Test
    @MainActor
    func linkedAccountIdentityRoutesOnlyDocumentedAuthenticatedConnectInputs() async throws {
        let identity = try #require(
            C7D09A22DocumentedSmartLifeReadOnlyConnector.LinkedDeviceIdentity(
                deviceID: "demo",
                uuid: "6815A5F5-4D1E-E004-BAE8-6DF924123907",
                productID: "FD50"
            )
        )
        let connector = C7D09A22DocumentedSmartLifeReadOnlyConnector()
        var observedUUID: String?
        var observedProductID: String?

        _ = try await connector.connect(identity: identity) { uuid, productID in
            observedUUID = uuid
            observedProductID = productID
            // This closure models the app's official Smart Life SDK connect + exact-UUID
            // SDK-local-online observation. It deliberately has no DP/write/reset API.
        }

        #expect(observedUUID == identity.uuid)
        #expect(observedProductID == identity.productID)

        let snapshot = await connector.currentPreflightSnapshot()
        #expect(snapshot.authenticationState == .authenticated)
        #expect(snapshot.authenticationMethod == .smartLifeAppSDK)
        #expect(snapshot.hasActiveCallbackAuthority)
        #expect(connector.authorizesRawFD50CharacteristicCustody == false)
        #expect(connector.authorizesTelemetrySemantics == false)
        #expect(connector.authorizesControlWrites == false)
        #expect(connector.authorizesPairingResetOrUnbind == false)
    }

    @Test
    @MainActor
    func rejectsIncompleteLinkedAccountIdentityBeforeAnySessionCanExist() async {
        #expect(
            C7D09A22DocumentedSmartLifeReadOnlyConnector.LinkedDeviceIdentity(
                deviceID: "demo",
                uuid: "   ",
                productID: "FD50"
            ) == nil
        )
    }
}
