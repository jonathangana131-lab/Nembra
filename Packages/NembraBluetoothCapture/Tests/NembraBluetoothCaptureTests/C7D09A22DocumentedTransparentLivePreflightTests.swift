import Foundation
import Testing
@testable import NembraBluetoothCapture

struct C7D09A22DocumentedTransparentLivePreflightTests {
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
    @MainActor
    func livePreflightArmsOnlyAuthenticatedGenerationAndRetiresFailClosed() async throws {
        let context = try await authenticatedContext()
        let preflight = C7D09A22DocumentedTransparentLivePreflight(
            preflightSnapshotProvider: { await context.ledger.currentPreflightSnapshot() }
        )

        #expect(await preflight.transportMilestone() == .blockedUnauthenticated)
        #expect(await preflight.arm(
            connectionToken: context.token,
            expectedDeviceID: " demo ",
            authenticatedPreflightSnapshot: context.snapshot
        ))
        #expect(preflight.hasActiveAuthenticatedGeneration)
        #expect(await preflight.transportMilestone() == .waitingForFirstPayload)

        preflight.receive(payload: Data([0x01, 0x02]), callbackDeviceID: "demo")
        await Task.yield()
        #expect(await preflight.transportMilestone() == .waitingForHistoricalRejectionWindow)

        #expect(!preflight.authorizesRawFD50CharacteristicCustody)
        #expect(!preflight.authorizesPhysicalFirstAcceptance)
        #expect(!preflight.authorizesStationaryMapping)
        #expect(!preflight.authorizesTelemetrySemantics)
        #expect(!preflight.authorizesControlWrites)
        #expect(!preflight.authorizesPairingResetOrUnbind)

        await preflight.retire()
        #expect(!preflight.hasActiveAuthenticatedGeneration)
        #expect(await preflight.diagnosticSnapshot() == nil)
        #expect(await preflight.transportMilestone() == .blockedUnauthenticated)
    }

    @Test
    @MainActor
    func unauthenticatedSnapshotCannotArmLivePreflight() async throws {
        let ledger = TuyaAuthenticatedReadOnlySessionLedger()
        let token = try await ledger.beginConnection()
        let snapshot = await ledger.currentPreflightSnapshot()
        let preflight = C7D09A22DocumentedTransparentLivePreflight(
            preflightSnapshotProvider: { await ledger.currentPreflightSnapshot() }
        )

        #expect(!(await preflight.arm(
            connectionToken: token,
            expectedDeviceID: "demo",
            authenticatedPreflightSnapshot: snapshot
        )))
        #expect(!preflight.hasActiveAuthenticatedGeneration)
        #expect(await preflight.transportMilestone() == .blockedUnauthenticated)
    }
}
