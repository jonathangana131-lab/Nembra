import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Passive CoreBluetooth zero-Horizon mutation recovery")
struct PassiveCoreBluetoothZeroHorizonMutationRecoveryTests {
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
    private func admittedHorizon(
        recorder: PassiveCoreBluetoothCaptureRecorder,
        fence: PassiveCoreBluetoothArtifactAuthorityFence,
        gate: inout PassiveCoreBluetoothObservationBoundaryQueueGate,
        readyCutoff: UInt64 = 2,
        horizonCutoff: UInt64 = 4
    ) async throws -> PassiveCoreBluetoothObservationBoundaryTransactionDecision.HorizonAdmission {
        let ready = try PassiveCoreBluetoothObservationBoundaryTransactionDecision.beginReady(
            queueCutoff: readyCutoff,
            processedThrough: readyCutoff,
            authorityFence: fence,
            gate: &gate
        )
        let recordedReady = try await ready.recordBoundary(on: recorder)
        let epoch = try recordedReady.markBoundaryRecorded(
            on: &gate,
            lastProcessedQueueSequence: readyCutoff
        )
        return try epoch.beginHorizon(
            queueCutoff: horizonCutoff,
            processedThrough: horizonCutoff,
            gate: &gate
        )
    }

    @MainActor
    private func rejectedBeforeHorizonMutation(
        admission: PassiveCoreBluetoothObservationBoundaryTransactionDecision.HorizonAdmission,
        recorder: PassiveCoreBluetoothCaptureRecorder,
        fence: PassiveCoreBluetoothArtifactAuthorityFence
    ) async throws -> PassiveCoreBluetoothObservationBoundaryTransactionDecision.HorizonRecorderMutationRejectionReceipt {
        let replacement = PassiveCoreBluetoothArtifactAuthorityContext(
            targetSessionGeneration: authority.targetSessionGeneration,
            authorityGeneration: authority.authorityGeneration + 1
        )
        try fence.transition(from: authority, to: replacement)

        let outcome = try await admission.recordBoundaryWithMutationOutcome(on: recorder)
        switch outcome {
        case .recorded:
            Issue.record("revoked Horizon authority unexpectedly appended a durable H boundary")
            throw PassiveCoreBluetoothObservationBoundaryQueueGate.StateError.invalidTransition
        case let .rejectedBeforeMutation(receipt):
            #expect(receipt.currentAuthority == replacement)
            return receipt
        }
    }

    @Test("authority loss after Horizon admission quarantines zero-H mutation without fabricating durable Horizon")
    @MainActor
    func authorityLossBeforeHorizonMutationHasExactZeroHRecovery() async throws {
        let recorder = try PassiveCoreBluetoothCaptureRecorder(
            vehicleIdentity: es80,
            startedAt: Date(timeIntervalSince1970: 1)
        )
        let fence = PassiveCoreBluetoothArtifactAuthorityFence(authority: authority)
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let horizon = try await admittedHorizon(
            recorder: recorder,
            fence: fence,
            gate: &gate
        )
        let active = try #require(gate.activeTransaction)

        let rejection = try await rejectedBeforeHorizonMutation(
            admission: horizon,
            recorder: recorder,
            fence: fence
        )

        #expect((await recorder.snapshot()).observationBoundaries.count == 1)
        #expect(gate.phase == .drainingHorizon(active))
        #expect(rejection.queueCutoff == active.queueCutoff)
        #expect(rejection.transactionRevision == active.revision)
        #expect(rejection.transactionIdentity == active.identity)

        let abort = try gate.abortUncommittedHorizon(after: rejection)
        #expect(abort.origin == .uncommittedHorizonRejectedBeforeRecorderMutation)
        #expect(abort.abandonedReadyQueueCutoff == 2)
        #expect(abort.abandonedHorizonQueueCutoff == nil)
        #expect(abort.abandonedHorizonTransactionRevision == nil)
        #expect(abort.abandonedHorizonTransactionIdentity == nil)
        #expect(abort.abandonedEvidenceQueueCutoff == 2)
        #expect(gate.phase == .abortQuarantined(abort))
        #expect(!gate.isTerminal)
        #expect(gate.permittedDrainUpperBound(firstPending: 3, pendingTail: 5) == nil)
        let resetAccepted = gate.resetForNewCaptureSession()
        #expect(!resetAccepted)

        await #expect(throws: PassiveCoreBluetoothObservationBoundaryMutationAttemptError.alreadyAttempted) {
            _ = try await horizon.recordBoundaryWithMutationOutcome(on: recorder)
        }
        #expect((await recorder.snapshot()).observationBoundaries.count == 1)
    }

    @Test("zero-H abort rejects equal-scalar rejection proof from another gate")
    @MainActor
    func foreignGateRejectionCannotAbortLocalHorizon() async throws {
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

        let horizonA = try await admittedHorizon(
            recorder: recorderA,
            fence: fenceA,
            gate: &gateA
        )
        _ = try await admittedHorizon(
            recorder: recorderB,
            fence: fenceB,
            gate: &gateB
        )
        let localB = try #require(gateB.activeTransaction)
        let rejectionA = try await rejectedBeforeHorizonMutation(
            admission: horizonA,
            recorder: recorderA,
            fence: fenceA
        )

        #expect(rejectionA.queueCutoff == localB.queueCutoff)
        #expect(rejectionA.transactionRevision == localB.revision)
        #expect(rejectionA.transactionIdentity != localB.identity)
        #expect(throws: PassiveCoreBluetoothObservationBoundaryQueueGate.StateError.staleTransaction) {
            _ = try gateB.abortUncommittedHorizon(after: rejectionA)
        }
        #expect(gateB.phase == .drainingHorizon(localB))
        #expect((await recorderB.snapshot()).observationBoundaries.count == 1)
    }

    @Test("zero-H quarantine retirement starts after durable Ready rather than attempted H")
    @MainActor
    func retirementUsesReadyAsFurthestDurableBoundary() async throws {
        let recorder = try PassiveCoreBluetoothCaptureRecorder(
            vehicleIdentity: es80,
            startedAt: Date(timeIntervalSince1970: 1)
        )
        let fence = PassiveCoreBluetoothArtifactAuthorityFence(authority: authority)
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let horizon = try await admittedHorizon(
            recorder: recorder,
            fence: fence,
            gate: &gate
        )
        let rejection = try await rejectedBeforeHorizonMutation(
            admission: horizon,
            recorder: recorder,
            fence: fence
        )
        let abort = try gate.abortUncommittedHorizon(after: rejection)
        let replacement = rejection.currentAuthority

        var pending = [
            PendingEvent(queueSequence: 3, authority: replacement),
            PendingEvent(queueSequence: 4, authority: replacement),
            PendingEvent(queueSequence: 5, authority: replacement)
        ]
        let retirement = try PassiveCoreBluetoothAbortedObservationQueueRetirement.retire(
            from: &pending,
            currentLastEnqueuedEventSequence: 5,
            currentSettledQueueSequence: 2,
            drainIsIdle: true,
            abortedGate: gate,
            identity: { .init(queueSequence: $0.queueSequence, authority: $0.authority) }
        )

        #expect(abort.abandonedEvidenceQueueCutoff == 2)
        #expect(retirement.abortReceipt == abort)
        #expect(retirement.validatedSettledQueueSequence == 2)
        #expect(retirement.validatedQueueTailSequence == 5)
        #expect(retirement.retiredPendingEvidenceCount == 3)
        #expect(pending.isEmpty)
        #expect((await recorder.snapshot()).observationBoundaries.count == 1)
        #expect(gate.phase == .abortQuarantined(abort))
    }
}
