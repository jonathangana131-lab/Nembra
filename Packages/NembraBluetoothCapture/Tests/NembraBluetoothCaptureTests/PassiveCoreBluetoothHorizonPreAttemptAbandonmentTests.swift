import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Passive CoreBluetooth Horizon pre-attempt abandonment")
struct PassiveCoreBluetoothHorizonPreAttemptAbandonmentTests {
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

    @MainActor
    private func horizonAdmission(
        gate: inout PassiveCoreBluetoothObservationBoundaryQueueGate,
        fence: PassiveCoreBluetoothArtifactAuthorityFence,
        recorder: PassiveCoreBluetoothCaptureRecorder
    ) async throws -> PassiveCoreBluetoothObservationBoundaryTransactionDecision.HorizonAdmission {
        let ready = try PassiveCoreBluetoothObservationBoundaryTransactionDecision.beginReady(
            queueCutoff: 2,
            processedThrough: 2,
            authorityFence: fence,
            gate: &gate
        )
        let recordedReady = try await ready.recordBoundary(on: recorder)
        let epoch = try recordedReady.markBoundaryRecorded(
            on: &gate,
            lastProcessedQueueSequence: 2
        )
        return try epoch.beginHorizon(
            queueCutoff: 4,
            processedThrough: 4,
            gate: &gate
        )
    }

    @Test("unused Horizon admission can quarantine before any recorder attempt")
    @MainActor
    func exactUnusedHorizonQuarantinesWithoutFabricatingDurableH() async throws {
        let recorder = try PassiveCoreBluetoothCaptureRecorder(
            vehicleIdentity: es80,
            startedAt: Date(timeIntervalSince1970: 1)
        )
        let fence = PassiveCoreBluetoothArtifactAuthorityFence(authority: authority)
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let horizon = try await horizonAdmission(gate: &gate, fence: fence, recorder: recorder)

        #expect((await recorder.snapshot()).observationBoundaries.count == 1)

        let abandonment = try horizon.abandonBeforeRecorderAttempt()
        #expect(abandonment.queueCutoff == 4)
        #expect(abandonment.authority == authority)

        let abort = try gate.abortHorizonBeforeRecorderAttempt(after: abandonment)
        #expect(abort.origin == .uncommittedHorizonAbandonedBeforeRecorderAttempt)
        #expect(abort.abandonedReadyQueueCutoff == 2)
        #expect(abort.abandonedEvidenceQueueCutoff == 2)
        #expect(abort.abandonedUnrecordedHorizonQueueCutoff == 4)
        #expect(abort.abandonedUnrecordedHorizonTransactionRevision == abandonment.transactionRevision)
        #expect(abort.abandonedUnrecordedHorizonTransactionIdentity == abandonment.transactionIdentity)
        #expect(abort.abandonedHorizonQueueCutoff == nil)
        #expect(abort.abandonedHorizonTransactionRevision == nil)
        #expect(abort.abandonedHorizonTransactionIdentity == nil)
        #expect(gate.phase == .abortQuarantined(abort))
        #expect(!gate.isTerminal)
        #expect(gate.permittedDrainUpperBound(firstPending: 5, pendingTail: 5) == nil)
        #expect(!gate.resetForNewCaptureSession())
        #expect((await recorder.snapshot()).observationBoundaries.count == 1)

        #expect(throws: PassiveCoreBluetoothObservationBoundaryMutationAttemptError.alreadyAttempted) {
            _ = try horizon.abandonBeforeRecorderAttempt()
        }
        await #expect(throws: PassiveCoreBluetoothObservationBoundaryMutationAttemptError.alreadyAttempted) {
            _ = try await horizon.recordBoundaryWithMutationOutcome(on: recorder)
        }
        #expect((await recorder.snapshot()).observationBoundaries.count == 1)
    }

    @Test("a recorder attempt consumes the same permit before abandonment can win")
    @MainActor
    func recorderAttemptAndPreAttemptAbandonmentAreMutuallyExclusive() async throws {
        let recorder = try PassiveCoreBluetoothCaptureRecorder(
            vehicleIdentity: es80,
            startedAt: Date(timeIntervalSince1970: 1)
        )
        let fence = PassiveCoreBluetoothArtifactAuthorityFence(authority: authority)
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let horizon = try await horizonAdmission(gate: &gate, fence: fence, recorder: recorder)

        _ = try await horizon.recordBoundary(on: recorder)
        #expect((await recorder.snapshot()).observationBoundaries.count == 2)

        #expect(throws: PassiveCoreBluetoothObservationBoundaryMutationAttemptError.alreadyAttempted) {
            _ = try horizon.abandonBeforeRecorderAttempt()
        }
        #expect(!gate.isAbortQuarantined)
    }

    @Test("equal-scalar foreign pre-attempt receipt cannot quarantine another gate")
    @MainActor
    func foreignPreAttemptReceiptFailsExactTransactionIdentity() async throws {
        let recorderA = try PassiveCoreBluetoothCaptureRecorder(
            vehicleIdentity: es80,
            startedAt: Date(timeIntervalSince1970: 1)
        )
        let recorderB = try PassiveCoreBluetoothCaptureRecorder(
            vehicleIdentity: es80,
            startedAt: Date(timeIntervalSince1970: 1)
        )
        let fenceA = PassiveCoreBluetoothArtifactAuthorityFence(authority: authority)
        let fenceB = PassiveCoreBluetoothArtifactAuthorityFence(authority: authority)
        var gateA = PassiveCoreBluetoothObservationBoundaryQueueGate()
        var gateB = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let horizonA = try await horizonAdmission(gate: &gateA, fence: fenceA, recorder: recorderA)
        _ = try await horizonAdmission(gate: &gateB, fence: fenceB, recorder: recorderB)

        let abandonmentA = try horizonA.abandonBeforeRecorderAttempt()

        #expect(throws: PassiveCoreBluetoothObservationBoundaryQueueGate.StateError.staleTransaction) {
            _ = try gateB.abortHorizonBeforeRecorderAttempt(after: abandonmentA)
        }
        #expect(!gateB.isAbortQuarantined)
        #expect((await recorderA.snapshot()).observationBoundaries.count == 1)
        #expect((await recorderB.snapshot()).observationBoundaries.count == 1)
    }
}
