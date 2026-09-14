import Foundation
import Testing
@testable import NembraBluetoothCapture

struct C7D09A22AuthenticatedTransparentReceiveAuthorityTests {
    @Test
    func authenticatedSnapshotWithoutActiveCallbackAuthorityIsRejected() {
        let snapshot = TuyaAuthenticatedReadOnlyPreflightSnapshot(
            authenticationState: .authenticated,
            authenticationMethod: .smartLifeAppSDK,
            connectionStartedAtUptimeNanoseconds: 10,
            authenticatedAtUptimeNanoseconds: 20,
            latestObservedUptimeNanoseconds: 30,
            applicationPayloadCount: 0,
            connectionGeneration: 1,
            hasActiveCallbackAuthority: false
        )

        #expect(
            C7D09A22AuthenticatedTransparentReceiveAdmission.verdict(
                snapshot: snapshot,
                bindingGeneration: 1,
                receivedAtUptimeNanoseconds: 25
            ) == .rejectNotAuthenticated
        )
    }

    @Test
    func sameAuthenticatedSnapshotWithActiveCallbackAuthorityIsAdmitted() {
        let snapshot = TuyaAuthenticatedReadOnlyPreflightSnapshot(
            authenticationState: .authenticated,
            authenticationMethod: .smartLifeAppSDK,
            connectionStartedAtUptimeNanoseconds: 10,
            authenticatedAtUptimeNanoseconds: 20,
            latestObservedUptimeNanoseconds: 30,
            applicationPayloadCount: 0,
            connectionGeneration: 1,
            hasActiveCallbackAuthority: true
        )

        #expect(
            C7D09A22AuthenticatedTransparentReceiveAdmission.verdict(
                snapshot: snapshot,
                bindingGeneration: 1,
                receivedAtUptimeNanoseconds: 25
            ) == .admitDiagnosticCallback
        )
    }
}
