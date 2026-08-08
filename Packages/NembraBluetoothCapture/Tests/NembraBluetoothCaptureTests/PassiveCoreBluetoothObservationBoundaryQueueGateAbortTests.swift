import Testing
@testable import NembraBluetoothCapture

@Suite("Passive CoreBluetooth observation-boundary pre-H abort")
struct PassiveCoreBluetoothObservationBoundaryQueueGateAbortTests {
    private struct PendingEvent: Equatable {
        let queueSequence: UInt64
        let authority: PassiveCoreBluetoothArtifactAuthorityContext
    }

    private let authority = PassiveCoreBluetoothArtifactAuthorityContext(
        targetSessionGeneration: 7,
        authorityGeneration: 11
    )

    private func committedReady(
        on gate: inout PassiveCoreBluetoothObservationBoundaryQueueGate,
        authority: PassiveCoreBluetoothArtifactAuthorityContext? = nil,
        cutoff: UInt64 = 4
    ) throws -> PassiveCoreBluetoothObservationBoundaryQueueGate.Transaction {
        let selectedAuthority = authority ?? self.authority
        let ready = try gate.begin(
            .finiteAcquisitionReady,
            through: cutoff,
            authority: selectedAuthority
        )
        try gate.markBoundaryRecorded(
            ready,
            lastProcessedQueueSequence: cutoff,
            currentAuthority: selectedAuthority
        )
        return ready
    }

    private func retireCommittedAbort(
        gate: inout PassiveCoreBluetoothObservationBoundaryQueueGate,
        ready: PassiveCoreBluetoothObservationBoundaryQueueGate.Transaction,
        pendingTail: UInt64 = 5
    ) throws -> PassiveCoreBluetoothAbortedObservationQueueRetirement.Receipt {
        _ = try gate.abortObservationEpoch(
            expectedReadyAuthority: ready.authority,
            expectedReadyQueueCutoff: ready.queueCutoff
        )
        var pending = pendingTail > ready.queueCutoff
            ? [
                PendingEvent(
                    queueSequence: pendingTail,
                    authority: PassiveCoreBluetoothArtifactAuthorityContext(
                        targetSessionGeneration: ready.authority.targetSessionGeneration,
                        authorityGeneration: ready.authority.authorityGeneration + 1
                    )
                )
            ]
            : []
        return try PassiveCoreBluetoothAbortedObservationQueueRetirement.retire(
            from: &pending,
            currentLastEnqueuedEventSequence: pendingTail,
            currentSettledQueueSequence: ready.queueCutoff,
            drainIsIdle: true,
            abortedGate: gate,
            identity: {
                .init(queueSequence: $0.queueSequence, authority: $0.authority)
            }
        )
    }

    @Test("committed Ready abort quarantines draining until queue retirement + fresh session binding")
    func committedAbortRequiresRetirementBeforeFreshReady() throws {
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let oldReady = try committedReady(on: &gate)

        let abort = try gate.abortObservationEpoch(
            expectedReadyAuthority: oldReady.authority,
            expectedReadyQueueCutoff: oldReady.queueCutoff
        )
        #expect(abort.abandonedReadyAuthority == oldReady.authority)
        #expect(abort.abandonedReadyQueueCutoff == oldReady.queueCutoff)
        #expect(abort.abandonedReadyTransactionRevision == oldReady.revision)
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
                authority: PassiveCoreBluetoothArtifactAuthorityContext(
                    targetSessionGeneration: authority.targetSessionGeneration,
                    authorityGeneration: authority.authorityGeneration + 1
                )
            ),
            PendingEvent(
                queueSequence: 6,
                authority: PassiveCoreBluetoothArtifactAuthorityContext(
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
        #expect(freshReady.revision > oldReady.revision)
        #expect(gate.phase == .drainingReady(freshReady))
    }

    @Test("normal reset cannot erase abort quarantine or exact fresh-session binding")
    func resetDoesNotEraseRecoveryFences() throws {
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let oldReady = try committedReady(on: &gate)
        let retirement = try retireCommittedAbort(
            gate: &gate,
            ready: oldReady,
            pendingTail: oldReady.queueCutoff
        )

        #expect(gate.resetForNewCaptureSession() == false)
        #expect(gate.isAbortQuarantined)

        let freshGeneration = authority.targetSessionGeneration + 1
        try gate.completeAbortedObservationRecovery(
            retirement,
            currentLastEnqueuedEventSequence: oldReady.queueCutoff,
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
    func queueTailMovementInvalidatesRetirementReceipt() throws {
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let ready = try committedReady(on: &gate)
        let retirement = try retireCommittedAbort(
            gate: &gate,
            ready: ready,
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

    @Test("abort requires the exact committed Ready identity")
    func staleReadyIdentityCannotAbortCurrentEpoch() throws {
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let currentReady = try committedReady(on: &gate)
        let error = capturedAbortStateError {
            try gate.abortObservationEpoch(
                expectedReadyAuthority: currentReady.authority,
                expectedReadyQueueCutoff: currentReady.queueCutoff + 1
            )
        }
        #expect(error == .staleTransaction)
        #expect(gate.phase == .observing)

        let horizon = try gate.begin(
            .observationHorizon,
            through: currentReady.queueCutoff,
            processedThrough: currentReady.queueCutoff,
            authority: authority
        )
        #expect(gate.phase == .drainingHorizon(horizon))
    }

    @Test("caller-asserted committed abort is unavailable during uncommitted Ready drain")
    func genericAbortCannotEraseUncommittedReady() throws {
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let uncommittedReady = try gate.begin(
            .finiteAcquisitionReady,
            through: 1,
            authority: authority
        )
        #expect(
            capturedAbortStateError {
                try gate.abortObservationEpoch(
                    expectedReadyAuthority: uncommittedReady.authority,
                    expectedReadyQueueCutoff: uncommittedReady.queueCutoff
                )
            } == .invalidTransition
        )
        #expect(gate.phase == .drainingReady(uncommittedReady))
    }

    @Test("Horizon-started, Horizon-recorded, and terminal states cannot escape through pre-H abort")
    func postHorizonAbortIsRejected() throws {
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let ready = try committedReady(on: &gate, cutoff: 1)
        let horizon = try gate.begin(
            .observationHorizon,
            through: 2,
            processedThrough: 1,
            authority: authority
        )
        #expect(
            capturedAbortStateError {
                try gate.abortObservationEpoch(
                    expectedReadyAuthority: ready.authority,
                    expectedReadyQueueCutoff: ready.queueCutoff
                )
            } == .invalidTransition
        )
        #expect(gate.phase == .drainingHorizon(horizon))

        try gate.markBoundaryRecorded(
            horizon,
            lastProcessedQueueSequence: 2,
            currentAuthority: authority
        )
        #expect(
            capturedAbortStateError {
                try gate.abortObservationEpoch(
                    expectedReadyAuthority: ready.authority,
                    expectedReadyQueueCutoff: ready.queueCutoff
                )
            } == .invalidTransition
        )
        #expect(gate.phase == .horizonBoundaryRecorded(horizon))

        try gate.completeHorizonArtifactFreeze(
            horizon,
            currentAuthority: authority
        )
        #expect(
            capturedAbortStateError {
                try gate.abortObservationEpoch(
                    expectedReadyAuthority: ready.authority,
                    expectedReadyQueueCutoff: ready.queueCutoff
                )
            } == .invalidTransition
        )
        #expect(gate.phase == .terminal(horizon))
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
