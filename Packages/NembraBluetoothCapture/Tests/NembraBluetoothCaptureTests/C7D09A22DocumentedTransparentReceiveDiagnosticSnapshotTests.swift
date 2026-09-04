import Foundation
import Testing
@testable import NembraBluetoothCapture

struct C7D09A22DocumentedTransparentReceiveDiagnosticSnapshotTests {
    @Test
    @MainActor
    func diagnosticSnapshotExposesOnlyCurrentAuthenticatedTransportEvidence() async throws {
        let ledger = TuyaAuthenticatedReadOnlySessionLedger()
        let token = try await ledger.beginConnection()
        try await ledger.markAuthenticationStarted(for: token)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        let authenticatedSnapshot = await ledger.currentPreflightSnapshot()
        let connectionStartedAt = try #require(authenticatedSnapshot.authenticatedAtUptimeNanoseconds)

        let ingress = C7D09A22DocumentedTransparentReceiveIngress()
        #expect(await ingress.begin(
            connectionToken: token,
            expectedDeviceID: " demo ",
            sdkConnectionStartedAtUptimeNanoseconds: connectionStartedAt,
            authenticatedPreflightSnapshot: authenticatedSnapshot
        ))

        let emptySnapshot = try #require(await ingress.diagnosticSnapshot())
        #expect(emptySnapshot.tuyaDeviceID == "demo")
        #expect(emptySnapshot.payloadCount == 0)
        #expect(emptySnapshot.totalByteCount == 0)
        #expect(!emptySnapshot.hasPayloadStrictlyBeyondHistoricalRejectionHorizon)
        #expect(!emptySnapshot.authorizesRawFD50CharacteristicCustody)
        #expect(!emptySnapshot.authorizesPhysicalFirstAcceptance)
        #expect(!emptySnapshot.authorizesStationaryMapping)
        #expect(!emptySnapshot.authorizesTelemetrySemantics)
        #expect(!emptySnapshot.authorizesControlWrites)
        #expect(!emptySnapshot.authorizesPairingResetOrUnbind)

        let payload = Data([0xAA, 0x55, 0x01])
        let receipt = try #require(ingress.capture(payload: payload, callbackDeviceID: "demo"))
        _ = await ingress.record(receipt, preflightSnapshot: authenticatedSnapshot)

        let recordedSnapshot = try #require(await ingress.diagnosticSnapshot())
        #expect(recordedSnapshot.payloadCount == 1)
        #expect(recordedSnapshot.totalByteCount == payload.count)
        #expect(recordedSnapshot.latestPayloadAtUptimeNanoseconds != nil)
        #expect(!recordedSnapshot.hasPayloadStrictlyBeyondHistoricalRejectionHorizon)
        #expect(!recordedSnapshot.authorizesPhysicalFirstAcceptance)
        #expect(!recordedSnapshot.authorizesTelemetrySemantics)

        await ingress.retire()
        #expect(await ingress.diagnosticSnapshot() == nil)
        #expect(!ingress.hasActiveGeneration)
    }
}
