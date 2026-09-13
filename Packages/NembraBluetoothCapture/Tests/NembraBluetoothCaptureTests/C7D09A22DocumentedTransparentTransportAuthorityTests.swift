import Foundation
import Testing
@testable import NembraBluetoothCapture

struct C7D09A22DocumentedTransparentTransportAuthorityTests {
    @Test
    func retiredAuthenticatedGenerationCannotSatisfyDocumentedTransportMilestoneFromOldBytes() {
        let authenticatedAt: UInt64 = 1
        let postHorizon = authenticatedAt
            + TuyaAuthenticatedReadOnlyPreflight.minimumPostAuthenticationPayloadSurvivalNanoseconds
            + 1

        let retiredSnapshot = TuyaAuthenticatedReadOnlyPreflightSnapshot(
            authenticationState: .authenticated,
            authenticationMethod: .smartLifeAppSDK,
            connectionStartedAtUptimeNanoseconds: 0,
            authenticatedAtUptimeNanoseconds: authenticatedAt,
            latestObservedUptimeNanoseconds: postHorizon,
            applicationPayloadCount: 2,
            latestApplicationPayloadUptimeNanoseconds: postHorizon,
            connectionGeneration: 1,
            hasActiveCallbackAuthority: false
        )

        let retainedTransparentBytes = TuyaSmartLifeTransparentReceiveObservationLedger.Snapshot(
            tuyaDeviceID: "demo",
            sdkConnectionStartedAtUptimeNanoseconds: 0,
            payloadCount: 2,
            totalByteCount: 2,
            latestPayloadAtUptimeNanoseconds: postHorizon,
            hasPayloadStrictlyBeyondHistoricalRejectionHorizon: true,
            retainedPayloads: [
                .init(payload: Data([0x01]), receivedAtUptimeNanoseconds: authenticatedAt + 1),
                .init(payload: Data([0x02]), receivedAtUptimeNanoseconds: postHorizon)
            ],
            retainedPayloadByteCount: 2,
            omittedPayloadCount: 0
        )

        #expect(C7D09A22DocumentedTransparentTransportMilestone.verdict(
            authenticatedPreflight: retiredSnapshot,
            transparent: retainedTransparentBytes
        ) == .blockedUnauthenticated)
    }
}
