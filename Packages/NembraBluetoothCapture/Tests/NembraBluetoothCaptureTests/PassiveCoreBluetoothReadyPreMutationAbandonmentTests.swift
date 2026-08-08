import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Passive CoreBluetooth Ready pre-mutation abandonment")
struct PassiveCoreBluetoothReadyPreMutationAbandonmentTests {
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

    @Test("unused Ready admission quarantines without fabricating durable Ready")
    @MainActor
    func exactUnusedReadyQuarantines() async throws {
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

        #expect((await recorder.snapshot()).observationBoundaries.isEmpty)

        let abandonment = try ready.abandonBeforeRecorderMutation()
        #expect(abandonment.queueCutoff == 2)
        #expect(abandonment.authority == authority)

        let abort = try gate.abortUncommittedReady(after: abandonment)
        #expect(abort.origin == .uncommittedReadyAbandonedBeforeRecorderMutation)
        #expect(abort.abandonedReadyQueueCutoff == 2)
        #expect(abort.abandonedEvidenceQueueCutoff == 2)
        #expect(gate.phase == .abortQuarantined(abort))
        #expect(!gate.isTerminal)
        #expect(!gate.resetForNewCaptureSession())
        #expect((await recorder.snapshot()).observationBoundaries.isEmpty)

        #expect(throws: PassiveCoreBluetoothObservationBoundaryMutationAttemptError.alreadyAttempted) {
            _ = try ready.abandonBeforeRecorderMutation()
        }
        await #expect(throws: PassiveCoreBluetoothObservationBoundaryMutationAttemptError.alreadyAttempted) {
            _ = try await ready.recordBoundaryWithMutationOutcome(on: recorder)
        }
        #expect((await recorder.snapshot()).observationBoundaries.isEmpty)
    }

    @Test("Ready recorder attempt and pre-mutation abandonment share one permit")
    @MainActor
    func recorderAttemptWinsBeforeAbandonment() async throws {
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

        _ = try await ready.recordBoundary(on: recorder)
        #expect((await recorder.snapshot()).observationBoundaries.map(\.kind) == [.finiteAcquisitionReady])

        #expect(throws: PassiveCoreBluetoothObservationBoundaryMutationAttemptError.alreadyAttempted) {
            _ = try ready.abandonBeforeRecorderMutation()
        }
        #expect(!gate.isAbortQuarantined)
    }

    @Test("equal-scalar foreign Ready abandonment cannot quarantine another gate")
    @MainActor
    func foreignAbandonmentFailsExactIdentity() throws {
        let fenceA = PassiveCoreBluetoothArtifactAuthorityFence(authority: authority)
        let fenceB = PassiveCoreBluetoothArtifactAuthorityFence(authority: authority)
        var gateA = PassiveCoreBluetoothObservationBoundaryQueueGate()
        var gateB = PassiveCoreBluetoothObservationBoundaryQueueGate()

        let readyA = try PassiveCoreBluetoothObservationBoundaryTransactionDecision.beginReady(
            queueCutoff: 2,
            processedThrough: 2,
            authorityFence: fenceA,
            gate: &gateA
        )
        _ = try PassiveCoreBluetoothObservationBoundaryTransactionDecision.beginReady(
            queueCutoff: 2,
            processedThrough: 2,
            authorityFence: fenceB,
            gate: &gateB
        )

        let abandonmentA = try readyA.abandonBeforeRecorderMutation()
        #expect(throws: PassiveCoreBluetoothObservationBoundaryQueueGate.StateError.staleTransaction) {
            _ = try gateB.abortUncommittedReady(after: abandonmentA)
        }
        #expect(!gateB.isAbortQuarantined)
    }
}
