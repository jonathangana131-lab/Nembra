import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

/// Expected-red adversarial contract for Ready allocated before any recorder attempt.
///
/// The foreground controller can enter `.drainingReady`, suspend while draining the
/// exact cutoff, then fail health/foreground validation before it ever calls the
/// recorder. Mutation-point rejection cannot describe that state because no recorder
/// attempt reached the canonical authority fence. The unused Ready admission therefore
/// needs its own one-shot producer proof, symmetric with Horizon pre-attempt abandonment.
struct PassiveCoreBluetoothReadyPreAttemptAbandonmentTests {
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

    @Test("unused Ready admission can quarantine before any recorder attempt")
    @MainActor
    func exactUnusedReadyQuarantinesWithoutFabricatingDurableReady() async throws {
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

        let abandonment = try ready.abandonBeforeRecorderAttempt()
        #expect(abandonment.queueCutoff == 2)
        #expect(abandonment.authority == authority)

        let abort = try gate.abortReadyBeforeRecorderAttempt(after: abandonment)
        #expect(abort.origin == .uncommittedReadyAbandonedBeforeRecorderAttempt)
        #expect(abort.abandonedReadyQueueCutoff == 2)
        // The exact FIFO prefix may already have drained into the recorder before
        // controller health failed; preserve that chronology without fabricating a
        // durable finiteAcquisitionReady lifecycle marker.
        #expect(abort.abandonedEvidenceQueueCutoff == 2)
        #expect(gate.phase == .abortQuarantined(abort))
        #expect(!gate.isTerminal)
        #expect(!gate.resetForNewCaptureSession())
        #expect((await recorder.snapshot()).observationBoundaries.isEmpty)

        #expect(throws: PassiveCoreBluetoothObservationBoundaryMutationAttemptError.alreadyAttempted) {
            _ = try ready.abandonBeforeRecorderAttempt()
        }
        await #expect(throws: PassiveCoreBluetoothObservationBoundaryMutationAttemptError.alreadyAttempted) {
            _ = try await ready.recordBoundaryWithMutationOutcome(on: recorder)
        }
        #expect((await recorder.snapshot()).observationBoundaries.isEmpty)
    }

    @Test("a Ready recorder attempt consumes the same permit before abandonment can win")
    @MainActor
    func recorderAttemptAndPreAttemptAbandonmentAreMutuallyExclusive() async throws {
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
            _ = try ready.abandonBeforeRecorderAttempt()
        }
        #expect(!gate.isAbortQuarantined)
    }

    @Test("equal-scalar foreign Ready abandonment cannot quarantine another gate")
    @MainActor
    func foreignPreAttemptReceiptFailsExactTransactionIdentity() async throws {
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

        let abandonmentA = try readyA.abandonBeforeRecorderAttempt()
        #expect(throws: PassiveCoreBluetoothObservationBoundaryQueueGate.StateError.staleTransaction) {
            _ = try gateB.abortReadyBeforeRecorderAttempt(after: abandonmentA)
        }
        #expect(!gateB.isAbortQuarantined)
    }
}
