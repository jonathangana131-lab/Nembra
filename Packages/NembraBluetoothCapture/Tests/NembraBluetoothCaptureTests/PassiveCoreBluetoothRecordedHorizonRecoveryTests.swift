import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Passive CoreBluetooth recorded Horizon recovery")
struct PassiveCoreBluetoothRecordedHorizonRecoveryTests {
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
    private func readyAndHorizon(
        gate: inout PassiveCoreBluetoothObservationBoundaryQueueGate,
        fence: PassiveCoreBluetoothArtifactAuthorityFence,
        recorder: PassiveCoreBluetoothCaptureRecorder,
        readyCutoff: UInt64 = 2,
        horizonCutoff: UInt64 = 4
    ) async throws -> (
        epoch: PassiveCoreBluetoothObservationBoundaryTransactionDecision.CommittedReadyEpoch,
        admission: PassiveCoreBluetoothObservationBoundaryTransactionDecision.HorizonAdmission,
        recorded: PassiveCoreBluetoothObservationBoundaryTransactionDecision.RecordedHorizonBoundary
    ) {
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
        let admission = try epoch.beginHorizon(
            queueCutoff: horizonCutoff,
            processedThrough: readyCutoff,
            gate: &gate
        )
        let recorded = try await admission.recordBoundary(on: recorder)
        return (epoch, admission, recorded)
    }

    @Test("durable Horizon plus failed queue commit quarantines exact epoch without fabricating terminal freeze")
    @MainActor
    func recordedHorizonCommitFailureQuarantinesIncompleteEpoch() async throws {
        let recorder = try PassiveCoreBluetoothCaptureRecorder(
            vehicleIdentity: es80,
            startedAt: Date(timeIntervalSince1970: 1)
        )
        let fence = PassiveCoreBluetoothArtifactAuthorityFence(authority: authority)
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let fixture = try await readyAndHorizon(gate: &gate, fence: fence, recorder: recorder)
        let active = try #require(gate.activeTransaction)

        #expect(active.identity == fixture.recorded.transactionIdentity)
        #expect(active.revision == fixture.recorded.transactionRevision)
        #expect((await recorder.snapshot()).observationBoundaries.count == 2)

        let replacement = PassiveCoreBluetoothArtifactAuthorityContext(
            targetSessionGeneration: authority.targetSessionGeneration,
            authorityGeneration: authority.authorityGeneration + 1
        )
        try fence.transition(from: authority, to: replacement)

        #expect(throws: PassiveCoreBluetoothObservationBoundaryQueueGate.StateError.authorityChanged) {
            _ = try fixture.recorded.markBoundaryRecorded(
                on: &gate,
                lastProcessedQueueSequence: fixture.recorded.queueCutoff
            )
        }
        #expect(gate.phase == .drainingHorizon(active))
        #expect(!gate.isTerminal)

        let abort = try gate.abortRecordedHorizonBeforeGateCommit(fixture.recorded)
        #expect(abort.origin == .recordedHorizonInvalidatedBeforeGateCommit)
        #expect(abort.abandonedReadyTransactionIdentity == fixture.epoch.transactionIdentity)
        #expect(abort.abandonedHorizonQueueCutoff == fixture.recorded.queueCutoff)
        #expect(abort.abandonedHorizonTransactionRevision == fixture.recorded.transactionRevision)
        #expect(abort.abandonedHorizonTransactionIdentity == fixture.recorded.transactionIdentity)
        #expect(abort.abandonedEvidenceQueueCutoff == fixture.recorded.queueCutoff)
        #expect(gate.phase == .abortQuarantined(abort))
        #expect(!gate.isTerminal)
        #expect(gate.permittedDrainUpperBound(firstPending: 5, pendingTail: 5) == nil)
        let resetWhileQuarantined = gate.resetForNewCaptureSession()
        #expect(!resetWhileQuarantined)

        await #expect(throws: PassiveCoreBluetoothObservationBoundaryMutationAttemptError.alreadyAttempted) {
            _ = try await fixture.admission.recordBoundary(on: recorder)
        }
        #expect((await recorder.snapshot()).observationBoundaries.count == 2)

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
        #expect(gate.phase == .abortQuarantined(abort))
    }

    @Test("recorded Horizon retirement requires chronology settled through H, not merely Ready")
    @MainActor
    func retirementRequiresSettledHorizonCutoff() async throws {
        let recorder = try PassiveCoreBluetoothCaptureRecorder(
            vehicleIdentity: es80,
            startedAt: Date(timeIntervalSince1970: 1)
        )
        let fence = PassiveCoreBluetoothArtifactAuthorityFence(authority: authority)
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let fixture = try await readyAndHorizon(gate: &gate, fence: fence, recorder: recorder)
        let abort = try gate.abortRecordedHorizonBeforeGateCommit(fixture.recorded)

        var pending = [
            PendingEvent(queueSequence: 3, authority: authority),
            PendingEvent(queueSequence: 4, authority: authority),
            PendingEvent(queueSequence: 5, authority: authority)
        ]
        let original = pending
        #expect(throws: PassiveCoreBluetoothAbortedObservationQueueRetirement.StateError.readyPrefixNotSettled(settled: 2, readyCutoff: 4)) {
            _ = try PassiveCoreBluetoothAbortedObservationQueueRetirement.retire(
                from: &pending,
                currentLastEnqueuedEventSequence: 5,
                currentSettledQueueSequence: 2,
                drainIsIdle: true,
                abortedGate: gate,
                identity: { .init(queueSequence: $0.queueSequence, authority: $0.authority) }
            )
        }
        #expect(pending == original)
        #expect(abort.abandonedEvidenceQueueCutoff == 4)
    }

    @Test("equal-scalar foreign recorded Horizon cannot quarantine another gate")
    @MainActor
    func foreignRecordedHorizonFailsExactIdentity() async throws {
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
        let a = try await readyAndHorizon(gate: &gateA, fence: fenceA, recorder: recorderA)
        let b = try await readyAndHorizon(gate: &gateB, fence: fenceB, recorder: recorderB)

        #expect(a.recorded.authority == b.recorded.authority)
        #expect(a.recorded.queueCutoff == b.recorded.queueCutoff)
        #expect(a.recorded.transactionRevision == b.recorded.transactionRevision)
        #expect(a.recorded.transactionIdentity != b.recorded.transactionIdentity)

        #expect(throws: PassiveCoreBluetoothObservationBoundaryQueueGate.StateError.staleTransaction) {
            _ = try gateB.abortRecordedHorizonBeforeGateCommit(a.recorded)
        }
        #expect(gateB.activeTransaction?.identity == b.recorded.transactionIdentity)
    }

    @Test("committed Horizon can quarantine after pre-freeze authority loss without inventing terminal success")
    @MainActor
    func committedHorizonPreFreezeFailureQuarantinesIncompleteArtifact() async throws {
        let recorder = try PassiveCoreBluetoothCaptureRecorder(
            vehicleIdentity: es80,
            startedAt: Date(timeIntervalSince1970: 1)
        )
        let fence = PassiveCoreBluetoothArtifactAuthorityFence(authority: authority)
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let fixture = try await readyAndHorizon(gate: &gate, fence: fence, recorder: recorder)
        let committed = try fixture.recorded.markBoundaryRecorded(
            on: &gate,
            lastProcessedQueueSequence: fixture.recorded.queueCutoff
        )
        let active = try #require(gate.activeTransaction)

        #expect(active.identity == committed.transactionIdentity)
        #expect(active.revision == committed.transactionRevision)
        #expect(gate.phase == .horizonBoundaryRecorded(active))
        #expect((await recorder.snapshot()).observationBoundaries.count == 2)

        let replacement = PassiveCoreBluetoothArtifactAuthorityContext(
            targetSessionGeneration: authority.targetSessionGeneration,
            authorityGeneration: authority.authorityGeneration + 1
        )
        try fence.transition(from: authority, to: replacement)

        #expect(throws: PassiveCoreBluetoothObservationBoundaryQueueGate.StateError.authorityChanged) {
            try committed.completeHorizonArtifactFreeze(on: &gate)
        }
        #expect(gate.phase == .horizonBoundaryRecorded(active))
        #expect(!gate.isTerminal)

        let abort = try gate.abortCommittedHorizonBeforeArtifactFreeze(committed)
        #expect(abort.origin == .committedHorizonInvalidatedBeforeArtifactFreeze)
        #expect(abort.abandonedReadyQueueCutoff == fixture.epoch.queueCutoff)
        #expect(abort.abandonedEvidenceQueueCutoff == committed.queueCutoff)
        #expect(abort.abandonedHorizonQueueCutoff == committed.queueCutoff)
        #expect(abort.abandonedHorizonTransactionRevision == committed.transactionRevision)
        #expect(abort.abandonedHorizonTransactionIdentity == committed.transactionIdentity)
        #expect(abort.abandonedUnrecordedHorizonQueueCutoff == nil)
        #expect(gate.phase == .abortQuarantined(abort))
        #expect(!gate.isTerminal)

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
    }

    @Test("equal-scalar foreign committed Horizon cannot quarantine another pre-freeze gate")
    @MainActor
    func foreignCommittedHorizonFailsExactIdentity() async throws {
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
        let a = try await readyAndHorizon(gate: &gateA, fence: fenceA, recorder: recorderA)
        let b = try await readyAndHorizon(gate: &gateB, fence: fenceB, recorder: recorderB)
        let committedA = try a.recorded.markBoundaryRecorded(
            on: &gateA,
            lastProcessedQueueSequence: a.recorded.queueCutoff
        )
        let committedB = try b.recorded.markBoundaryRecorded(
            on: &gateB,
            lastProcessedQueueSequence: b.recorded.queueCutoff
        )

        #expect(committedA.authority == committedB.authority)
        #expect(committedA.queueCutoff == committedB.queueCutoff)
        #expect(committedA.transactionRevision == committedB.transactionRevision)
        #expect(committedA.transactionIdentity != committedB.transactionIdentity)

        #expect(throws: PassiveCoreBluetoothObservationBoundaryQueueGate.StateError.staleTransaction) {
            _ = try gateB.abortCommittedHorizonBeforeArtifactFreeze(committedA)
        }
        #expect(gateB.activeTransaction?.identity == committedB.transactionIdentity)
        #expect(!gateB.isAbortQuarantined)
    }

    @Test("unchanged authority still commits Horizon and reaches terminal only after explicit freeze")
    @MainActor
    func normalHorizonCommitAndFreezeRemainsAvailable() async throws {
        let recorder = try PassiveCoreBluetoothCaptureRecorder(
            vehicleIdentity: es80,
            startedAt: Date(timeIntervalSince1970: 1)
        )
        let fence = PassiveCoreBluetoothArtifactAuthorityFence(authority: authority)
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let fixture = try await readyAndHorizon(gate: &gate, fence: fence, recorder: recorder)

        let committed = try fixture.recorded.markBoundaryRecorded(
            on: &gate,
            lastProcessedQueueSequence: fixture.recorded.queueCutoff
        )
        #expect(!gate.isTerminal)
        try committed.completeHorizonArtifactFreeze(on: &gate)
        #expect(gate.isTerminal)
    }
}
