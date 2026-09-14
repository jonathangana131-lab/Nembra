import Foundation
import Testing
@testable import NembraBluetoothCapture

struct C7D09A22DocumentedSmartLifeVerifiedAccountPreflightTests {
    private let deviceID = "demo"
    private let uuid = "6815A5F5-4D1E-E004-BAE8-6DF924123907"
    private let productID = "FD50"
    private let accountUID = "linked-user"

    private func identity() throws -> C7D09A22DocumentedSmartLifeReadOnlyConnector.LinkedDeviceIdentity {
        try #require(
            C7D09A22DocumentedSmartLifeReadOnlyConnector.LinkedDeviceIdentity(
                deviceID: deviceID,
                uuid: uuid,
                productID: productID
            )
        )
    }

    private func membership(containsDevice: Bool = true) -> TuyaSDKAccountDeviceMembershipGate.Snapshot {
        .init(
            isLoggedIn: true,
            homeEnumerationCompleted: true,
            loadedHomeCount: 1,
            ownedDeviceIDs: containsDevice ? [deviceID] : [],
            sharedDeviceIDs: [],
            homeLoadFailureCount: 0
        )
    }

    private func lease(currentUID: String? = nil, membershipUID: String? = nil) -> TuyaSDKAccountIdentityLeaseGate.Snapshot {
        .init(
            isLoggedIn: true,
            currentAccountUID: currentUID ?? accountUID,
            membershipAccountUID: membershipUID ?? accountUID,
            expectedDeviceID: deviceID,
            membershipDeviceID: deviceID
        )
    }

    @Test
    @MainActor
    func exactLinkedAccountProofPermitsOnlyDocumentedAuthenticatedConnect() async throws {
        let connector = C7D09A22DocumentedSmartLifeReadOnlyConnector()
        var connectCalls = 0

        let token = try await C7D09A22DocumentedSmartLifeVerifiedAccountPreflight.connect(
            connector: connector,
            identity: identity(),
            membershipSnapshot: membership(),
            identityLeaseSnapshot: lease()
        ) { observedUUID, observedProductID in
            connectCalls += 1
            #expect(observedUUID == uuid)
            #expect(observedProductID == productID)
        }

        #expect(connectCalls == 1)
        let snapshot = try await connector.currentPreflightSnapshot()
        #expect(snapshot.connectionGeneration == token.diagnosticGeneration)
        #expect(snapshot.authenticationState == .authenticated)
        #expect(snapshot.authenticationMethod == .smartLifeAppSDK)
        #expect(snapshot.hasActiveCallbackAuthority)
        #expect(C7D09A22DocumentedSmartLifeVerifiedAccountPreflight.authorizesTelemetrySemantics == false)
        #expect(C7D09A22DocumentedSmartLifeVerifiedAccountPreflight.authorizesControlWrites == false)
        #expect(C7D09A22DocumentedSmartLifeVerifiedAccountPreflight.authorizesPairingResetOrUnbind == false)
    }

    @Test
    @MainActor
    func absentExactDeviceMembershipBlocksBeforeSDKConnect() async throws {
        let connector = C7D09A22DocumentedSmartLifeReadOnlyConnector()
        var connectCalls = 0

        do {
            _ = try await C7D09A22DocumentedSmartLifeVerifiedAccountPreflight.connect(
                connector: connector,
                identity: identity(),
                membershipSnapshot: membership(containsDevice: false),
                identityLeaseSnapshot: lease()
            ) { _, _ in
                connectCalls += 1
            }
            Issue.record("unverified account membership reached SDK connect")
        } catch let error as C7D09A22DocumentedSmartLifeVerifiedAccountPreflight.Error {
            if case .accountMembershipNotAuthorized = error {
                // Expected.
            } else {
                Issue.record("unexpected preflight error: \(error)")
            }
        }

        #expect(connectCalls == 0)
        let snapshot = await connector.currentPreflightSnapshot()
        #expect(snapshot.authenticationState != .authenticated)
        #expect(snapshot.hasActiveCallbackAuthority == false)
    }

    @Test
    @MainActor
    func accountSwitchAfterMembershipProofBlocksBeforeSDKConnect() async throws {
        let connector = C7D09A22DocumentedSmartLifeReadOnlyConnector()
        var connectCalls = 0

        do {
            _ = try await C7D09A22DocumentedSmartLifeVerifiedAccountPreflight.connect(
                connector: connector,
                identity: identity(),
                membershipSnapshot: membership(),
                identityLeaseSnapshot: lease(currentUID: "other-user", membershipUID: accountUID)
            ) { _, _ in
                connectCalls += 1
            }
            Issue.record("changed Tuya account identity reached SDK connect")
        } catch let error as C7D09A22DocumentedSmartLifeVerifiedAccountPreflight.Error {
            if case .accountIdentityLeaseNotAuthorized = error {
                // Expected.
            } else {
                Issue.record("unexpected preflight error: \(error)")
            }
        }

        #expect(connectCalls == 0)
        let snapshot = await connector.currentPreflightSnapshot()
        #expect(snapshot.authenticationState != .authenticated)
        #expect(snapshot.hasActiveCallbackAuthority == false)
    }
}
