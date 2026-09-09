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
