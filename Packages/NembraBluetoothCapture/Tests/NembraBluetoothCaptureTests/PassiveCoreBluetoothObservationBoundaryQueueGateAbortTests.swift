import Testing
@testable import NembraBluetoothCapture

@Suite("Passive CoreBluetooth observation-boundary pre-H abort")
struct PassiveCoreBluetoothObservationBoundaryQueueGateAbortTests {
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

    @Test("exact committed Ready may abort only into a mandatory fresh target session")
    func abortRequiresFreshTargetSessionBeforeAnotherReady() throws {
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let oldReady = try committedReady(on: &gate)

        let receipt = try gate.abortObservationEpoch(
            expectedReadyAuthority: oldReady.authority,
            expectedReadyQueueCutoff: oldReady.queueCutoff
        )
        #expect(receipt.abandonedReadyTransaction == oldReady)
        #expect(receipt.abandonedTargetSessionGeneration == authority.targetSessionGeneration)
        #expect(gate.phase == .awaitingReady)

        let sameSessionNewAuthority = PassiveCoreBluetoothArtifactAuthorityContext(
            targetSessionGeneration: authority.targetSessionGeneration,
            authorityGeneration: authority.authorityGeneration + 1
        )
        let sameSessionError = capturedAbortStateError {
            try gate.begin(
                .finiteAcquisitionReady,
                through: 5,
                authority: sameSessionNewAuthority
            )
        }
        #expect(sameSessionError == .freshTargetSessionRequired)
        #expect(gate.phase == .awaitingReady)

        let freshSessionAuthority = PassiveCoreBluetoothArtifactAuthorityContext(
            targetSessionGeneration: authority.targetSessionGeneration + 1,
            authorityGeneration: 1
        )
        let freshReady = try gate.begin(
            .finiteAcquisitionReady,
            through: 5,
            authority: freshSessionAuthority
        )
        #expect(freshReady.authority == freshSessionAuthority)
        #expect(freshReady.revision > oldReady.revision)
        #expect(gate.phase == .drainingReady(freshReady))
    }

    @Test("normal reset cannot erase the fresh-session fence created by abort")
    func resetDoesNotEraseAbortFence() throws {
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let oldReady = try committedReady(on: &gate)
        _ = try gate.abortObservationEpoch(
            expectedReadyAuthority: oldReady.authority,
            expectedReadyQueueCutoff: oldReady.queueCutoff
        )

        let resetAccepted = gate.resetForNewCaptureSession()
        #expect(resetAccepted)
        #expect(gate.phase == .awaitingReady)

        let sameSessionAuthority = PassiveCoreBluetoothArtifactAuthorityContext(
            targetSessionGeneration: authority.targetSessionGeneration,
            authorityGeneration: authority.authorityGeneration + 5
        )
        let error = capturedAbortStateError {
            try gate.begin(
                .finiteAcquisitionReady,
                through: 9,
                authority: sameSessionAuthority
            )
        }
        #expect(error == .freshTargetSessionRequired)
        #expect(gate.phase == .awaitingReady)
    }

    @Test("older target-session generations cannot satisfy an abort fence")
    func olderTargetSessionFailsClosed() throws {
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let oldReady = try committedReady(on: &gate)
        _ = try gate.abortObservationEpoch(
            expectedReadyAuthority: oldReady.authority,
            expectedReadyQueueCutoff: oldReady.queueCutoff
        )

        let olderAuthority = PassiveCoreBluetoothArtifactAuthorityContext(
            targetSessionGeneration: authority.targetSessionGeneration - 1,
            authorityGeneration: UInt64.max - 1
        )
        let error = capturedAbortStateError {
            try gate.begin(
                .finiteAcquisitionReady,
                through: 5,
                authority: olderAuthority
            )
        }
        #expect(error == .freshTargetSessionRequired)
        #expect(gate.phase == .awaitingReady)
    }

    @Test("abort requires the exact committed Ready transaction")
    func staleReadyTransactionCannotAbortCurrentEpoch() throws {
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

    @Test("abort is legal only after Ready commit and before Horizon begins")
    func abortPhaseBoundaryFailsClosed() throws {
        var awaiting = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let fabricated = PassiveCoreBluetoothObservationBoundaryQueueGate.Transaction(
            boundaryKind: .finiteAcquisitionReady,
            queueCutoff: 1,
            authority: authority,
            revision: 1
        )
        #expect(
            capturedAbortStateError {
                try awaiting.abortObservationEpoch(
                    expectedReadyAuthority: fabricated.authority,
                    expectedReadyQueueCutoff: fabricated.queueCutoff
                )
            } == .invalidTransition
        )

        var drainingReady = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let uncommittedReady = try drainingReady.begin(
            .finiteAcquisitionReady,
            through: 1,
            authority: authority
        )
        #expect(
            capturedAbortStateError {
                try drainingReady.abortObservationEpoch(
                    expectedReadyAuthority: uncommittedReady.authority,
                    expectedReadyQueueCutoff: uncommittedReady.queueCutoff
                )
            } == .invalidTransition
        )
        #expect(drainingReady.phase == .drainingReady(uncommittedReady))

        var drainingHorizon = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let committed = try committedReady(on: &drainingHorizon, cutoff: 1)
        let horizon = try drainingHorizon.begin(
            .observationHorizon,
            through: 2,
            processedThrough: 1,
            authority: authority
        )
        #expect(
            capturedAbortStateError {
                try drainingHorizon.abortObservationEpoch(
                    expectedReadyAuthority: committed.authority,
                    expectedReadyQueueCutoff: committed.queueCutoff
                )
            } == .invalidTransition
        )
        #expect(drainingHorizon.phase == .drainingHorizon(horizon))
    }

    @Test("Horizon-recorded and terminal states can never escape through pre-H abort")
    func postHorizonAbortIsRejected() throws {
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let ready = try committedReady(on: &gate, cutoff: 1)
        let horizon = try gate.begin(
            .observationHorizon,
            through: 2,
            processedThrough: 1,
            authority: authority
        )
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
