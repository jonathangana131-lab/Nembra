import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Passive CoreBluetooth observation-boundary queue gate")
struct PassiveCoreBluetoothObservationBoundaryQueueGateTests {
    private let authority = PassiveCoreBluetoothArtifactAuthorityContext(
        targetSessionGeneration: 7,
        authorityGeneration: 11
    )

    @Test("ready cutoff drains accepted prefix then releases later evidence")
    func readyCutoffOrdersBoundaryBeforeLaterEvidence() throws {
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let transaction = try gate.begin(
            .finiteAcquisitionReady,
            through: 4,
            authority: authority
        )
        #expect(gate.permittedDrainUpperBound(firstPending: 1, pendingTail: 6) == 4)
        #expect(gate.permittedDrainUpperBound(firstPending: 5, pendingTail: 6) == nil)

        #expect(capturedStateError {
            try gate.markBoundaryRecorded(
                transaction,
                lastProcessedQueueSequence: 3,
                currentAuthority: authority
            )
        } == .cutoffNotDrained)

        try gate.markBoundaryRecorded(
            transaction,
            lastProcessedQueueSequence: 4,
            currentAuthority: authority
        )
        #expect(gate.phase == .observing)
        #expect(gate.activeTransaction == nil)
        #expect(gate.permittedDrainUpperBound(firstPending: 5, pendingTail: 6) == 6)
    }

    @Test("terminal horizon keeps post-cut evidence blocked through artifact freeze")
    func horizonBarrierRemainsClosedUntilFreeze() throws {
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let ready = try gate.begin(.finiteAcquisitionReady, through: 2, authority: authority)
        try gate.markBoundaryRecorded(ready, lastProcessedQueueSequence: 2, currentAuthority: authority)

        let horizon = try gate.beginObservationHorizon(
            through: 8,
            processedThrough: 2,
            authority: authority,
            establishedByReadyRevision: ready.revision,
            establishedByReadyIdentity: ready.identity
        )
        #expect(gate.permittedDrainUpperBound(firstPending: 3, pendingTail: 10) == 8)

        try gate.markBoundaryRecorded(horizon, lastProcessedQueueSequence: 8, currentAuthority: authority)
        #expect(gate.phase == .horizonBoundaryRecorded(horizon))
        #expect(gate.permittedDrainUpperBound(firstPending: 9, pendingTail: 10) == nil)
        #expect(!gate.isTerminal)

        try gate.completeHorizonArtifactFreeze(horizon, currentAuthority: authority)
        #expect(gate.isTerminal)
        #expect(gate.terminalQueueCutoff == 8)
        #expect(gate.permittedDrainUpperBound(firstPending: 9, pendingTail: 10) == nil)
        #expect(gate.shouldDiscardQueuedEvidenceAfterTerminalHorizon(queueSequence: 9, authority: authority))
        #expect(!gate.shouldDiscardQueuedEvidenceAfterTerminalHorizon(queueSequence: 8, authority: authority))
    }

    @Test("generic Horizon entry is not a producer-identity bypass")
    func genericHorizonEntryFailsClosed() throws {
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let ready = try gate.begin(.finiteAcquisitionReady, through: 0, authority: authority)
        try gate.markBoundaryRecorded(ready, lastProcessedQueueSequence: 0, currentAuthority: authority)

        #expect(capturedStateError {
            try gate.begin(
                .observationHorizon,
                through: 0,
                processedThrough: 0,
                authority: authority
            )
        } == .invalidTransition)
        #expect(gate.phase == .observing)
    }

    @Test("foreign committed Ready identity cannot open Horizon on an equal scalar gate")
    func foreignReadyIdentityFailsClosed() throws {
        var gateA = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let readyA = try gateA.begin(.finiteAcquisitionReady, through: 2, authority: authority)
        try gateA.markBoundaryRecorded(readyA, lastProcessedQueueSequence: 2, currentAuthority: authority)

        var gateB = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let readyB = try gateB.begin(.finiteAcquisitionReady, through: 2, authority: authority)
        try gateB.markBoundaryRecorded(readyB, lastProcessedQueueSequence: 2, currentAuthority: authority)
        #expect(readyA.revision == readyB.revision)
        #expect(readyA.identity != readyB.identity)

        #expect(capturedStateError {
            try gateB.beginObservationHorizon(
                through: 3,
                processedThrough: 2,
                authority: authority,
                establishedByReadyRevision: readyA.revision,
                establishedByReadyIdentity: readyA.identity
            )
        } == .staleTransaction)
        #expect(gateB.phase == .observing)

        _ = try gateB.beginObservationHorizon(
            through: 3,
            processedThrough: 2,
            authority: authority,
            establishedByReadyRevision: readyB.revision,
            establishedByReadyIdentity: readyB.identity
        )
    }

    @Test("horizon cannot begin before one ready boundary")
    func horizonBeforeReadyFailsClosed() {
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let error = capturedStateError {
            try gate.beginObservationHorizon(
                through: 0,
                processedThrough: 0,
                authority: authority,
                establishedByReadyRevision: 1,
                establishedByReadyIdentity: UUID()
            )
        }
        #expect(error == .invalidTransition)
        #expect(gate.phase == .awaitingReady)
    }

    @Test("duplicate ready cannot reopen observation grammar")
    func duplicateReadyFailsClosed() throws {
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let first = try gate.begin(.finiteAcquisitionReady, through: 0, authority: authority)
        try gate.markBoundaryRecorded(first, lastProcessedQueueSequence: 0, currentAuthority: authority)
        #expect(capturedStateError {
            try gate.begin(.finiteAcquisitionReady, through: 1, authority: authority)
        } == .invalidTransition)
        #expect(gate.phase == .observing)
    }

    @Test("old async boundary completion cannot satisfy a newer transaction")
    func staleTransactionFailsClosed() throws {
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let ready = try gate.begin(.finiteAcquisitionReady, through: 1, authority: authority)
        try gate.markBoundaryRecorded(ready, lastProcessedQueueSequence: 1, currentAuthority: authority)
        let horizon = try gate.beginObservationHorizon(
            through: 3,
            processedThrough: 1,
            authority: authority,
            establishedByReadyRevision: ready.revision,
            establishedByReadyIdentity: ready.identity
        )
        #expect(capturedStateError {
            try gate.markBoundaryRecorded(ready, lastProcessedQueueSequence: 3, currentAuthority: authority)
        } == .staleTransaction)
        #expect(gate.phase == .drainingHorizon(horizon))
    }

    @Test("authority drift cannot commit ready or terminal freeze")
    func authorityDriftFailsClosed() throws {
        let changedAuthority = PassiveCoreBluetoothArtifactAuthorityContext(
            targetSessionGeneration: authority.targetSessionGeneration,
            authorityGeneration: authority.authorityGeneration + 1
        )
        var readyGate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let ready = try readyGate.begin(.finiteAcquisitionReady, through: 1, authority: authority)
        #expect(capturedStateError {
            try readyGate.markBoundaryRecorded(ready, lastProcessedQueueSequence: 1, currentAuthority: changedAuthority)
        } == .authorityChanged)
        #expect(readyGate.phase == .drainingReady(ready))

        var horizonGate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let ready2 = try horizonGate.begin(.finiteAcquisitionReady, through: 1, authority: authority)
        try horizonGate.markBoundaryRecorded(ready2, lastProcessedQueueSequence: 1, currentAuthority: authority)
        let horizon = try horizonGate.beginObservationHorizon(
            through: 2,
            processedThrough: 1,
            authority: authority,
            establishedByReadyRevision: ready2.revision,
            establishedByReadyIdentity: ready2.identity
        )
        try horizonGate.markBoundaryRecorded(horizon, lastProcessedQueueSequence: 2, currentAuthority: authority)
        #expect(capturedStateError {
            try horizonGate.completeHorizonArtifactFreeze(horizon, currentAuthority: changedAuthority)
        } == .authorityChanged)
        #expect(horizonGate.phase == .horizonBoundaryRecorded(horizon))
    }

    @Test("terminal freeze cannot reopen lifecycle before old queue retirement")
    func terminalResetFailsClosedUntilQueueRetirementExists() throws {
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let oldReady = try gate.begin(.finiteAcquisitionReady, through: 1, authority: authority)
        try gate.markBoundaryRecorded(oldReady, lastProcessedQueueSequence: 1, currentAuthority: authority)
        let horizon = try gate.beginObservationHorizon(
            through: 2,
            processedThrough: 1,
            authority: authority,
            establishedByReadyRevision: oldReady.revision,
            establishedByReadyIdentity: oldReady.identity
        )
        try gate.markBoundaryRecorded(horizon, lastProcessedQueueSequence: 2, currentAuthority: authority)
        try gate.completeHorizonArtifactFreeze(horizon, currentAuthority: authority)
        #expect(gate.phase == .terminal(horizon))
        #expect(gate.permittedDrainUpperBound(firstPending: 3, pendingTail: 5) == nil)
        let resetAfterTerminal = gate.resetForNewCaptureSession()
        #expect(!resetAfterTerminal)

        let freshAuthority = PassiveCoreBluetoothArtifactAuthorityContext(
            targetSessionGeneration: authority.targetSessionGeneration + 1,
            authorityGeneration: authority.authorityGeneration + 1
        )
        #expect(throws: PassiveCoreBluetoothObservationBoundaryQueueGate.StateError.invalidTransition) {
            _ = try gate.begin(.finiteAcquisitionReady, through: 5, authority: freshAuthority)
        }
    }
}

private func capturedStateError<T>(
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
