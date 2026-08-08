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

    @Test("unused H admission quarantines without fabricating recorder rejection or durable H")
    @MainActor
    func unusedAdmissionQuarantinesAsDistinctZeroMutationOrigin() async throws {
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

        await #expect(throws: PassiveCoreBluetoothObservationBoundaryMutationAttemptError.alreadyAttempted) {
            _ = try await horizon.recordBoundaryWithMutationOutcome(on: recorder)
        }
        #expect((await recorder.snapshot()).observationBoundaries.count == 1)
    }

    @Test("copied H admission shares the one-shot permit between abandonment and recording")
    @MainActor
    func copiedAdmissionCannotRecordAfterAbandonmentWins() async throws {
        let recorder = try PassiveCoreBluetoothCaptureRecorder(
            vehicleIdentity: es80,
            startedAt: Date(timeIntervalSince1970: 1)
        )
        let fence = PassiveCoreBluetoothArtifactAuthorityFence(authority: authority)
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let horizon = try await horizonAdmission(gate: &gate, fence: fence, recorder: recorder)
        let copiedHorizon = horizon

        let abandonment = try copiedHorizon.abandonBeforeRecorderAttempt()
        _ = try gate.abortHorizonBeforeRecorderAttempt(after: abandonment)

        await #expect(throws: PassiveCoreBluetoothObservationBoundaryMutationAttemptError.alreadyAttempted) {
            _ = try await horizon.recordBoundary(on: recorder)
        }
        #expect((await recorder.snapshot()).observationBoundaries.count == 1)
    }

    @Test("recorder attempt winning first permanently prevents pre-attempt abandonment")
    @MainActor
    func recorderAttemptCannotBeRelabeledAsPreAttemptAbandonment() async throws {
        let recorder = try PassiveCoreBluetoothCaptureRecorder(
            vehicleIdentity: es80,
            startedAt: Date(timeIntervalSince1970: 1)
        )
        let fence = PassiveCoreBluetoothArtifactAuthorityFence(authority: authority)
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let horizon = try await horizonAdmission(gate: &gate, fence: fence, recorder: recorder)

        let recorded = try await horizon.recordBoundary(on: recorder)
        #expect(throws: PassiveCoreBluetoothObservationBoundaryMutationAttemptError.alreadyAttempted) {
            _ = try horizon.abandonBeforeRecorderAttempt()
        }

        let committed = try recorded.markBoundaryRecorded(
            on: &gate,
            lastProcessedQueueSequence: recorded.queueCutoff
        )
        try committed.completeHorizonArtifactFreeze(on: &gate)
        #expect(gate.isTerminal)
        #expect((await recorder.snapshot()).observationBoundaries.count == 2)
    }

    @Test("equal-scalar foreign abandonment receipt cannot quarantine another gate")
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
        #expect((await recorderB.snapshot()).observationBoundaries.count == 1)

        let abortA = try gateA.abortHorizonBeforeRecorderAttempt(after: abandonmentA)
        #expect(abortA.origin == .uncommittedHorizonAbandonedBeforeRecorderAttempt)
        #expect(gateA.isAbortQuarantined)
    }
}
