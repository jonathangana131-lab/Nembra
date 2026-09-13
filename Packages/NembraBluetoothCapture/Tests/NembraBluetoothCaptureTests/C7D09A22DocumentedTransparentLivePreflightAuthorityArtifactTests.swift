import Foundation
import Testing
@testable import NembraBluetoothCapture

private actor C7D09A22PreflightSnapshotBox {
    private var snapshot: TuyaAuthenticatedReadOnlyPreflightSnapshot?

    init(_ snapshot: TuyaAuthenticatedReadOnlyPreflightSnapshot?) {
        self.snapshot = snapshot
    }

    func get() -> TuyaAuthenticatedReadOnlyPreflightSnapshot? { snapshot }
    func set(_ snapshot: TuyaAuthenticatedReadOnlyPreflightSnapshot?) { self.snapshot = snapshot }
}

struct C7D09A22DocumentedTransparentLivePreflightAuthorityArtifactTests {
    @Test
    @MainActor
    func retiredCallbackAuthorityCannotExportDocumentedEvidenceArtifact() async throws {
        let ledger = TuyaAuthenticatedReadOnlySessionLedger()
        let token = try await ledger.beginConnection()
        try await ledger.markAuthenticationStarted(for: token)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        let authenticated = await ledger.currentPreflightSnapshot()
        let box = C7D09A22PreflightSnapshotBox(authenticated)

        let preflight = C7D09A22DocumentedTransparentLivePreflight(
            preflightSnapshotProvider: { await box.get() }
        )
        #expect(await preflight.arm(
            connectionToken: token,
            expectedDeviceID: "demo",
            authenticatedPreflightSnapshot: authenticated
        ))

        preflight.receive(payload: Data([0xaa, 0x55]), callbackDeviceID: "demo")
        await Task.yield()
        #expect(await preflight.evidenceArtifact() != nil)

        let retired = TuyaAuthenticatedReadOnlyPreflightSnapshot(
            authenticationState: .authenticated,
            authenticationMethod: .smartLifeAppSDK,
            connectionStartedAtUptimeNanoseconds: authenticated.connectionStartedAtUptimeNanoseconds,
            authenticatedAtUptimeNanoseconds: authenticated.authenticatedAtUptimeNanoseconds,
            latestObservedUptimeNanoseconds: authenticated.latestObservedUptimeNanoseconds,
            applicationPayloadCount: authenticated.applicationPayloadCount,
            latestApplicationPayloadUptimeNanoseconds: authenticated.latestApplicationPayloadUptimeNanoseconds,
            connectionGeneration: authenticated.connectionGeneration,
            hasActiveCallbackAuthority: false
        )
        await box.set(retired)

        #expect(await preflight.evidenceArtifact() == nil)
        #expect(await preflight.transportMilestone() == .blockedUnauthenticated)
        #expect(!(await preflight.fieldAttemptEvidence().satisfiesDocumentedAuthenticatedTransportAcceptance))
    }
}
