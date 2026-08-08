import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Passive CoreBluetooth Ready append/commit reentrancy")
struct PassiveCoreBluetoothReadyCommitReentrancyTests {
    private let readyAuthority = PassiveCoreBluetoothArtifactAuthorityContext(
        targetSessionGeneration: 7,
        authorityGeneration: 11
    )

    private let es80 = VehicleIdentity(
        manufacturer: "AOVOPRO",
        model: "ES80",
        displayName: "AOVOPRO ES80",
        protocolFamily: "Tuya / AOVOPRO (hardware validation pending)"
    )

    @Test("durable Ready append survives authority change before queue commit and quarantines exact token")
    @MainActor
    func durableReadyAppendThenAuthorityAdvanceUsesRecordedReadyRecovery() async throws {
        let recorder = try PassiveCoreBluetoothCaptureRecorder(
            vehicleIdentity: es80,
            startedAt: Date(timeIntervalSince1970: 1)
        )
        let fence = PassiveCoreBluetoothArtifactAuthorityFence(authority: readyAuthority)
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()

        let admission = try PassiveCoreBluetoothObservationBoundaryTransactionDecision.beginReady(
            queueCutoff: 0,
            processedThrough: 0,
            authorityFence: fence,
            gate: &gate
        )
        let recorded = try await admission.recordBoundary(on: recorder)
        let active = try #require(gate.activeTransaction)

        let afterAppend = await recorder.snapshot()
        #expect(afterAppend.observationBoundaries.count == 1)
        #expect(gate.phase == .drainingReady(active))

        let replacementAuthority = PassiveCoreBluetoothArtifactAuthorityContext(
            targetSessionGeneration: readyAuthority.targetSessionGeneration,
            authorityGeneration: readyAuthority.authorityGeneration + 1
        )
        try fence.transition(from: readyAuthority, to: replacementAuthority)

        #expect(throws: PassiveCoreBluetoothObservationBoundaryQueueGate.StateError.authorityChanged) {
            _ = try recorded.markBoundaryRecorded(
                on: &gate,
                lastProcessedQueueSequence: 0
            )
        }

        #expect(gate.phase == .drainingReady(active))
        #expect((await recorder.snapshot()).observationBoundaries.count == 1)

        let abort = try gate.abortRecordedReadyBeforeGateCommit(recorded)
        #expect(abort.origin == .recordedReadyInvalidatedBeforeGateCommit)
        #expect(abort.abandonedReadyAuthority == readyAuthority)
        #expect(abort.abandonedReadyQueueCutoff == recorded.queueCutoff)
        #expect(abort.abandonedReadyTransactionRevision == recorded.transactionRevision)
        #expect(abort.abandonedReadyTransactionIdentity == recorded.transactionIdentity)
        #expect(gate.phase == .abortQuarantined(abort))
        #expect(gate.permittedDrainUpperBound(firstPending: 1, pendingTail: 1) == nil)
        #expect(!gate.resetForNewCaptureSession())

        await #expect(throws: PassiveCoreBluetoothObservationBoundaryMutationAttemptError.alreadyAttempted) {
            _ = try await admission.recordBoundaryWithMutationOutcome(on: recorder)
        }
        #expect((await recorder.snapshot()).observationBoundaries.count == 1)
    }
}
