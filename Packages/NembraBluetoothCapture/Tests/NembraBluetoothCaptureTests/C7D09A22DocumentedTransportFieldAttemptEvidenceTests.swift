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

        // A documented callback from any other Tuya device must never contaminate the
        // assistant-owned field artifact, even while the exact authenticated generation is armed.
        preflight.receiveDocumentedSmartLifeCallback(
            payload: Data([0xde, 0xad]),
            deviceID: "different-linked-tuya-device"
        )
        await Task.yield()

        let afterWrongDevice = await preflight.fieldAttemptEvidence()
        let stillEmpty = try #require(afterWrongDevice.artifact)
        #expect(afterWrongDevice.milestone == .waitingForFirstPayload)
        #expect(stillEmpty.tuyaDeviceID == "demo")
        #expect(stillEmpty.payloadCount == 0)
        #expect(stillEmpty.totalByteCount == 0)
        #expect(stillEmpty.retainedPayloads.isEmpty)
        #expect(!afterWrongDevice.satisfiesDocumentedAuthenticatedTransportAcceptance)

        preflight.receiveDocumentedSmartLifeCallback(
            payload: Data([0xc7, 0xd0, 0x9a, 0x22]),
            deviceID: "demo"
        )
        await Task.yield()

        let received = await preflight.fieldAttemptEvidence()
        #expect(received.milestone == .waitingForHistoricalRejectionWindow)
        let artifact = try #require(received.artifact)
        #expect(artifact.tuyaDeviceID == "demo")
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