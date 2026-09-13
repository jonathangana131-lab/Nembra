import Foundation
import Testing
@testable import NembraBluetoothCapture

struct C7D09A22DocumentedTransportConnectionChronologyTests {
    @Test
    func documentedReceiveFromAnotherConnectionChronologyCannotSatisfyMilestone() {
        let authenticatedAt: UInt64 = 5_000_000_000
        let connectionStarted: UInt64 = 1_000_000_000
        let horizon = TuyaAuthenticatedReadOnlyPreflight.minimumPostAuthenticationPayloadSurvivalNanoseconds
        let postHorizon = authenticatedAt + horizon + 1

        let authenticated = TuyaAuthenticatedReadOnlyPreflightSnapshot(
            authenticationState: .authenticated,
            authenticationMethod: .smartLifeAppSDK,
            connectionStartedAtUptimeNanoseconds: connectionStarted,
            authenticatedAtUptimeNanoseconds: authenticatedAt,
            latestObservedUptimeNanoseconds: postHorizon + 1,
            applicationPayloadCount: 0,
            connectionGeneration: 1,
            hasActiveCallbackAuthority: true
        )

        // These are otherwise-valid repeated post-auth receives, but they were captured under a
        // different physical connection start. Matching a diagnostic generation number is not
        // enough authority to splice them into this authenticated session's acceptance milestone.
        let foreignConnectionReceive = TuyaSmartLifeTransparentReceiveObservationLedger.Snapshot(
            tuyaDeviceID: "demo",
            sdkConnectionStartedAtUptimeNanoseconds: connectionStarted + 1,
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
            authenticatedPreflight: authenticated,
            transparent: foreignConnectionReceive
        ) == .waitingForHistoricalRejectionWindow)

        let exactConnectionReceive = TuyaSmartLifeTransparentReceiveObservationLedger.Snapshot(
            tuyaDeviceID: "demo",
            sdkConnectionStartedAtUptimeNanoseconds: connectionStarted,
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
            authenticatedPreflight: authenticated,
            transparent: exactConnectionReceive
        ) == .satisfied)
        #expect(!C7D09A22DocumentedTransparentTransportMilestone.authorizesRawFD50CharacteristicCustody)
        #expect(!C7D09A22DocumentedTransparentTransportMilestone.authorizesTelemetrySemantics)
        #expect(!C7D09A22DocumentedTransparentTransportMilestone.authorizesControlWrites)
        #expect(!C7D09A22DocumentedTransparentTransportMilestone.authorizesPairingResetOrUnbind)
    }
}
