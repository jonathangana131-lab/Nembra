import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Passive CoreBluetooth observation-boundary queue gate reset safety")
struct PassiveCoreBluetoothObservationBoundaryQueueGateResetSafetyTests {
    private let authority = PassiveCoreBluetoothArtifactAuthorityContext(
        targetSessionGeneration: 7,
        authorityGeneration: 11
    )

    @Test("reset cannot release an unresolved ready cutoff")
    func resetDuringReadyDrainPreservesBarrier() throws {
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let ready = try gate.begin(
            .finiteAcquisitionReady,
            through: 4,
            authority: authority
        )

        #expect(gate.permittedDrainUpperBound(firstPending: 1, pendingTail: 6) == 4)
        let resetAccepted = gate.resetForNewCaptureSession()
        #expect(!resetAccepted)
        #expect(gate.phase == .drainingReady(ready))
        #expect(gate.activeTransaction == ready)
        #expect(gate.permittedDrainUpperBound(firstPending: 1, pendingTail: 6) == 4)
    }

    @Test("reset cannot erase committed ready authority while observing")
    func resetDuringObservationPreservesReadyAuthority() throws {
        let changedAuthority = PassiveCoreBluetoothArtifactAuthorityContext(
            targetSessionGeneration: authority.targetSessionGeneration,
            authorityGeneration: authority.authorityGeneration + 1
        )

        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let ready = try gate.begin(
            .finiteAcquisitionReady,
            through: 4,
            authority: authority
        )
        try gate.markBoundaryRecorded(
            ready,
            lastProcessedQueueSequence: 4,
            currentAuthority: authority
        )

        let resetAccepted = gate.resetForNewCaptureSession()
        #expect(!resetAccepted)
        #expect(gate.phase == .observing)

        do {
            _ = try gate.beginObservationHorizon(
                through: 5,
                processedThrough: 4,
                authority: changedAuthority,
                establishedByReadyRevision: ready.revision,
                establishedByReadyIdentity: ready.identity
            )
            Issue.record("Reset while observing must not detach the committed ready authority.")
        } catch let error as PassiveCoreBluetoothObservationBoundaryQueueGate.StateError {
            #expect(error == .authorityChanged)
        }

        let horizon = try gate.beginObservationHorizon(
            through: 5,
            processedThrough: 4,
            authority: authority,
            establishedByReadyRevision: ready.revision,
            establishedByReadyIdentity: ready.identity
        )
        #expect(horizon.revision == ready.revision + 1)
    }

    @Test("reset cannot release an unresolved horizon cutoff")
    func resetDuringHorizonDrainPreservesBarrier() throws {
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let ready = try gate.begin(
            .finiteAcquisitionReady,
            through: 2,
            authority: authority
        )
        try gate.markBoundaryRecorded(
            ready,
            lastProcessedQueueSequence: 2,
            currentAuthority: authority
        )
        let horizon = try gate.beginObservationHorizon(
            through: 6,
            processedThrough: 2,
            authority: authority,
            establishedByReadyRevision: ready.revision,
            establishedByReadyIdentity: ready.identity
        )

        #expect(gate.permittedDrainUpperBound(firstPending: 3, pendingTail: 8) == 6)
        let resetAccepted = gate.resetForNewCaptureSession()
        #expect(!resetAccepted)
        #expect(gate.phase == .drainingHorizon(horizon))
        #expect(gate.activeTransaction == horizon)
        #expect(gate.permittedDrainUpperBound(firstPending: 3, pendingTail: 8) == 6)
    }

    @Test("terminal freeze does not release quarantined post-horizon evidence")
    func terminalResetRequiresExplicitQueueRetirement() throws {
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let ready = try gate.begin(
            .finiteAcquisitionReady,
            through: 2,
            authority: authority
        )
        try gate.markBoundaryRecorded(
            ready,
            lastProcessedQueueSequence: 2,
            currentAuthority: authority
        )
        let horizon = try gate.beginObservationHorizon(
            through: 6,
            processedThrough: 2,
            authority: authority,
            establishedByReadyRevision: ready.revision,
            establishedByReadyIdentity: ready.identity
        )
        try gate.markBoundaryRecorded(
            horizon,
            lastProcessedQueueSequence: 6,
            currentAuthority: authority
        )

        #expect(gate.permittedDrainUpperBound(firstPending: 7, pendingTail: 8) == nil)
        let preFreezeResetAccepted = gate.resetForNewCaptureSession()
        #expect(!preFreezeResetAccepted)
        #expect(gate.phase == .horizonBoundaryRecorded(horizon))

        try gate.completeHorizonArtifactFreeze(
            horizon,
            currentAuthority: authority
        )

        #expect(gate.phase == .terminal(horizon))
        #expect(gate.permittedDrainUpperBound(firstPending: 7, pendingTail: 8) == nil)
        #expect(
            gate.shouldDiscardQueuedEvidenceAfterTerminalHorizon(
                queueSequence: 7,
                authority: authority
            )
        )
        #expect(
            gate.shouldDiscardQueuedEvidenceAfterTerminalHorizon(
                queueSequence: 8,
                authority: authority
            )
        )

        let terminalResetAccepted = gate.resetForNewCaptureSession()
        #expect(!terminalResetAccepted)
        #expect(gate.phase == .terminal(horizon))
        #expect(gate.permittedDrainUpperBound(firstPending: 7, pendingTail: 8) == nil)
        #expect(
            gate.shouldDiscardQueuedEvidenceAfterTerminalHorizon(
                queueSequence: 7,
                authority: authority
            )
        )
    }
}