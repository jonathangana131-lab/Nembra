import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Passive CoreBluetooth observation-boundary pre-H abort")
struct PassiveCoreBluetoothObservationBoundaryQueueGateAbortTests {
    private struct PendingEvent: Equatable {
        let queueSequence: UInt64
        let authority: PassiveCoreBluetoothArtifactAuthorityContext
    }

    private struct CommittedFixture {
        let recorder: PassiveCoreBluetoothCaptureRecorder
        let epoch: PassiveCoreBluetoothObservationBoundaryTransactionDecision.CommittedReadyEpoch
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
        on gate: inout PassiveCoreBluetoothObservationBoundaryQueueGate,
        cutoff: UInt64 = 4
    ) async throws -> CommittedFixture {
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
        return CommittedFixture(recorder: recorder, epoch: epoch)
    }

    @MainActor
    private func retireCommittedAbort(
        gate: inout PassiveCoreBluetoothObservationBoundaryQueueGate,
        fixture: CommittedFixture,
        pendingTail: UInt64 = 5
    ) throws -> PassiveCoreBluetoothAbortedObservationQueueRetirement.Receipt {
        _ = try gate.abortObservationEpoch(fixture.epoch)

        var pending: [PendingEvent] = []
        if pendingTail > fixture.epoch.queueCutoff {
            for sequence in (fixture.epoch.queueCutoff + 1)...pendingTail {
                pending.append(
                    PendingEvent(
                        queueSequence: sequence,
                        authority: .init(
                            targetSessionGeneration: fixture.epoch.authority.targetSessionGeneration,
                            authorityGeneration: fixture.epoch.authority.authorityGeneration + sequence
                        )
                    )
                )
            }
        }

        return try PassiveCoreBluetoothAbortedObservationQueueRetirement.retire(
            from: &pending,
            currentLastEnqueuedEventSequence: pendingTail,
            currentSettledQueueSequence: fixture.epoch.queueCutoff,
            drainIsIdle: true,
            abortedGate: gate,
            identity: {
                .init(queueSequence: $0.queueSequence, authority: $0.authority)
            }
        )
    }

    @Test("committed Ready abort quarantines draining until queue retirement + exact fresh session binding")
    @MainActor
    func committedAbortRequiresRetirementBeforeFreshReady() async throws {
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let fixture = try await committedReady(on: &gate)

        let abort = try gate.abortObservationEpoch(fixture.epoch)
        #expect(abort.abandonedReadyAuthority == fixture.epoch.authority)
        #expect(abort.abandonedReadyQueueCutoff == fixture.epoch.queueCutoff)
        #expect(abort.abandonedReadyTransactionRevision == fixture.epoch.transactionRevision)
        #expect(abort.abandonedTargetSessionGeneration == authority.targetSessionGeneration)
        #expect(abort.origin == .committedReadyInvalidated)
        #expect(gate.phase == .abortQuarantined(abort))
        #expect(gate.isAbortQuarantined)
        #expect(gate.permittedDrainUpperBound(firstPending: 5, pendingTail: 9) == nil)
        #expect(gate.resetForNewCaptureSession() == false)

        let freshAuthority = PassiveCoreBluetoothArtifactAuthorityContext(
            targetSessionGeneration: authority.targetSessionGeneration + 1,
            authorityGeneration: 1
        )
        #expect(
            capturedAbortStateError {
                try gate.begin(
                    .finiteAcquisitionReady,
                    through: 5,
                    authority: freshAuthority
                )
            } == .invalidTransition
        )
        #expect(gate.phase == .abortQuarantined(abort))

        var pending = [
            PendingEvent(
                queueSequence: 5,
                authority: .init(
                    targetSessionGeneration: authority.targetSessionGeneration,
                    authorityGeneration: authority.authorityGeneration + 1
                )
            ),
            PendingEvent(
                queueSequence: 6,
                authority: .init(
                    targetSessionGeneration: authority.targetSessionGeneration,
                    authorityGeneration: authority.authorityGeneration + 2
                )
            ),
        ]
        let retirement = try PassiveCoreBluetoothAbortedObservationQueueRetirement.retire(
            from: &pending,
            currentLastEnqueuedEventSequence: 6,
            currentSettledQueueSequence: 4,
            drainIsIdle: true,
            abortedGate: gate,
            identity: {
                .init(queueSequence: $0.queueSequence, authority: $0.authority)
            }
        )
        #expect(pending.isEmpty)
        #expect(retirement.abortReceipt == abort)
        #expect(retirement.retiredEvidenceCount == 2)
        #expect(retirement.retainedPendingEvidenceCount == 0)

        try gate.completeAbortedObservationRecovery(
            retirement,
            currentLastEnqueuedEventSequence: 6,
            freshTargetSessionGeneration: freshAuthority.targetSessionGeneration
        )
        #expect(gate.phase == .awaitingReady)
        #expect(!gate.isAbortQuarantined)

        let sameSessionNewAuthority = PassiveCoreBluetoothArtifactAuthorityContext(
            targetSessionGeneration: authority.targetSessionGeneration,
            authorityGeneration: authority.authorityGeneration + 3
        )
        #expect(
            capturedAbortStateError {
                try gate.begin(
                    .finiteAcquisitionReady,
                    through: 7,
                    authority: sameSessionNewAuthority
                )
            } == .freshTargetSessionRequired
        )

        let wrongLaterSession = PassiveCoreBluetoothArtifactAuthorityContext(
            targetSessionGeneration: freshAuthority.targetSessionGeneration + 1,
            authorityGeneration: 1
        )
        #expect(
            capturedAbortStateError {
                try gate.begin(
                    .finiteAcquisitionReady,
                    through: 7,
                    authority: wrongLaterSession
                )
            } == .freshTargetSessionRequired
        )

        let freshReady = try gate.begin(
            .finiteAcquisitionReady,
            through: 7,
            authority: freshAuthority
        )
        #expect(freshReady.authority == freshAuthority)
        #expect(freshReady.revision > fixture.epoch.transactionRevision)
        #expect(gate.phase == .drainingReady(freshReady))
    }

    @Test("normal reset cannot erase abort quarantine or exact fresh-session binding")
    @MainActor
    func resetDoesNotEraseRecoveryFences() async throws {
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let fixture = try await committedReady(on: &gate)
        let retirement = try retireCommittedAbort(
            gate: &gate,
            fixture: fixture,
            pendingTail: fixture.epoch.queueCutoff
        )

        #expect(gate.resetForNewCaptureSession() == false)
        #expect(gate.isAbortQuarantined)

        let freshGeneration = authority.targetSessionGeneration + 1
        try gate.completeAbortedObservationRecovery(
            retirement,
            currentLastEnqueuedEventSequence: fixture.epoch.queueCutoff,
            freshTargetSessionGeneration: freshGeneration
        )
        #expect(gate.resetForNewCaptureSession())

        let sameSessionAuthority = PassiveCoreBluetoothArtifactAuthorityContext(
            targetSessionGeneration: authority.targetSessionGeneration,
            authorityGeneration: authority.authorityGeneration + 5
        )
        #expect(
            capturedAbortStateError {
                try gate.begin(
                    .finiteAcquisitionReady,
                    through: 9,
                    authority: sameSessionAuthority
                )
            } == .freshTargetSessionRequired
        )

        let expectedFreshAuthority = PassiveCoreBluetoothArtifactAuthorityContext(
            targetSessionGeneration: freshGeneration,
            authorityGeneration: 1
        )
        _ = try gate.begin(
            .finiteAcquisitionReady,
            through: 9,
            authority: expectedFreshAuthority
        )
    }

    @Test("queue-tail movement after retirement keeps abort quarantine closed")
    @MainActor
    func queueTailMovementInvalidatesRetirementReceipt() async throws {
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let fixture = try await committedReady(on: &gate)
        let retirement = try retireCommittedAbort(
            gate: &gate,
            fixture: fixture,
            pendingTail: 5
        )

        #expect(
            capturedAbortStateError {
                try gate.completeAbortedObservationRecovery(
                    retirement,
                    currentLastEnqueuedEventSequence: 6,
                    freshTargetSessionGeneration: authority.targetSessionGeneration + 1
                )
            } == .abortQueueTailChanged
        )
        #expect(gate.isAbortQuarantined)
        #expect(gate.permittedDrainUpperBound(firstPending: 6, pendingTail: 6) == nil)
    }

    @Test("committed proof from a structurally identical foreign gate cannot abort this gate")
    @MainActor
    func foreignCommittedEpochCannotAbortCurrentGate() async throws {
        var currentGate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let current = try await committedReady(on: &currentGate)

        var foreignGate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let foreign = try await committedReady(on: &foreignGate)
        #expect(current.epoch.authority == foreign.epoch.authority)
        #expect(current.epoch.queueCutoff == foreign.epoch.queueCutoff)
        #expect(current.epoch.transactionRevision == foreign.epoch.transactionRevision)
        #expect(current.epoch.transactionIdentity != foreign.epoch.transactionIdentity)

        #expect(
            capturedAbortStateError {
                try currentGate.abortObservationEpoch(foreign.epoch)
            } == .staleTransaction
        )
        #expect(currentGate.phase == .observing)

        _ = try current.epoch.beginHorizon(
            queueCutoff: current.epoch.queueCutoff,
            processedThrough: current.epoch.queueCutoff,
            gate: &currentGate
        )
    }

    @Test("committed abort proof cannot erase an uncommitted Ready transaction")
    @MainActor
    func committedProofCannotEraseUncommittedReady() async throws {
        var committedGate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let committed = try await committedReady(on: &committedGate)

        var drainingGate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let fence = PassiveCoreBluetoothArtifactAuthorityFence(authority: authority)
        let admission = try PassiveCoreBluetoothObservationBoundaryTransactionDecision.beginReady(
            queueCutoff: 1,
            processedThrough: 1,
            authorityFence: fence,
            gate: &drainingGate
        )
        #expect(drainingGate.activeTransaction?.queueCutoff == admission.queueCutoff)

        #expect(
            capturedAbortStateError {
                try drainingGate.abortObservationEpoch(committed.epoch)
            } == .invalidTransition
        )
        #expect(drainingGate.activeTransaction?.queueCutoff == admission.queueCutoff)
    }

    @Test("Horizon-started, Horizon-recorded, and terminal states cannot escape through pre-H abort")
    @MainActor
    func postHorizonAbortIsRejected() async throws {
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let fixture = try await committedReady(on: &gate, cutoff: 1)
        let horizonAdmission = try fixture.epoch.beginHorizon(
            queueCutoff: 2,
            processedThrough: 1,
            gate: &gate
        )

        #expect(
            capturedAbortStateError {
                try gate.abortObservationEpoch(fixture.epoch)
            } == .invalidTransition
        )
        #expect(gate.activeTransaction?.queueCutoff == 2)

        let recordedHorizon = try await horizonAdmission.recordBoundary(on: fixture.recorder)
        let committedHorizon = try recordedHorizon.markBoundaryRecorded(
            on: &gate,
            lastProcessedQueueSequence: 2
        )
        #expect(
            capturedAbortStateError {
                try gate.abortObservationEpoch(fixture.epoch)
            } == .invalidTransition
        )
        #expect(gate.terminalQueueCutoff == nil)

        try committedHorizon.completeHorizonArtifactFreeze(on: &gate)
        #expect(
            capturedAbortStateError {
                try gate.abortObservationEpoch(fixture.epoch)
            } == .invalidTransition
        )
        #expect(gate.terminalQueueCutoff == 2)
    }
}

private func capturedAbortStateError<T>(
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
