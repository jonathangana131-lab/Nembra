import Foundation
import Testing
@testable import NembraBluetoothCapture

struct C7D09A22DocumentedTransparentDelegateHandoffTests {
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
    func callbackHandoffRequestsSnapshotOnlyAfterSynchronousCustodyAdmission() async throws {
        let context = try await authenticatedContext()
        var snapshotRequestCount = 0
        var recordCallbackCount = 0

        let handoff = C7D09A22DocumentedTransparentDelegateHandoff(
            preflightSnapshotProvider: {
                snapshotRequestCount += 1
                return context.snapshot
            },
            recordObserver: { result in
                if result != nil { recordCallbackCount += 1 }
            }
        )

        handoff.receive(payload: Data([0x01]), callbackDeviceID: "demo")
        await Task.yield()
        #expect(snapshotRequestCount == 0)

        #expect(await handoff.begin(
            connectionToken: context.token,
            expectedDeviceID: " demo ",
            authenticatedPreflightSnapshot: context.snapshot
        ))
        #expect(handoff.hasActiveGeneration)

        handoff.receive(payload: Data([0x02]), callbackDeviceID: "other-device")
        handoff.receive(payload: Data(), callbackDeviceID: "demo")
        await Task.yield()
        #expect(snapshotRequestCount == 0)

        handoff.receive(payload: Data([0xA5, 0x5A]), callbackDeviceID: " demo ")
        for _ in 0..<20 where snapshotRequestCount == 0 {
            await Task.yield()
        }

        #expect(snapshotRequestCount == 1)
        #expect(recordCallbackCount <= 1)
        #expect(!handoff.authorizesRawFD50CharacteristicCustody)
        #expect(!handoff.authorizesPhysicalFirstAcceptance)
        #expect(!handoff.authorizesStationaryMapping)
        #expect(!handoff.authorizesTelemetrySemantics)
        #expect(!handoff.authorizesControlWrites)
        #expect(!handoff.authorizesPairingResetOrUnbind)
    }

    @Test
    @MainActor
    func retirementPreventsQueuedOrLaterCallbacksFromBorrowingAuthority() async throws {
        let context = try await authenticatedContext()
        var snapshotRequestCount = 0

        let handoff = C7D09A22DocumentedTransparentDelegateHandoff(
            preflightSnapshotProvider: {
                snapshotRequestCount += 1
                return context.snapshot
            }
        )

        #expect(await handoff.begin(
            connectionToken: context.token,
            expectedDeviceID: "demo",
            authenticatedPreflightSnapshot: context.snapshot
        ))

        await handoff.retire()
        #expect(!handoff.hasActiveGeneration)

        handoff.receive(payload: Data([0xFF]), callbackDeviceID: "demo")
        for _ in 0..<5 { await Task.yield() }

        #expect(snapshotRequestCount == 0)
        #expect(await handoff.diagnosticSnapshot() == nil)
    }
}
