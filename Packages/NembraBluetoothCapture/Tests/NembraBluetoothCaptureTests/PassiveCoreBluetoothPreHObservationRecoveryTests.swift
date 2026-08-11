import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Passive CoreBluetooth pre-H observation recovery")
struct PassiveCoreBluetoothPreHObservationRecoveryTests {
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
    private func committedReady(
        gate: inout PassiveCoreBluetoothObservationBoundaryQueueGate,
        cutoff: UInt64 = 2
    ) async throws -> (
        recorder: PassiveCoreBluetoothCaptureRecorder,
        fence: PassiveCoreBluetoothArtifactAuthorityFence,
        epoch: PassiveCoreBluetoothObservationBoundaryTransactionDecision.CommittedReadyEpoch
    ) {
        let recorder = try PassiveCoreBluetoothCaptureRecorder(
            vehicleIdentity: es80,
            startedAt: Date(timeIntervalSince1970: 1)
        )
        let fence = PassiveCoreBluetoothArtifactAuthorityFence(authority: authority)
        let admission = try PassiveCoreBluetoothObservationBoundaryTransactionDecision.beginReady(
            queueCutoff: cutoff,
            processedThrough: cutoff,
            authorityFence: fence,
            gate: &gate
        )
        let recorded = try await admission.recordBoundary(on: recorder)
        let epoch = try recorded.markBoundaryRecorded(
            on: &gate,
            lastProcessedQueueSequence: cutoff
        )
        return (recorder, fence, epoch)
    }

    @Test("committed Ready abort preserves exact identity and raw retirement cannot reopen lifecycle")
    @MainActor
    func committedReadyAbortRemainsQuarantinedAfterRawRetirement() async throws {
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let fixture = try await committedReady(gate: &gate)
        let abort = try gate.abortObservationEpoch(fixture.epoch)

        #expect(abort.origin == .committedReadyInvalidated)
        #expect(abort.abandonedReadyQueueCutoff == fixture.epoch.queueCutoff)
        #expect(abort.abandonedReadyTransactionRevision == fixture.epoch.transactionRevision)
        #expect(abort.abandonedReadyTransactionIdentity == fixture.epoch.transactionIdentity)
        #expect(gate.phase == .abortQuarantined(abort))
        #expect(gate.permittedDrainUpperBound(firstPending: 3, pendingTail: 3) == nil)
        let resetWhileQuarantined = gate.resetForNewCaptureSession()
        #expect(!resetWhileQuarantined)

        var pending = [
            PendingEvent(
                queueSequence: 3,
                authority: .init(
                    targetSessionGeneration: authority.targetSessionGeneration,
                    authorityGeneration: authority.authorityGeneration + 1
                )
            )
        ]
        let retirement = try PassiveCoreBluetoothAbortedObservationQueueRetirement.retire(
            from: &pending,
            currentLastEnqueuedEventSequence: 3,
            currentSettledQueueSequence: 2,
            drainIsIdle: true,
            abortedGate: gate,
            identity: { .init(queueSequence: $0.queueSequence, authority: $0.authority) }
        )
        #expect(pending.isEmpty)
        #expect(retirement.abortReceipt.abandonedReadyTransactionIdentity == fixture.epoch.transactionIdentity)
        #expect(retirement.validatedSettledQueueSequence == 2)
        #expect(retirement.validatedQueueTailSequence == 3)
        #expect(retirement.retiredEvidenceCount == 1)

        // Raw retirement resolves no lifecycle authority by itself. The gate must
        // remain hard-quarantined until #450/equivalent global resolved-frontier
        // authority is composed into a successor recovery admission.
        #expect(gate.phase == .abortQuarantined(abort))
        #expect(gate.permittedDrainUpperBound(firstPending: 4, pendingTail: 4) == nil)
        let resetAfterRetirement = gate.resetForNewCaptureSession()
        #expect(!resetAfterRetirement)
        #expect(throws: PassiveCoreBluetoothObservationBoundaryQueueGate.StateError.invalidTransition) {
            _ = try gate.begin(
                .finiteAcquisitionReady,
                through: 4,
                authority: .init(targetSessionGeneration: 8, authorityGeneration: 1)
            )
        }
        #expect(throws: PassiveCoreBluetoothObservationBoundaryQueueGate.StateError.invalidTransition) {
            _ = try fixture.epoch.beginHorizon(
                queueCutoff: 4,
                processedThrough: 3,
                gate: &gate
            )
        }
        #expect(gate.phase == .abortQuarantined(abort))
    }

    @Test("canonical fence rejection proves zero Ready mutation and consumes one-shot admission")
    @MainActor
    func revokedUncommittedReadyUsesOnlyProducerRejectionProof() async throws {
        let recorder = try PassiveCoreBluetoothCaptureRecorder(
            vehicleIdentity: es80,
            startedAt: Date(timeIntervalSince1970: 1)
        )
        let fence = PassiveCoreBluetoothArtifactAuthorityFence(authority: authority)
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let admission = try PassiveCoreBluetoothObservationBoundaryTransactionDecision.beginReady(
            queueCutoff: 0,
            processedThrough: 0,
            authorityFence: fence,
            gate: &gate
        )
        let active = try #require(gate.activeTransaction)
        let replacement = PassiveCoreBluetoothArtifactAuthorityContext(
            targetSessionGeneration: 7,
            authorityGeneration: 12
        )
        try fence.transition(from: authority, to: replacement)

        let outcome = try await admission.recordBoundaryWithMutationOutcome(on: recorder)
        let rejection: PassiveCoreBluetoothObservationBoundaryTransactionDecision.ReadyRecorderMutationRejectionReceipt
        switch outcome {
        case .recorded:
            Issue.record("Revoked Ready must not append a boundary.")
            return
        case let .rejectedBeforeMutation(receipt):
            rejection = receipt
        }

        #expect(rejection.transactionRevision == active.revision)
        #expect(rejection.transactionIdentity == active.identity)
        #expect(rejection.currentAuthority == replacement)
        #expect((await recorder.snapshot()).observationBoundaries.isEmpty)
        #expect(gate.phase == .drainingReady(active))

        let abort = try gate.abortUncommittedReady(after: rejection)
        #expect(abort.origin == .uncommittedReadyRejectedBeforeRecorderMutation)
        #expect(abort.abandonedReadyTransactionIdentity == active.identity)
        #expect(gate.phase == .abortQuarantined(abort))

        await #expect(throws: PassiveCoreBluetoothObservationBoundaryMutationAttemptError.alreadyAttempted) {
            _ = try await admission.recordBoundary(on: recorder)
        }
        #expect((await recorder.snapshot()).observationBoundaries.isEmpty)
    }

    @Test("successful Ready append may quarantine before gate commit without pretending zero mutation")
    @MainActor
    func recordedReadyBeforeCommitHasDistinctAbortOrigin() async throws {
        let recorder = try PassiveCoreBluetoothCaptureRecorder(
            vehicleIdentity: es80,
            startedAt: Date(timeIntervalSince1970: 1)
        )
        let fence = PassiveCoreBluetoothArtifactAuthorityFence(authority: authority)
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let admission = try PassiveCoreBluetoothObservationBoundaryTransactionDecision.beginReady(
            queueCutoff: 0,
            processedThrough: 0,
            authorityFence: fence,
            gate: &gate
        )
        let recorded = try await admission.recordBoundary(on: recorder)
        let active = try #require(gate.activeTransaction)
        #expect((await recorder.snapshot()).observationBoundaries.count == 1)
        #expect(gate.phase == .drainingReady(active))

        let abort = try gate.abortRecordedReadyBeforeGateCommit(recorded)
        #expect(abort.origin == .recordedReadyInvalidatedBeforeGateCommit)
        #expect(abort.abandonedReadyTransactionIdentity == recorded.transactionIdentity)
        #expect(gate.phase == .abortQuarantined(abort))
        #expect((await recorder.snapshot()).observationBoundaries.count == 1)
    }

    @Test("recorded Ready token from equal-scalar foreign gate cannot abort current gate")
    @MainActor
    func foreignRecordedReadyTokenFailsExactIdentity() async throws {
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

        let admissionA = try PassiveCoreBluetoothObservationBoundaryTransactionDecision.beginReady(
            queueCutoff: 0,
            processedThrough: 0,
            authorityFence: fenceA,
            gate: &gateA
        )
        let admissionB = try PassiveCoreBluetoothObservationBoundaryTransactionDecision.beginReady(
            queueCutoff: 0,
            processedThrough: 0,
            authorityFence: fenceB,
            gate: &gateB
        )
        let recordedA = try await admissionA.recordBoundary(on: recorderA)
        let recordedB = try await admissionB.recordBoundary(on: recorderB)
        #expect(recordedA.authority == recordedB.authority)
        #expect(recordedA.queueCutoff == recordedB.queueCutoff)
        #expect(recordedA.transactionRevision == recordedB.transactionRevision)
        #expect(recordedA.transactionIdentity != recordedB.transactionIdentity)

        #expect(throws: PassiveCoreBluetoothObservationBoundaryQueueGate.StateError.staleTransaction) {
            _ = try gateB.abortRecordedReadyBeforeGateCommit(recordedA)
        }
        #expect(gateB.activeTransaction?.identity == recordedB.transactionIdentity)
    }

    @Test("CommittedReadyEpoch cannot open Horizon on a structurally identical foreign gate")
    @MainActor
    func foreignCommittedEpochCannotOpenHorizon() async throws {
        var gateA = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let fixtureA = try await committedReady(gate: &gateA)
        var gateB = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let fixtureB = try await committedReady(gate: &gateB)
        #expect(fixtureA.epoch.authority == fixtureB.epoch.authority)
        #expect(fixtureA.epoch.queueCutoff == fixtureB.epoch.queueCutoff)
        #expect(fixtureA.epoch.transactionRevision == fixtureB.epoch.transactionRevision)
        #expect(fixtureA.epoch.transactionIdentity != fixtureB.epoch.transactionIdentity)

        #expect(throws: PassiveCoreBluetoothObservationBoundaryQueueGate.StateError.staleTransaction) {
            _ = try fixtureA.epoch.beginHorizon(
                queueCutoff: 3,
                processedThrough: 2,
                gate: &gateB
            )
        }
        #expect(gateB.phase == .observing)
        _ = try fixtureB.epoch.beginHorizon(
            queueCutoff: 3,
            processedThrough: 2,
            gate: &gateB
        )
    }

    @Test("retirement fails atomically on drain activity, queue gaps, or foreign target-session evidence")
    @MainActor
    func retirementAdversarialFailuresPreserveQueue() async throws {
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let fixture = try await committedReady(gate: &gate)
        _ = try gate.abortObservationEpoch(fixture.epoch)

        var activeDrainPending = [PendingEvent(queueSequence: 3, authority: authority)]
        let activeOriginal = activeDrainPending
        #expect(throws: PassiveCoreBluetoothAbortedObservationQueueRetirement.StateError.eventDrainStillActive) {
            _ = try PassiveCoreBluetoothAbortedObservationQueueRetirement.retire(
                from: &activeDrainPending,
                currentLastEnqueuedEventSequence: 3,
                currentSettledQueueSequence: 2,
                drainIsIdle: false,
                abortedGate: gate,
                identity: { .init(queueSequence: $0.queueSequence, authority: $0.authority) }
            )
        }
        #expect(activeDrainPending == activeOriginal)

        var gapPending = [PendingEvent(queueSequence: 4, authority: authority)]
        let gapOriginal = gapPending
        #expect(throws: PassiveCoreBluetoothAbortedObservationQueueRetirement.StateError.nonContiguousQueueSequence(expected: 3, actual: 4)) {
            _ = try PassiveCoreBluetoothAbortedObservationQueueRetirement.retire(
                from: &gapPending,
                currentLastEnqueuedEventSequence: 4,
                currentSettledQueueSequence: 2,
                drainIsIdle: true,
                abortedGate: gate,
                identity: { .init(queueSequence: $0.queueSequence, authority: $0.authority) }
            )
        }
        #expect(gapPending == gapOriginal)

        var foreignPending = [
            PendingEvent(
                queueSequence: 3,
                authority: .init(targetSessionGeneration: 8, authorityGeneration: 1)
            )
        ]
        let foreignOriginal = foreignPending
        #expect(throws: PassiveCoreBluetoothAbortedObservationQueueRetirement.StateError.foreignTargetSessionPending(expected: 7, actual: 8)) {
            _ = try PassiveCoreBluetoothAbortedObservationQueueRetirement.retire(
                from: &foreignPending,
                currentLastEnqueuedEventSequence: 3,
                currentSettledQueueSequence: 2,
                drainIsIdle: true,
                abortedGate: gate,
                identity: { .init(queueSequence: $0.queueSequence, authority: $0.authority) }
            )
        }
        #expect(foreignPending == foreignOriginal)
    }
}
