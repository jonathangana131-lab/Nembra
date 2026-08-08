import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Passive CoreBluetooth Horizon append/commit reentrancy")
struct PassiveCoreBluetoothHorizonCommitReentrancyTests {
    private let authority = PassiveCoreBluetoothArtifactAuthorityContext(
        targetSessionGeneration: 7,
        authorityGeneration: 11
    )

    private let es80 = VehicleIdentity(
        manufacturer: "AOVOPRO",
        model: "ES80",
        displayName: "AOVOPRO ES80",
        protocolFamily: "Tuya / AOVOPRO (hardware validation pending)"
    )

    @Test("durable Horizon append remains fail-closed when authority changes before queue commit")
    @MainActor
    func durableHorizonAppendThenAuthorityAdvancePinsRecoveryGap() async throws {
        let recorder = try PassiveCoreBluetoothCaptureRecorder(
            vehicleIdentity: es80,
            startedAt: Date(timeIntervalSince1970: 1)
        )
        let fence = PassiveCoreBluetoothArtifactAuthorityFence(authority: authority)
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()

        let ready = try PassiveCoreBluetoothObservationBoundaryTransactionDecision.beginReady(
            queueCutoff: 0,
            processedThrough: 0,
            authorityFence: fence,
            gate: &gate
        )
        let recordedReady = try await ready.recordBoundary(on: recorder)
        let committedReady = try recordedReady.markBoundaryRecorded(
            on: &gate,
            lastProcessedQueueSequence: 0
        )

        let horizon = try committedReady.beginHorizon(
            queueCutoff: 0,
            processedThrough: 0,
            gate: &gate
        )
        let recordedHorizon = try await horizon.recordBoundary(on: recorder)
        let activeHorizon = try #require(gate.activeTransaction)

        let afterAppend = await recorder.snapshot()
        #expect(afterAppend.observationBoundaries.map(\.kind) == [
            .finiteAcquisitionReady,
            .observationHorizon
        ])
        #expect(gate.phase == .drainingHorizon(activeHorizon))

        let replacementAuthority = PassiveCoreBluetoothArtifactAuthorityContext(
            targetSessionGeneration: authority.targetSessionGeneration,
            authorityGeneration: authority.authorityGeneration + 1
        )
        try fence.transition(from: authority, to: replacementAuthority)

        #expect(throws: PassiveCoreBluetoothObservationBoundaryQueueGate.StateError.authorityChanged) {
            _ = try recordedHorizon.markBoundaryRecorded(
                on: &gate,
                lastProcessedQueueSequence: 0
            )
        }

        // The irreversible recorder mutation is truthful and must not be erased or
        // relabeled as a zero-mutation rejection. The current package intentionally
        // fails closed here, but unlike recorded Ready there is not yet a producer-issued
        // Horizon recovery receipt that can quarantine/retire this exact partial state.
        #expect((await recorder.snapshot()).observationBoundaries.map(\.kind) == [
            .finiteAcquisitionReady,
            .observationHorizon
        ])
        #expect(gate.phase == .drainingHorizon(activeHorizon))
        #expect(!gate.isTerminal)
        #expect(!gate.resetForNewCaptureSession())
        #expect(gate.permittedDrainUpperBound(firstPending: 1, pendingTail: 1) == nil)

        #expect(throws: PassiveCoreBluetoothObservationBoundaryQueueGate.StateError.invalidTransition) {
            _ = try gate.abortObservationEpoch(committedReady)
        }

        await #expect(throws: PassiveCoreBluetoothObservationBoundaryMutationAttemptError.alreadyAttempted) {
            _ = try await horizon.recordBoundary(on: recorder)
        }
        #expect((await recorder.snapshot()).observationBoundaries.count == 2)
    }
}
