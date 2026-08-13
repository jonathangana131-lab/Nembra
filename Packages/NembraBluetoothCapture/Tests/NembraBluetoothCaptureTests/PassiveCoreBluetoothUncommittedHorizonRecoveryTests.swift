import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Passive CoreBluetooth uncommitted Horizon recovery")
struct PassiveCoreBluetoothUncommittedHorizonRecoveryTests {
    private struct PendingEvent: Equatable {
        let queueSequence: UInt64
        let authority: PassiveCoreBluetoothArtifactAuthorityContext
    }

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

    @Test("explicit pre-attempt H abandonment consumes one-shot authority and preserves zero durable H")
    @MainActor
    func explicitPreAttemptAbandonmentQuarantinesWithoutMutation() async throws {
        let recorder = try PassiveCoreBluetoothCaptureRecorder(
            vehicleIdentity: es80,
            startedAt: Date(timeIntervalSince1970: 1)
        )
        let fence = PassiveCoreBluetoothArtifactAuthorityFence(authority: authority)
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let horizon = try await horizonAdmission(gate: &gate, fence: fence, recorder: recorder)

        #expect((await recorder.snapshot()).observationBoundaries.count == 1)
        let abandonment = try horizon.abandonBeforeRecorderMutation()
        #expect(abandonment.queueCutoff == 4)
        #expect(abandonment.authority == authority)

        let abort = try gate.abortUncommittedHorizon(after: abandonment)
        #expect(abort.origin == .uncommittedHorizonAbandonedBeforeRecorderMutation)
        #expect(abort.abandonedReadyQueueCutoff == 2)
        #expect(abort.abandonedEvidenceQueueCutoff == 2)
        #expect(abort.abandonedUnrecordedHorizonQueueCutoff == 4)
        #expect(abort.abandonedUnrecordedHorizonTransactionRevision == abandonment.transactionRevision)
        #expect(abort.abandonedUnrecordedHorizonTransactionIdentity == abandonment.transactionIdentity)
        #expect(abort.abandonedHorizonQueueCutoff == nil)
        #expect(gate.phase == .abortQuarantined(abort))
        #expect(!gate.isTerminal)
        #expect((await recorder.snapshot()).observationBoundaries.count == 1)

        #expect(throws: PassiveCoreBluetoothObservationBoundaryMutationAttemptError.alreadyAttempted) {
            _ = try horizon.abandonBeforeRecorderMutation()
        }
        await #expect(throws: PassiveCoreBluetoothObservationBoundaryMutationAttemptError.alreadyAttempted) {
            _ = try await horizon.recordBoundaryWithMutationOutcome(on: recorder)
        }
        #expect((await recorder.snapshot()).observationBoundaries.count == 1)
    }

    @Test("foreign pre-attempt abandonment proof cannot quarantine another exact H transaction")
    @MainActor
    func foreignPreAttemptAbandonmentFailsExactIdentity() async throws {
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
        let abandonment = try horizonA.abandonBeforeRecorderMutation()

        #expect(throws: PassiveCoreBluetoothObservationBoundaryQueueGate.StateError.staleTransaction) {
            _ = try gateB.abortUncommittedHorizon(after: abandonment)
        }
        #expect(!gateB.isAbortQuarantined)
        #expect((await recorderA.snapshot()).observationBoundaries.count == 1)
        #expect((await recorderB.snapshot()).observationBoundaries.count == 1)
    }

    @Test("canonical rejection before H mutation quarantines exact zero-H epoch")
    @MainActor
    func canonicalRejectionBeforeHMutationQuarantinesWithoutFabricatingH() async throws {
        let recorder = try PassiveCoreBluetoothCaptureRecorder(
            vehicleIdentity: es80,
            startedAt: Date(timeIntervalSince1970: 1)
        )
        let fence = PassiveCoreBluetoothArtifactAuthorityFence(authority: authority)
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let horizon = try await horizonAdmission(gate: &gate, fence: fence, recorder: recorder)
        #expect((await recorder.snapshot()).observationBoundaries.count == 1)

        let replacement = PassiveCoreBluetoothArtifactAuthorityContext(
            targetSessionGeneration: authority.targetSessionGeneration,
            authorityGeneration: authority.authorityGeneration + 1
        )
        try fence.transition(from: authority, to: replacement)

        let outcome = try await horizon.recordBoundaryWithMutationOutcome(on: recorder)
        let rejection: PassiveCoreBluetoothObservationBoundaryTransactionDecision.HorizonRecorderMutationRejectionReceipt
        switch outcome {
        case .recorded:
            Issue.record("Revoked Horizon authority must not append a durable H boundary.")
            return
        case let .rejectedBeforeMutation(receipt):
            rejection = receipt
        }

        #expect(rejection.queueCutoff == 4)
        #expect(rejection.authority == authority)
        #expect(rejection.currentAuthority == replacement)
        #expect((await recorder.snapshot()).observationBoundaries.count == 1)

        let abort = try gate.abortUncommittedHorizon(after: rejection)
        #expect(abort.origin == .uncommittedHorizonRejectedBeforeRecorderMutation)
        #expect(abort.abandonedReadyQueueCutoff == 2)
        #expect(abort.abandonedEvidenceQueueCutoff == 2)
        #expect(abort.abandonedUnrecordedHorizonQueueCutoff == 4)
        #expect(abort.abandonedUnrecordedHorizonTransactionRevision == rejection.transactionRevision)
        #expect(abort.abandonedUnrecordedHorizonTransactionIdentity == rejection.transactionIdentity)
        #expect(abort.abandonedHorizonQueueCutoff == nil)
        #expect(abort.abandonedHorizonTransactionRevision == nil)
        #expect(abort.abandonedHorizonTransactionIdentity == nil)
        #expect(gate.phase == .abortQuarantined(abort))
        #expect(!gate.isTerminal)
        #expect(gate.permittedDrainUpperBound(firstPending: 5, pendingTail: 5) == nil)
        let resetWhileQuarantined = gate.resetForNewCaptureSession()
        #expect(!resetWhileQuarantined)

        await #expect(throws: PassiveCoreBluetoothObservationBoundaryMutationAttemptError.alreadyAttempted) {
            _ = try await horizon.recordBoundaryWithMutationOutcome(on: recorder)
        }
        #expect((await recorder.snapshot()).observationBoundaries.count == 1)

        // Raw-event chronology may already be settled through the attempted H cutoff,
        // but that must not promote H into durable lifecycle evidence. Only the still-
        // pending suffix is retired, and the producer receipt keeps Ready as the
        // furthest durable observation boundary.
        var pending = [PendingEvent(queueSequence: 5, authority: replacement)]
        let retirement = try PassiveCoreBluetoothAbortedObservationQueueRetirement.retire(
            from: &pending,
            currentLastEnqueuedEventSequence: 5,
            currentSettledQueueSequence: 4,
            drainIsIdle: true,
            abortedGate: gate,
            identity: { .init(queueSequence: $0.queueSequence, authority: $0.authority) }
        )
        #expect(pending.isEmpty)
        #expect(retirement.abortReceipt == abort)
        #expect(retirement.validatedSettledQueueSequence == 4)
        #expect(retirement.abortReceipt.abandonedEvidenceQueueCutoff == 2)
        #expect(retirement.retiredEvidenceCount == 1)
    }

    @Test("equal-scalar foreign zero-H rejection cannot quarantine another gate")
    @MainActor
    func foreignZeroHRejectionFailsExactIdentity() async throws {
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

        let replacement = PassiveCoreBluetoothArtifactAuthorityContext(
            targetSessionGeneration: authority.targetSessionGeneration,
            authorityGeneration: authority.authorityGeneration + 1
        )
        try fenceA.transition(from: authority, to: replacement)
        let outcome = try await horizonA.recordBoundaryWithMutationOutcome(on: recorderA)
        let rejection: PassiveCoreBluetoothObservationBoundaryTransactionDecision.HorizonRecorderMutationRejectionReceipt
        switch outcome {
        case .recorded:
            Issue.record("Revoked Horizon authority must reject before mutation.")
            return
        case let .rejectedBeforeMutation(receipt):
            rejection = receipt
        }

        #expect(throws: PassiveCoreBluetoothObservationBoundaryQueueGate.StateError.staleTransaction) {
            _ = try gateB.abortUncommittedHorizon(after: rejection)
        }
        #expect(!gateB.isAbortQuarantined)
        #expect((await recorderB.snapshot()).observationBoundaries.count == 1)
    }

    @Test("ordinary Horizon success outcome remains recorded and commit-capable")
    @MainActor
    func unchangedAuthorityRecordsHorizonNormally() async throws {
        let recorder = try PassiveCoreBluetoothCaptureRecorder(
            vehicleIdentity: es80,
            startedAt: Date(timeIntervalSince1970: 1)
        )
        let fence = PassiveCoreBluetoothArtifactAuthorityFence(authority: authority)
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let horizon = try await horizonAdmission(gate: &gate, fence: fence, recorder: recorder)

        let outcome = try await horizon.recordBoundaryWithMutationOutcome(on: recorder)
        switch outcome {
        case let .recorded(recorded):
            let committed = try recorded.markBoundaryRecorded(
                on: &gate,
                lastProcessedQueueSequence: recorded.queueCutoff
            )
            try committed.completeHorizonArtifactFreeze(on: &gate)
        case .rejectedBeforeMutation:
            Issue.record("Unchanged authority must not produce zero-H rejection authority.")
        }

        #expect((await recorder.snapshot()).observationBoundaries.count == 2)
        #expect(gate.isTerminal)
    }
}
