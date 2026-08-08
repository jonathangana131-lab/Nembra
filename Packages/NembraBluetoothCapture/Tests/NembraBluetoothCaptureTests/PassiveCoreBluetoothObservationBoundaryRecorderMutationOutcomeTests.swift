import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Passive CoreBluetooth boundary recorder mutation outcome")
struct PassiveCoreBluetoothObservationBoundaryRecorderMutationOutcomeTests {
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

    @Test("successful fenced append reports recorded and leaves gate transaction for exact commit")
    @MainActor
    func successfulAppendReportsRecorded() async throws {
        let recorder = try PassiveCoreBluetoothCaptureRecorder(
            vehicleIdentity: es80,
            startedAt: Date(timeIntervalSince1970: 1)
        )
        let fence = PassiveCoreBluetoothArtifactAuthorityMutationFence(
            initialAuthority: authority
        )
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let ready = try PassiveCoreBluetoothObservationBoundaryTransactionDecision.captureAndBegin(
            kind: .finiteAcquisitionReady,
            queueCutoff: 0,
            processedThrough: 0,
            authorityFence: fence,
            gate: &gate
        )

        let outcome = try await ready.recordBoundaryWithMutationOutcome(on: recorder)
        #expect(outcome == .recorded)
        #expect(gate.activeTransaction?.authority == authority)
        #expect(gate.activeTransaction?.queueCutoff == 0)

        let session = await recorder.snapshot()
        #expect(session.observationBoundaries.count == 1)

        try ready.markBoundaryRecorded(
            on: &gate,
            lastProcessedQueueSequence: 0
        )
        #expect(gate.phase == .observing)
    }

    @Test("authority replacement issues genuine zero-mutation rejection proof and quarantines exact Ready")
    @MainActor
    func revokedReadyIssuesProofForUncommittedAbort() async throws {
        let recorder = try PassiveCoreBluetoothCaptureRecorder(
            vehicleIdentity: es80,
            startedAt: Date(timeIntervalSince1970: 1)
        )
        let fence = PassiveCoreBluetoothArtifactAuthorityMutationFence(
            initialAuthority: authority
        )
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let ready = try PassiveCoreBluetoothObservationBoundaryTransactionDecision.captureAndBegin(
            kind: .finiteAcquisitionReady,
            queueCutoff: 0,
            processedThrough: 0,
            authorityFence: fence,
            gate: &gate
        )
        let replacement = PassiveCoreBluetoothArtifactAuthorityContext(
            targetSessionGeneration: authority.targetSessionGeneration,
            authorityGeneration: authority.authorityGeneration + 1
        )
        try fence.replace(expectedCurrent: authority, with: replacement)

        let outcome = try await ready.recordBoundaryWithMutationOutcome(on: recorder)
        let rejection: PassiveCoreBluetoothObservationBoundaryRecorderMutationRejectionReceipt
        switch outcome {
        case .recorded:
            Issue.record("Revoked authority must not report a successful recorder mutation.")
            return
        case let .rejectedBeforeMutation(receipt):
            rejection = receipt
        }

        #expect(rejection.queueKind == .finiteAcquisitionReady)
        #expect(rejection.queueCutoff == 0)
        #expect(rejection.authority == authority)
        #expect(rejection.reason == .artifactAuthorityChangedBeforeMutation)

        let session = await recorder.snapshot()
        #expect(session.observationBoundaries.isEmpty)
        #expect(gate.activeTransaction?.authority == authority)
        #expect(gate.activeTransaction?.queueCutoff == 0)

        let abort = try gate.abortUncommittedReady(after: rejection)
        #expect(abort.origin == .uncommittedReadyRejectedBeforeRecorderMutation)
        #expect(abort.abandonedReadyAuthority == authority)
        #expect(abort.abandonedReadyQueueCutoff == 0)
        #expect(gate.phase == .abortQuarantined(abort))
        #expect(gate.permittedDrainUpperBound(firstPending: 1, pendingTail: 1) == nil)
    }

    @Test("rejection proof from another Ready cannot erase the current draining transaction")
    @MainActor
    func foreignRejectionProofFailsClosed() async throws {
        let recorder = try PassiveCoreBluetoothCaptureRecorder(
            vehicleIdentity: es80,
            startedAt: Date(timeIntervalSince1970: 1)
        )

        var firstGate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let firstFence = PassiveCoreBluetoothArtifactAuthorityMutationFence(
            initialAuthority: authority
        )
        let firstReady = try PassiveCoreBluetoothObservationBoundaryTransactionDecision.captureAndBegin(
            kind: .finiteAcquisitionReady,
            queueCutoff: 0,
            processedThrough: 0,
            authorityFence: firstFence,
            gate: &firstGate
        )
        try firstFence.replace(
            expectedCurrent: authority,
            with: .init(
                targetSessionGeneration: authority.targetSessionGeneration,
                authorityGeneration: authority.authorityGeneration + 1
            )
        )
        let firstOutcome = try await firstReady.recordBoundaryWithMutationOutcome(on: recorder)
        let rejection: PassiveCoreBluetoothObservationBoundaryRecorderMutationRejectionReceipt
        switch firstOutcome {
        case .recorded:
            Issue.record("Expected first Ready to be rejected before mutation.")
            return
        case let .rejectedBeforeMutation(receipt):
            rejection = receipt
        }

        var secondGate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let secondFence = PassiveCoreBluetoothArtifactAuthorityMutationFence(
            initialAuthority: authority
        )
        let secondReady = try PassiveCoreBluetoothObservationBoundaryTransactionDecision.captureAndBegin(
            kind: .finiteAcquisitionReady,
            queueCutoff: 1,
            processedThrough: 1,
            authorityFence: secondFence,
            gate: &secondGate
        )

        #expect(
            capturedMutationAbortStateError {
                try secondGate.abortUncommittedReady(after: rejection)
            } == .staleTransaction
        )
        #expect(secondGate.phase == .drainingReady(
            .init(
                boundaryKind: .finiteAcquisitionReady,
                queueCutoff: secondReady.queueCutoff,
                authority: secondReady.authority,
                revision: secondGate.activeTransaction?.revision ?? 0
            )
        ))
        #expect(secondGate.activeTransaction?.queueCutoff == 1)
        #expect(secondGate.activeTransaction?.authority == authority)
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
