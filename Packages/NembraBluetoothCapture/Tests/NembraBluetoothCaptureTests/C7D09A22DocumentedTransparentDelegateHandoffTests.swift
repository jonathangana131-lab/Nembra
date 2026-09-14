import Foundation
import Testing
@testable import NembraBluetoothCapture

@MainActor
private final class C7D09A22SuspendedSnapshotGate {
    private(set) var isWaiting = false
    private var continuation: CheckedContinuation<TuyaAuthenticatedReadOnlyPreflightSnapshot?, Never>?

    func snapshot() async -> TuyaAuthenticatedReadOnlyPreflightSnapshot? {
        isWaiting = true
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resume(returning snapshot: TuyaAuthenticatedReadOnlyPreflightSnapshot?) {
        isWaiting = false
        let continuation = continuation
        self.continuation = nil
        continuation?.resume(returning: snapshot)
    }
}

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

    @Test
    @MainActor
    func callbackSuspendedInSnapshotLookupCannotRecordAfterRetirementStarts() async throws {
        let context = try await authenticatedContext()
        let gate = C7D09A22SuspendedSnapshotGate()
        var recordCallbackCount = 0

        let handoff = C7D09A22DocumentedTransparentDelegateHandoff(
            preflightSnapshotProvider: {
                await gate.snapshot()
            },
            recordObserver: { result in
                if result != nil { recordCallbackCount += 1 }
            }
        )

        #expect(await handoff.begin(
            connectionToken: context.token,
            expectedDeviceID: "demo",
            authenticatedPreflightSnapshot: context.snapshot
        ))

        handoff.receive(payload: Data([0xC7, 0xD0, 0x9A, 0x22]), callbackDeviceID: "demo")
        for _ in 0..<20 where !gate.isWaiting {
            await Task.yield()
        }
        #expect(gate.isWaiting)

        let retireTask = Task { @MainActor in
            await handoff.retire()
        }
        for _ in 0..<20 where handoff.hasActiveGeneration {
            await Task.yield()
        }
        #expect(!handoff.hasActiveGeneration)

        gate.resume(returning: context.snapshot)
        await retireTask.value
        for _ in 0..<5 { await Task.yield() }

        #expect(recordCallbackCount == 0)
        #expect(await handoff.diagnosticSnapshot() == nil)
        #expect(!handoff.authorizesPhysicalFirstAcceptance)
        #expect(!handoff.authorizesTelemetrySemantics)
        #expect(!handoff.authorizesControlWrites)
        #expect(!handoff.authorizesPairingResetOrUnbind)
    }

    @Test
    @MainActor
    func diagnosticReadStartedUnderOlderLifecycleCannotReturnAfterRearmBegins() async throws {
        let first = try await authenticatedContext()
        let second = try await authenticatedContext()
        let gate = C7D09A22SuspendedSnapshotGate()

        let handoff = C7D09A22DocumentedTransparentDelegateHandoff(
            preflightSnapshotProvider: {
                await gate.snapshot()
            }
        )

        #expect(await handoff.begin(
            connectionToken: first.token,
            expectedDeviceID: "demo",
            authenticatedPreflightSnapshot: first.snapshot
        ))

        handoff.receive(payload: Data([0xC7, 0xD0, 0x9A, 0x22]), callbackDeviceID: "demo")
        for _ in 0..<20 where !gate.isWaiting {
            await Task.yield()
        }
        #expect(gate.isWaiting)

        let oldDiagnostic = Task { @MainActor in
            await handoff.diagnosticSnapshot()
        }
        await Task.yield()

        let rearm = Task { @MainActor in
            await handoff.begin(
                connectionToken: second.token,
                expectedDeviceID: "demo",
                authenticatedPreflightSnapshot: second.snapshot
            )
        }
        for _ in 0..<20 where handoff.hasActiveGeneration {
            await Task.yield()
        }
        #expect(!handoff.hasActiveGeneration)

        gate.resume(returning: first.snapshot)

        #expect(await oldDiagnostic.value == nil)
        #expect(await rearm.value)
        #expect(handoff.hasActiveGeneration)
        #expect(!handoff.authorizesPhysicalFirstAcceptance)
        #expect(!handoff.authorizesTelemetrySemantics)
        #expect(!handoff.authorizesControlWrites)
        #expect(!handoff.authorizesPairingResetOrUnbind)
    }
}
