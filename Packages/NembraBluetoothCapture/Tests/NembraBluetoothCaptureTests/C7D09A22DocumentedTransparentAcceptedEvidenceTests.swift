import Foundation
import Testing
@testable import NembraBluetoothCapture

struct C7D09A22DocumentedTransparentAcceptedEvidenceTests {
    @Test
    @MainActor
    func acceptanceScopedExportStaysNilBeforeTransportAcceptance() async throws {
        let ledger = TuyaAuthenticatedReadOnlySessionLedger()
        let token = try await ledger.beginConnection()
        try await ledger.markAuthenticationStarted(for: token)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        let authenticated = await ledger.currentPreflightSnapshot()

        let preflight = C7D09A22DocumentedTransparentLivePreflight(
            preflightSnapshotProvider: { await ledger.currentPreflightSnapshot() }
        )
        #expect(await preflight.arm(
            connectionToken: token,
            expectedDeviceID: "demo",
            authenticatedPreflightSnapshot: authenticated
        ))

        // Exact documented callback bytes are useful diagnostic evidence immediately, but they
        // must not become an acceptance-scoped portable artifact before the independently observed
        // authenticated session and repeated receive stream survive the post-auth rejection window.
        preflight.receiveDocumentedSmartLifeCallback(
            payload: Data([0xc7, 0xd0, 0x9a, 0x22]),
            deviceID: "demo"
        )
        await Task.yield()

        #expect(await preflight.evidenceArtifact() != nil)
        #expect(await preflight.acceptedDocumentedTransportEvidenceArtifact() == nil)

        let cut = await preflight.fieldAttemptEvidence()
        #expect(!cut.satisfiesDocumentedAuthenticatedTransportAcceptance)
        #expect(!cut.authorizesRawFD50CharacteristicCustody)
        #expect(!cut.authorizesTelemetrySemantics)
        #expect(!cut.authorizesControlWrites)
        #expect(!cut.authorizesPairingResetOrUnbind)
    }
}
