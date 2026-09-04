import Foundation
import Testing
@testable import NembraBluetoothCapture

struct C7D09A22DocumentedTransportFieldAttemptEvidenceTests {
    @Test
    @MainActor
    func coherentFieldAttemptEvidenceTracksExactBytesWithoutMintingPhysicalTruth() async throws {
        let ledger = TuyaAuthenticatedReadOnlySessionLedger()
        let token = try await ledger.beginConnection()
        try await ledger.markAuthenticationStarted(for: token)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        let authenticated = await ledger.currentPreflightSnapshot()

        let preflight = C7D09A22DocumentedTransparentLivePreflight(
            preflightSnapshotProvider: { await ledger.currentPreflightSnapshot() }
        )

        let blocked = await preflight.fieldAttemptEvidence()
        #expect(blocked.milestone == .blockedUnauthenticated)
        #expect(blocked.artifact == nil)
        #expect(!blocked.satisfiesDocumentedAuthenticatedTransportAcceptance)

        #expect(await preflight.arm(
            connectionToken: token,
            expectedDeviceID: "demo",
            authenticatedPreflightSnapshot: authenticated
        ))

        let waiting = await preflight.fieldAttemptEvidence()
        #expect(waiting.milestone == .waitingForFirstPayload)
        let empty = try #require(waiting.artifact)
        #expect(empty.tuyaDeviceID == "demo")
        #expect(empty.payloadCount == 0)
        #expect(!waiting.satisfiesDocumentedAuthenticatedTransportAcceptance)

        preflight.receiveDocumentedSmartLifeCallback(
            payload: Data([0xc7, 0xd0, 0x9a, 0x22]),
            deviceID: "demo"
        )
        await Task.yield()

        let received = await preflight.fieldAttemptEvidence()
        #expect(received.milestone == .waitingForHistoricalRejectionWindow)
        let artifact = try #require(received.artifact)
        #expect(artifact.payloadCount == 1)
        #expect(artifact.totalByteCount == 4)
        #expect(artifact.retainedPayloads.map(\.hex) == ["c7d09a22"])
        #expect(!received.satisfiesDocumentedAuthenticatedTransportAcceptance)

        #expect(!received.authorizesRawFD50CharacteristicCustody)
        #expect(!received.authorizesPhysicalFirstAcceptance)
        #expect(!received.authorizesStationaryMapping)
        #expect(!received.authorizesTelemetrySemantics)
        #expect(!received.authorizesControlWrites)
        #expect(!received.authorizesPairingResetOrUnbind)
    }
}