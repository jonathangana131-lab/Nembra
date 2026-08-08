import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Passive CoreBluetooth post-Horizon pre-freeze recovery")
struct PassiveCoreBluetoothPostHorizonPreFreezeRecoveryTests {
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

    @Test("durable committed Horizon cannot be stranded when freeze authority changes")
    @MainActor
    func committedHorizonNeedsExactPreFreezeRecovery() async throws {
        let recorder = try PassiveCoreBluetoothCaptureRecorder(
            vehicleIdentity: es80,
            startedAt: Date(timeIntervalSince1970: 1)
        )
        let fence = PassiveCoreBluetoothArtifactAuthorityFence(authority: authority)
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()

        let ready = try PassiveCoreBluetoothObservationBoundaryTransactionDecision.beginReady(
            queueCutoff: 2,
            processedThrough: 2,
            authorityFence: fence,
            gate: &gate
        )
        let recordedReady = try await ready.recordBoundary(on: recorder)
        let committedReady = try recordedReady.markBoundaryRecorded(
            on: &gate,
            lastProcessedQueueSequence: 2
        )
        let horizon = try committedReady.beginHorizon(
            queueCutoff: 4,
            processedThrough: 2,
            gate: &gate
        )
        let recordedHorizon = try await horizon.recordBoundary(on: recorder)
        let committedHorizon = try recordedHorizon.markBoundaryRecorded(
            on: &gate,
            lastProcessedQueueSequence: 4
        )
        let openHorizonTransaction = try #require(gate.activeTransaction)

        #expect((await recorder.snapshot()).observationBoundaries.count == 2)
        #expect(gate.phase == .horizonBoundaryRecorded(openHorizonTransaction))
        #expect(!gate.isTerminal)

        let replacement = PassiveCoreBluetoothArtifactAuthorityContext(
            targetSessionGeneration: authority.targetSessionGeneration,
            authorityGeneration: authority.authorityGeneration + 1
        )
        try fence.transition(from: authority, to: replacement)

        do {
            try committedHorizon.completeHorizonArtifactFreeze(on: &gate)
            Issue.record("A revoked post-Horizon authority must not complete terminal artifact freeze.")
        } catch let error as PassiveCoreBluetoothObservationBoundaryQueueGate.StateError {
            #expect(error == .authorityChanged)
        }

        #expect((await recorder.snapshot()).observationBoundaries.count == 2)
        #expect(gate.phase == .horizonBoundaryRecorded(openHorizonTransaction))
        #expect(!gate.isTerminal)
        #expect(gate.permittedDrainUpperBound(firstPending: 5, pendingTail: 5) == nil)
        let resetWhilePreFreezeHorizonIsStranded = gate.resetForNewCaptureSession()
        #expect(!resetWhilePreFreezeHorizonIsStranded)

        Issue.record(
            "A durable, queue-committed Horizon can remain stranded in horizonBoundaryRecorded after pre-freeze authority failure. The current typestate exposes no producer-issued retry/quarantine/recovery authority for this exact state."
        )
    }
}
