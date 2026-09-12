import Foundation
import Testing
@testable import NembraBluetoothCapture

struct C7D09A22DocumentedTransparentTransportMilestoneTests {
    private func authenticatedContext() async throws -> (
        ledger: TuyaAuthenticatedReadOnlySessionLedger,
        token: TuyaReadOnlyConnectionToken,
        snapshot: TuyaAuthenticatedReadOnlyPreflightSnapshot
    ) {
        let ledger = TuyaAuthenticatedReadOnlySessionLedger()
        let token = try await ledger.beginConnection()
        try await ledger.markAuthenticationStarted(for: token)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        return (ledger, token, await ledger.currentPreflightSnapshot())
    }

    @Test
    func unauthenticatedPreflightCannotClaimDocumentedTransportMilestone() {
        let snapshot = TuyaAuthenticatedReadOnlyPreflightSnapshot(
            authenticationState: .unavailable(reason: "not authenticated"),
            connectionStartedAtUptimeNanoseconds: nil,
            authenticatedAtUptimeNanoseconds: nil,
            latestObservedUptimeNanoseconds: nil,
            applicationPayloadCount: 0,
            connectionGeneration: 0
        )
        #expect(C7D09A22DocumentedTransparentTransportMilestone.verdict(
            authenticatedPreflight: snapshot,
            transparent: nil
        ) == .blockedUnauthenticated)
    }

    @Test
    func singlePostHorizonCallbackCannotSatisfyRepeatedReceiveMilestone() {
        let authenticated = TuyaAuthenticatedReadOnlyPreflightSnapshot(
            authenticationState: .authenticated,
            authenticationMethod: .smartLifeAppSDK,
            connectionStartedAtUptimeNanoseconds: 0,
            authenticatedAtUptimeNanoseconds: 1,
            latestObservedUptimeNanoseconds: 45_000_000_001,
            applicationPayloadCount: 2,
            latestApplicationPayloadUptimeNanoseconds: 31_000_000_002,
            connectionGeneration: 1
        )
        let oneDelayedCallback = TuyaSmartLifeTransparentReceiveObservationLedger.Snapshot(
            tuyaDeviceID: "demo",
            sdkConnectionStartedAtUptimeNanoseconds: 0,
            payloadCount: 1,
            totalByteCount: 1,
            latestPayloadAtUptimeNanoseconds: 31_000_000_001,
            hasPayloadStrictlyBeyondHistoricalRejectionHorizon: true,
            retainedPayloads: [
                .init(payload: Data([0x01]), receivedAtUptimeNanoseconds: 31_000_000_001)
            ],
            retainedPayloadByteCount: 1,
            omittedPayloadCount: 0
        )
        #expect(C7D09A22DocumentedTransparentTransportMilestone.verdict(
            authenticatedPreflight: authenticated,
            transparent: oneDelayedCallback
        ) == .waitingForHistoricalRejectionWindow)

        let repeatedCallbacks = TuyaSmartLifeTransparentReceiveObservationLedger.Snapshot(
            tuyaDeviceID: "demo",
            sdkConnectionStartedAtUptimeNanoseconds: 0,
            payloadCount: 2,
            totalByteCount: 2,
            latestPayloadAtUptimeNanoseconds: 31_000_000_001,
            hasPayloadStrictlyBeyondHistoricalRejectionHorizon: true,
            retainedPayloads: [
                .init(payload: Data([0x01]), receivedAtUptimeNanoseconds: 1_000_000_000),
                .init(payload: Data([0x02]), receivedAtUptimeNanoseconds: 31_000_000_001)
            ],
            retainedPayloadByteCount: 2,
            omittedPayloadCount: 0
        )
        #expect(C7D09A22DocumentedTransparentTransportMilestone.verdict(
            authenticatedPreflight: authenticated,
            transparent: repeatedCallbacks
        ) == .satisfied)
    }

    @Test
    func connectionRelativePostHorizonPayloadCannotSubstituteForThirtySecondsAfterAuthentication() {
        let authenticatedAt: UInt64 = 5_000_000_000
        let payloadAt: UInt64 = 31_000_000_001
        let snapshot = TuyaAuthenticatedReadOnlyPreflightSnapshot(
            authenticationState: .authenticated,
            authenticationMethod: .smartLifeAppSDK,
            connectionStartedAtUptimeNanoseconds: 0,
            authenticatedAtUptimeNanoseconds: authenticatedAt,
            latestObservedUptimeNanoseconds: 40_000_000_001,
            applicationPayloadCount: 0,
            connectionGeneration: 1
        )
        let transparent = TuyaSmartLifeTransparentReceiveObservationLedger.Snapshot(
            tuyaDeviceID: "demo",
            sdkConnectionStartedAtUptimeNanoseconds: 0,
            payloadCount: 2,
            totalByteCount: 2,
            latestPayloadAtUptimeNanoseconds: payloadAt,
            hasPayloadStrictlyBeyondHistoricalRejectionHorizon: true,
            retainedPayloads: [
                .init(payload: Data([0x01]), receivedAtUptimeNanoseconds: 6_000_000_000),
                .init(payload: Data([0x02]), receivedAtUptimeNanoseconds: payloadAt)
            ],
            retainedPayloadByteCount: 2,
            omittedPayloadCount: 0
        )

        #expect(payloadAt - authenticatedAt < TuyaAuthenticatedReadOnlyPreflight.minimumPostAuthenticationPayloadSurvivalNanoseconds)
        #expect(transparent.hasPayloadStrictlyBeyondHistoricalRejectionHorizon)
        #expect(C7D09A22DocumentedTransparentTransportMilestone.verdict(
            authenticatedPreflight: snapshot,
            transparent: transparent
        ) == .waitingForHistoricalRejectionWindow)
    }

    @Test
    func callbackBeyondThirtySecondsCannotProveTransportSurvivalWithoutIndependentLedgerObservation() {
        let authenticatedAt: UInt64 = 1
        let payloadAt = authenticatedAt + TuyaAuthenticatedReadOnlyPreflight.minimumPostAuthenticationPayloadSurvivalNanoseconds + 1
        let snapshot = TuyaAuthenticatedReadOnlyPreflightSnapshot(
            authenticationState: .authenticated,
            authenticationMethod: .smartLifeAppSDK,
            connectionStartedAtUptimeNanoseconds: 0,
            authenticatedAtUptimeNanoseconds: authenticatedAt,
            latestObservedUptimeNanoseconds: payloadAt - 1,
            applicationPayloadCount: 0,
            connectionGeneration: 1
        )
        let transparent = TuyaSmartLifeTransparentReceiveObservationLedger.Snapshot(
            tuyaDeviceID: "demo",
            sdkConnectionStartedAtUptimeNanoseconds: 0,
            payloadCount: 2,
            totalByteCount: 2,
            latestPayloadAtUptimeNanoseconds: payloadAt,
            hasPayloadStrictlyBeyondHistoricalRejectionHorizon: true,
            retainedPayloads: [
                .init(payload: Data([0x01]), receivedAtUptimeNanoseconds: 1_000_000_000),
                .init(payload: Data([0x02]), receivedAtUptimeNanoseconds: payloadAt)
            ],
            retainedPayloadByteCount: 2,
            omittedPayloadCount: 0
        )

        #expect(C7D09A22DocumentedTransparentTransportMilestone.verdict(
            authenticatedPreflight: snapshot,
            transparent: transparent
        ) == .waitingForHistoricalRejectionWindow)
    }

    @Test
    @MainActor
    func authenticatedSessionWaitsForTransparentPayloadThenHistoricalWindowSurvival() async throws {
        let context = try await authenticatedContext()
        let ingress = C7D09A22DocumentedTransparentReceiveIngress()
        #expect(await ingress.begin(
            connectionToken: context.token,
            expectedDeviceID: "demo",
            authenticatedPreflightSnapshot: context.snapshot
        ))

        let empty = await ingress.diagnosticSnapshot()
        #expect(C7D09A22DocumentedTransparentTransportMilestone.verdict(
            authenticatedPreflight: context.snapshot,
            transparent: empty
        ) == .waitingForFirstPayload)

        let receipt = try #require(ingress.capture(payload: Data([0x01]), callbackDeviceID: "demo"))
        _ = await ingress.record(receipt, preflightSnapshot: context.snapshot)
        let recorded = await ingress.diagnosticSnapshot()
        #expect(C7D09A22DocumentedTransparentTransportMilestone.verdict(
            authenticatedPreflight: context.snapshot,
            transparent: recorded
        ) == .waitingForHistoricalRejectionWindow)

        #expect(!C7D09A22DocumentedTransparentTransportMilestone.authorizesRawFD50CharacteristicCustody)
        #expect(!C7D09A22DocumentedTransparentTransportMilestone.authorizesPhysicalFirstAcceptance)
        #expect(!C7D09A22DocumentedTransparentTransportMilestone.authorizesStationaryMapping)
        #expect(!C7D09A22DocumentedTransparentTransportMilestone.authorizesTelemetrySemantics)
        #expect(!C7D09A22DocumentedTransparentTransportMilestone.authorizesControlWrites)
        #expect(!C7D09A22DocumentedTransparentTransportMilestone.authorizesPairingResetOrUnbind)
    }
}
