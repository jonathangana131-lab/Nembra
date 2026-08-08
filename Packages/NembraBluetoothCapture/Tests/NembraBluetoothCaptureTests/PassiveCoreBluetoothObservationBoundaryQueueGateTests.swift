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

        let earlyResult = Result {
            try gate.markBoundaryRecorded(
                transaction,
                lastProcessedQueueSequence: 3,
                currentAuthority: authority
            )
        }
        #expect(earlyResult == .failure(.cutoffNotDrained))

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

        let horizon = try gate.begin(
            .observationHorizon,
            through: 8,
            authority: authority
        )
        #expect(gate.permittedDrainUpperBound(firstPending: 3, pendingTail: 10) == 8)

        try gate.markBoundaryRecorded(
            horizon,
            lastProcessedQueueSequence: 8,
            currentAuthority: authority
        )

        #expect(gate.phase == .horizonBoundaryRecorded(horizon))
        #expect(gate.permittedDrainUpperBound(firstPending: 9, pendingTail: 10) == nil)
        #expect(!gate.isTerminal)

        try gate.completeHorizonArtifactFreeze(
            horizon,
            currentAuthority: authority
        )

        #expect(gate.isTerminal)
        #expect(gate.terminalQueueCutoff == 8)
        #expect(gate.permittedDrainUpperBound(firstPending: 9, pendingTail: 10) == nil)
        #expect(
            gate.shouldDiscardQueuedEvidenceAfterTerminalHorizon(
                queueSequence: 9,
                authority: authority
            )
        )
        #expect(
            !gate.shouldDiscardQueuedEvidenceAfterTerminalHorizon(
                queueSequence: 8,
                authority: authority
            )
        )
    }

    @Test("horizon cannot begin before one ready boundary")
    func horizonBeforeReadyFailsClosed() {
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let result = Result {
            try gate.begin(
                .observationHorizon,
                through: 0,
                authority: authority
            )
        }

        #expect(result == .failure(.invalidTransition))
        #expect(gate.phase == .awaitingReady)
    }

    @Test("duplicate ready cannot reopen observation grammar")
    func duplicateReadyFailsClosed() throws {
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let first = try gate.begin(
            .finiteAcquisitionReady,
            through: 0,
            authority: authority
        )
        try gate.markBoundaryRecorded(
            first,
            lastProcessedQueueSequence: 0,
            currentAuthority: authority
        )

        let result = Result {
            try gate.begin(
                .finiteAcquisitionReady,
                through: 1,
                authority: authority
            )
        }

        #expect(result == .failure(.invalidTransition))
        #expect(gate.phase == .observing)
    }

    @Test("old async boundary completion cannot satisfy a newer transaction")
    func staleTransactionFailsClosed() throws {
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let ready = try gate.begin(
            .finiteAcquisitionReady,
            through: 1,
            authority: authority
        )
        try gate.markBoundaryRecorded(
            ready,
            lastProcessedQueueSequence: 1,
            currentAuthority: authority
        )
        let horizon = try gate.begin(
            .observationHorizon,
            through: 3,
            authority: authority
        )

        let staleResult = Result {
            try gate.markBoundaryRecorded(
                ready,
                lastProcessedQueueSequence: 3,
                currentAuthority: authority
            )
        }

        #expect(staleResult == .failure(.staleTransaction))
        #expect(gate.phase == .drainingHorizon(horizon))
    }

    @Test("authority drift cannot commit ready or terminal freeze")
    func authorityDriftFailsClosed() throws {
        let changedAuthority = PassiveCoreBluetoothArtifactAuthorityContext(
            targetSessionGeneration: authority.targetSessionGeneration,
            authorityGeneration: authority.authorityGeneration + 1
        )

        var readyGate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let ready = try readyGate.begin(
            .finiteAcquisitionReady,
            through: 1,
            authority: authority
        )
        let readyResult = Result {
            try readyGate.markBoundaryRecorded(
                ready,
                lastProcessedQueueSequence: 1,
                currentAuthority: changedAuthority
            )
        }
        #expect(readyResult == .failure(.authorityChanged))
        #expect(readyGate.phase == .drainingReady(ready))

        var horizonGate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let ready2 = try horizonGate.begin(
            .finiteAcquisitionReady,
            through: 1,
            authority: authority
        )
        try horizonGate.markBoundaryRecorded(
            ready2,
            lastProcessedQueueSequence: 1,
            currentAuthority: authority
        )
        let horizon = try horizonGate.begin(
            .observationHorizon,
            through: 2,
            authority: authority
        )
        try horizonGate.markBoundaryRecorded(
            horizon,
            lastProcessedQueueSequence: 2,
            currentAuthority: authority
        )
        let freezeResult = Result {
            try horizonGate.completeHorizonArtifactFreeze(
                horizon,
                currentAuthority: changedAuthority
            )
        }
        #expect(freezeResult == .failure(.authorityChanged))
        #expect(horizonGate.phase == .horizonBoundaryRecorded(horizon))
    }

    @Test("fresh target session reset does not make an old transaction current")
    func newSessionResetKeepsOldTransactionsStale() throws {
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let oldReady = try gate.begin(
            .finiteAcquisitionReady,
            through: 1,
            authority: authority
        )
        try gate.markBoundaryRecorded(
            oldReady,
            lastProcessedQueueSequence: 1,
            currentAuthority: authority
        )
        let horizon = try gate.begin(
            .observationHorizon,
            through: 2,
            authority: authority
        )
        try gate.markBoundaryRecorded(
            horizon,
            lastProcessedQueueSequence: 2,
            currentAuthority: authority
        )
        try gate.completeHorizonArtifactFreeze(
            horizon,
            currentAuthority: authority
        )

        gate.resetForNewCaptureSession()
        let freshAuthority = PassiveCoreBluetoothArtifactAuthorityContext(
            targetSessionGeneration: authority.targetSessionGeneration + 1,
            authorityGeneration: authority.authorityGeneration + 1
        )
        let freshReady = try gate.begin(
            .finiteAcquisitionReady,
            through: 5,
            authority: freshAuthority
        )

        let staleResult = Result {
            try gate.markBoundaryRecorded(
                oldReady,
                lastProcessedQueueSequence: 5,
                currentAuthority: freshAuthority
            )
        }
        #expect(staleResult == .failure(.authorityChanged))
        #expect(gate.phase == .drainingReady(freshReady))
        #expect(freshReady.revision > oldReady.revision)
    }
}

private extension Result where Success == Void, Failure == Error {
    static func failure(
        _ error: PassiveCoreBluetoothObservationBoundaryQueueGate.StateError
    ) -> Self {
        .failure(error)
    }
}
