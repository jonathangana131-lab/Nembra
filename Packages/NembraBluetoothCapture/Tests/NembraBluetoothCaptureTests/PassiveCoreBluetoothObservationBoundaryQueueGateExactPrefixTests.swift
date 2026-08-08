import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Passive CoreBluetooth observation-boundary exact processed prefix")
struct PassiveCoreBluetoothObservationBoundaryQueueGateExactPrefixTests {
    private let authority = PassiveCoreBluetoothArtifactAuthorityContext(
        targetSessionGeneration: 7,
        authorityGeneration: 11
    )

    @Test("ready cannot commit after recorder processing crossed its cutoff")
    func readyOverrunFailsClosed() throws {
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let ready = try gate.begin(
            .finiteAcquisitionReady,
            through: 4,
            authority: authority
        )

        do {
            try gate.markBoundaryRecorded(
                ready,
                lastProcessedQueueSequence: 6,
                currentAuthority: authority
            )
            Issue.record("Ready must not commit behind already-processed recorder evidence.")
        } catch let error as PassiveCoreBluetoothObservationBoundaryQueueGate.StateError {
            #expect(error == .cutoffOverrun)
        }

        #expect(gate.phase == .drainingReady(ready))
        #expect(gate.activeTransaction == ready)
        #expect(gate.permittedDrainUpperBound(firstPending: 5, pendingTail: 6) == nil)
    }

    @Test("horizon cannot commit after recorder processing crossed its cutoff")
    func horizonOverrunFailsClosed() throws {
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

        do {
            try gate.markBoundaryRecorded(
                horizon,
                lastProcessedQueueSequence: 7,
                currentAuthority: authority
            )
            Issue.record("Horizon must not commit behind already-processed recorder evidence.")
        } catch let error as PassiveCoreBluetoothObservationBoundaryQueueGate.StateError {
            #expect(error == .cutoffOverrun)
        }

        #expect(gate.phase == .drainingHorizon(horizon))
        #expect(gate.activeTransaction == horizon)
        #expect(gate.permittedDrainUpperBound(firstPending: 7, pendingTail: 8) == nil)
    }

    @Test("exact prefix commits remain valid when ready and horizon share a quiet watermark")
    func exactQuietWatermarkCommits() throws {
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

        let horizon = try gate.beginObservationHorizon(
            through: 4,
            processedThrough: 4,
            authority: authority,
            establishedByReadyRevision: ready.revision,
            establishedByReadyIdentity: ready.identity
        )
        try gate.markBoundaryRecorded(
            horizon,
            lastProcessedQueueSequence: 4,
            currentAuthority: authority
        )

        #expect(gate.phase == .horizonBoundaryRecorded(horizon))
        #expect(gate.permittedDrainUpperBound(firstPending: 5, pendingTail: 6) == nil)

        try gate.completeHorizonArtifactFreeze(
            horizon,
            currentAuthority: authority
        )
        #expect(gate.isTerminal)
        #expect(gate.terminalQueueCutoff == 4)
    }
}
