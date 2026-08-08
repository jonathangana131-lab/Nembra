import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Passive CoreBluetooth uncommitted Horizon recovery")
struct PassiveCoreBluetoothUncommittedHorizonRecoveryTests {
    private typealias Gate = PassiveCoreBluetoothObservationBoundaryQueueGate
    private typealias Rejection = PassiveCoreBluetoothHorizonRecorderMutationRejectionReceipt

    private struct PendingEvent: Equatable {
        let queueSequence: UInt64
        let authority: PassiveCoreBluetoothArtifactAuthorityContext
    }

    private let authority = PassiveCoreBluetoothArtifactAuthorityContext(
        targetSessionGeneration: 7,
        authorityGeneration: 11
    )

    private let replacementAuthority = PassiveCoreBluetoothArtifactAuthorityContext(
        targetSessionGeneration: 7,
        authorityGeneration: 12
    )

    private let es80 = VehicleIdentity(
        manufacturer: "AOVOPRO",
        model: "ES80",
        displayName: "AOVOPRO ES80",
        protocolFamily: "Tuya / AOVOPRO (hardware validation pending)"
    )

    @Test("canonical Horizon rejection quarantines exact zero-mutation admission")
    @MainActor
    func rejectedHorizonPreservesReadyWithoutFabricatingDurableH() async throws {
        var gate = Gate()
        let recorder = try PassiveCoreBluetoothCaptureRecorder(
            vehicleIdentity: es80,
            startedAt: Date(timeIntervalSince1970: 1)
        )
        let fence = PassiveCoreBluetoothArtifactAuthorityFence(authority: authority)

        let readyAdmission = try PassiveCoreBluetoothObservationBoundaryTransactionDecision.beginReady(
            queueCutoff: 2,
            processedThrough: 2,
            authorityFence: fence,
            gate: &gate
        )
        let recordedReady = try await readyAdmission.recordBoundary(on: recorder)
        let ready = try recordedReady.markBoundaryRecorded(
            on: &gate,
            lastProcessedQueueSequence: 2
        )
        let horizon = try ready.beginHorizon(
            queueCutoff: 4,
            processedThrough: 2,
            gate: &gate
        )
        #expect(gate.phase == .drainingHorizon(try #require(gate.activeTransaction)))

        try fence.transition(from: authority, to: replacementAuthority)
        let rejection = try await rejectedHorizon(horizon, recorder: recorder)

        let beforeAbort = await recorder.snapshot()
        #expect(beforeAbort.observationBoundaries.count == 1)
        #expect(beforeAbort.observationBoundaries.first?.kind == .finiteAcquisitionReady)
        #expect(rejection.queueCutoff == 4)
        #expect(rejection.transactionRevision == horizon.transactionRevision)
        #expect(rejection.transactionIdentity == horizon.transactionIdentity)
        #expect(rejection.authority == authority)
        #expect(rejection.currentAuthority == replacementAuthority)

        let abort = try gate.abortUncommittedHorizon(after: rejection)
        #expect(abort.origin == .uncommittedHorizonRejectedBeforeRecorderMutation)
        #expect(abort.abandonedReadyQueueCutoff == 2)
        #expect(abort.abandonedHorizonQueueCutoff == 4)
        #expect(abort.abandonedHorizonTransactionRevision == horizon.transactionRevision)
        #expect(abort.abandonedHorizonTransactionIdentity == horizon.transactionIdentity)
        #expect(abort.abandonedEvidenceQueueCutoff == 2)
        #expect(gate.phase == .abortQuarantined(abort))
        #expect(gate.permittedDrainUpperBound(firstPending: 3, pendingTail: 5) == nil)

        let resetSucceeded = gate.resetForNewCaptureSession()
        #expect(!resetSucceeded)
        await #expect(throws: PassiveCoreBluetoothObservationBoundaryMutationAttemptError.alreadyAttempted) {
            _ = try await horizon.recordBoundary(on: recorder)
        }
        #expect((await recorder.snapshot()).observationBoundaries.count == 1)
    }

    @Test("equal-scalar foreign Horizon rejection cannot quarantine another gate")
    @MainActor
    func foreignRejectionFailsExactHorizonIdentity() async throws {
        var gateA = Gate()
        let recorderA = try PassiveCoreBluetoothCaptureRecorder(
            vehicleIdentity: es80,
            startedAt: Date(timeIntervalSince1970: 1)
        )
        let fenceA = PassiveCoreBluetoothArtifactAuthorityFence(authority: authority)
        let horizonA = try await beginHorizon(
            gate: &gateA,
            recorder: recorderA,
            fence: fenceA,
            readyCutoff: 2,
            horizonCutoff: 4
        )

        var gateB = Gate()
        let recorderB = try PassiveCoreBluetoothCaptureRecorder(
            vehicleIdentity: es80,
            startedAt: Date(timeIntervalSince1970: 1)
        )
        let fenceB = PassiveCoreBluetoothArtifactAuthorityFence(authority: authority)
        let horizonB = try await beginHorizon(
            gate: &gateB,
            recorder: recorderB,
            fence: fenceB,
            readyCutoff: 2,
            horizonCutoff: 4
        )

        #expect(horizonA.transactionRevision == horizonB.transactionRevision)
        #expect(horizonA.transactionIdentity != horizonB.transactionIdentity)
        try fenceA.transition(from: authority, to: replacementAuthority)
        try fenceB.transition(from: authority, to: replacementAuthority)
        let rejectionA = try await rejectedHorizon(horizonA, recorder: recorderA)
        let rejectionB = try await rejectedHorizon(horizonB, recorder: recorderB)

        #expect(throws: Gate.StateError.staleTransaction) {
            _ = try gateB.abortUncommittedHorizon(after: rejectionA)
        }
        #expect(gateB.activeTransaction?.identity == horizonB.transactionIdentity)

        let abortB = try gateB.abortUncommittedHorizon(after: rejectionB)
        #expect(abortB.origin == .uncommittedHorizonRejectedBeforeRecorderMutation)
        #expect(abortB.abandonedHorizonTransactionIdentity == horizonB.transactionIdentity)
    }

    @Test("zero-mutation Horizon retirement starts after durable Ready, not after nonexistent H")
    @MainActor
    func retirementUsesReadyAsFurthestDurableEvidenceCutoff() async throws {
        var gate = Gate()
        let recorder = try PassiveCoreBluetoothCaptureRecorder(
            vehicleIdentity: es80,
            startedAt: Date(timeIntervalSince1970: 1)
        )
        let fence = PassiveCoreBluetoothArtifactAuthorityFence(authority: authority)
        let horizon = try await beginHorizon(
            gate: &gate,
            recorder: recorder,
            fence: fence,
            readyCutoff: 2,
            horizonCutoff: 4
        )

        try fence.transition(from: authority, to: replacementAuthority)
        let rejection = try await rejectedHorizon(horizon, recorder: recorder)
        let abort = try gate.abortUncommittedHorizon(after: rejection)
        #expect(abort.abandonedEvidenceQueueCutoff == 2)
        #expect(abort.abandonedHorizonQueueCutoff == 4)

        var pending = [
            PendingEvent(queueSequence: 3, authority: replacementAuthority),
            PendingEvent(queueSequence: 4, authority: replacementAuthority),
            PendingEvent(queueSequence: 5, authority: replacementAuthority),
        ]
        let retirement = try PassiveCoreBluetoothAbortedObservationQueueRetirement.retire(
            from: &pending,
            currentLastEnqueuedEventSequence: 5,
            currentSettledQueueSequence: 2,
            drainIsIdle: true,
            abortedGate: gate,
            identity: { .init(queueSequence: $0.queueSequence, authority: $0.authority) }
        )

        #expect(pending.isEmpty)
        #expect(retirement.abortReceipt == abort)
        #expect(retirement.validatedSettledQueueSequence == 2)
        #expect(retirement.validatedQueueTailSequence == 5)
        #expect(retirement.retiredEvidenceCount == 3)
        #expect(retirement.retainedPendingEvidenceCount == 0)
        #expect((await recorder.snapshot()).observationBoundaries.count == 1)
    }

    @MainActor
    private func beginHorizon(
        gate: inout Gate,
        recorder: PassiveCoreBluetoothCaptureRecorder,
        fence: PassiveCoreBluetoothArtifactAuthorityFence,
        readyCutoff: UInt64,
        horizonCutoff: UInt64
    ) async throws -> PassiveCoreBluetoothObservationBoundaryTransactionDecision.HorizonAdmission {
        let readyAdmission = try PassiveCoreBluetoothObservationBoundaryTransactionDecision.beginReady(
            queueCutoff: readyCutoff,
            processedThrough: readyCutoff,
            authorityFence: fence,
            gate: &gate
        )
        let recordedReady = try await readyAdmission.recordBoundary(on: recorder)
        let ready = try recordedReady.markBoundaryRecorded(
            on: &gate,
            lastProcessedQueueSequence: readyCutoff
        )
        return try ready.beginHorizon(
            queueCutoff: horizonCutoff,
            processedThrough: readyCutoff,
            gate: &gate
        )
    }

    private func rejectedHorizon(
        _ admission: PassiveCoreBluetoothObservationBoundaryTransactionDecision.HorizonAdmission,
        recorder: PassiveCoreBluetoothCaptureRecorder
    ) async throws -> Rejection {
        let outcome = try await admission.recordBoundaryWithMutationOutcome(on: recorder)
        switch outcome {
        case .recorded:
            Issue.record("Revoked Horizon must not append a boundary.")
            throw UnexpectedRecordedHorizon()
        case let .rejectedBeforeMutation(receipt):
            return receipt
        }
    }

    private struct UnexpectedRecordedHorizon: Error {}
}
