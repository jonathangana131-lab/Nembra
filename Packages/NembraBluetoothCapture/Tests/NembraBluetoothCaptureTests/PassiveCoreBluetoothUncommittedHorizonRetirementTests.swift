import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Passive CoreBluetooth uncommitted Horizon retirement")
struct PassiveCoreBluetoothUncommittedHorizonRetirementTests {
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

    @Test("zero-H rejection retires from durable Ready rather than nonexistent Horizon")
    @MainActor
    func retirementStartsAfterReadyCutoff() async throws {
        let recorder = try PassiveCoreBluetoothCaptureRecorder(
            vehicleIdentity: es80,
            startedAt: Date(timeIntervalSince1970: 1)
        )
        let fence = PassiveCoreBluetoothArtifactAuthorityFence(authority: authority)
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()

        let readyAdmission = try PassiveCoreBluetoothObservationBoundaryTransactionDecision.beginReady(
            queueCutoff: 2,
            processedThrough: 2,
            authorityFence: fence,
            gate: &gate
        )
        let recordedReady = try await readyAdmission.recordBoundary(on: recorder)
        let committedReady = try recordedReady.markBoundaryRecorded(
            on: &gate,
            lastProcessedQueueSequence: 2
        )
        let horizon = try committedReady.beginHorizon(
            queueCutoff: 4,
            processedThrough: 4,
            gate: &gate
        )

        try fence.transition(from: authority, to: replacementAuthority)
        let outcome = try await horizon.recordBoundaryWithMutationOutcome(on: recorder)
        let rejection: PassiveCoreBluetoothObservationBoundaryTransactionDecision.HorizonRecorderMutationRejectionReceipt
        switch outcome {
        case .recorded:
            Issue.record("Revoked Horizon must not become durable evidence.")
            return
        case let .rejectedBeforeMutation(receipt):
            rejection = receipt
        }

        let abort = try gate.abortUncommittedHorizon(after: rejection)
        #expect(abort.abandonedReadyQueueCutoff == 2)
        #expect(abort.abandonedUnrecordedHorizonQueueCutoff == 4)
        #expect(abort.abandonedHorizonQueueCutoff == nil)
        #expect(abort.abandonedEvidenceQueueCutoff == 2)
        #expect((await recorder.snapshot()).observationBoundaries.count == 1)

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
}
