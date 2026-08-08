import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Passive CoreBluetooth boundary recorder mutation outcome")
struct PassiveCoreBluetoothObservationBoundaryRecorderMutationOutcomeTests {
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

    @Test("successful canonical fenced append reports recorded token and commits exact Ready")
    @MainActor
    func successfulAppendReportsRecorded() async throws {
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

        let outcome = try await admission.recordBoundaryWithMutationOutcome(on: recorder)
        let recorded: PassiveCoreBluetoothObservationBoundaryTransactionDecision.RecordedReadyBoundary
        switch outcome {
        case let .recorded(token):
            recorded = token
        case .rejectedBeforeMutation:
            Issue.record("Current canonical authority must permit the Ready recorder mutation.")
            return
        }

        #expect(gate.activeTransaction?.authority == authority)
        #expect(gate.activeTransaction?.queueCutoff == 0)
        let session = await recorder.snapshot()
        #expect(session.observationBoundaries.count == 1)

        let epoch = try recorded.markBoundaryRecorded(
            on: &gate,
            lastProcessedQueueSequence: 0
        )
        #expect(gate.phase == .observing)
        #expect(epoch.authority == authority)
        #expect(epoch.transactionIdentity != UUID())
    }

    @Test("canonical authority revocation issues genuine zero-mutation proof then requires quarantine retirement")
    @MainActor
    func revokedReadyIssuesProofForUncommittedAbort() async throws {
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
        let activeBefore = try #require(gate.activeTransaction)
        let replacement = PassiveCoreBluetoothArtifactAuthorityContext(
            targetSessionGeneration: authority.targetSessionGeneration,
            authorityGeneration: authority.authorityGeneration + 1
        )
        try fence.transition(from: authority, to: replacement)

        let outcome = try await admission.recordBoundaryWithMutationOutcome(on: recorder)
        let rejection: PassiveCoreBluetoothObservationBoundaryTransactionDecision.ReadyRecorderMutationRejectionReceipt
        switch outcome {
        case .recorded:
            Issue.record("Revoked authority must not report a successful recorder mutation.")
            return
        case let .rejectedBeforeMutation(receipt):
            rejection = receipt
        }

        #expect(rejection.queueCutoff == 0)
        #expect(rejection.authority == authority)
        #expect(rejection.transactionRevision == activeBefore.revision)
        #expect(rejection.transactionIdentity == activeBefore.identity)
        #expect(rejection.currentAuthority == replacement)

        let session = await recorder.snapshot()
        #expect(session.observationBoundaries.isEmpty)
        #expect(gate.phase == .drainingReady(activeBefore))

        let abort = try gate.abortUncommittedReady(after: rejection)
        #expect(abort.origin == .uncommittedReadyRejectedBeforeRecorderMutation)
        #expect(abort.abandonedReadyAuthority == authority)
        #expect(abort.abandonedReadyQueueCutoff == 0)
        #expect(abort.abandonedReadyTransactionRevision == activeBefore.revision)
        #expect(gate.phase == .abortQuarantined(abort))
        #expect(gate.permittedDrainUpperBound(firstPending: 1, pendingTail: 1) == nil)

        var pending = [
            PendingEvent(queueSequence: 1, authority: replacement),
        ]
        let retirement = try PassiveCoreBluetoothAbortedObservationQueueRetirement.retire(
            from: &pending,
            currentLastEnqueuedEventSequence: 1,
            currentSettledQueueSequence: 0,
            drainIsIdle: true,
            abortedGate: gate,
            identity: {
                .init(queueSequence: $0.queueSequence, authority: $0.authority)
            }
        )
        #expect(pending.isEmpty)
        #expect(retirement.abortReceipt.origin == .uncommittedReadyRejectedBeforeRecorderMutation)

        let freshGeneration = authority.targetSessionGeneration + 1
        try gate.completeAbortedObservationRecovery(
            retirement,
            currentLastEnqueuedEventSequence: 1,
            freshTargetSessionGeneration: freshGeneration
        )
        #expect(gate.phase == .awaitingReady)

        let freshAuthority = PassiveCoreBluetoothArtifactAuthorityContext(
            targetSessionGeneration: freshGeneration,
            authorityGeneration: 1
        )
        let next = try gate.begin(
            .finiteAcquisitionReady,
            through: 2,
            authority: freshAuthority
        )
        #expect(gate.phase == .drainingReady(next))
    }

    @Test("genuine rejection proof from structurally identical foreign gate cannot erase current Ready")
    @MainActor
    func foreignRejectionProofFailsClosed() async throws {
        let firstRecorder = try PassiveCoreBluetoothCaptureRecorder(
            vehicleIdentity: es80,
            startedAt: Date(timeIntervalSince1970: 1)
        )

        var firstGate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let firstFence = PassiveCoreBluetoothArtifactAuthorityFence(authority: authority)
        let firstAdmission = try PassiveCoreBluetoothObservationBoundaryTransactionDecision.beginReady(
            queueCutoff: 0,
            processedThrough: 0,
            authorityFence: firstFence,
            gate: &firstGate
        )
        let replacement = PassiveCoreBluetoothArtifactAuthorityContext(
            targetSessionGeneration: authority.targetSessionGeneration,
            authorityGeneration: authority.authorityGeneration + 1
        )
        try firstFence.transition(from: authority, to: replacement)
        let firstOutcome = try await firstAdmission.recordBoundaryWithMutationOutcome(on: firstRecorder)
        let rejection: PassiveCoreBluetoothObservationBoundaryTransactionDecision.ReadyRecorderMutationRejectionReceipt
        switch firstOutcome {
        case .recorded:
            Issue.record("Expected first Ready to be rejected before mutation.")
            return
        case let .rejectedBeforeMutation(receipt):
            rejection = receipt
        }

        var secondGate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let secondFence = PassiveCoreBluetoothArtifactAuthorityFence(authority: authority)
        _ = try PassiveCoreBluetoothObservationBoundaryTransactionDecision.beginReady(
            queueCutoff: 0,
            processedThrough: 0,
            authorityFence: secondFence,
            gate: &secondGate
        )
        let activeBefore = try #require(secondGate.activeTransaction)
        #expect(activeBefore.authority == rejection.authority)
        #expect(activeBefore.queueCutoff == rejection.queueCutoff)
        #expect(activeBefore.revision == rejection.transactionRevision)
        #expect(activeBefore.identity != rejection.transactionIdentity)

        #expect(
            capturedMutationAbortStateError {
                try secondGate.abortUncommittedReady(after: rejection)
            } == .staleTransaction
        )
        #expect(secondGate.phase == .drainingReady(activeBefore))
        #expect(secondGate.activeTransaction == activeBefore)
    }
}

private func capturedMutationAbortStateError<T>(
    _ operation: () throws -> T
) -> PassiveCoreBluetoothObservationBoundaryQueueGate.StateError? {
    do {
        _ = try operation()
        return nil
    } catch let error as PassiveCoreBluetoothObservationBoundaryQueueGate.StateError {
        return error
    } catch {
        return nil
    }
}
