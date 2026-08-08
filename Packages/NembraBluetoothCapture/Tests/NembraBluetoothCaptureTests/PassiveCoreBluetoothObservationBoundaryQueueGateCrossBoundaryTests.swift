import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Passive CoreBluetooth observation-boundary queue gate cross-boundary invariants")
struct PassiveCoreBluetoothObservationBoundaryQueueGateCrossBoundaryTests {
    private let authority = PassiveCoreBluetoothArtifactAuthorityContext(
        targetSessionGeneration: 7,
        authorityGeneration: 11
    )

    @Test("horizon cutoff cannot regress behind the committed ready cutoff")
    func horizonCutoffCannotRegressBehindCommittedReadyCutoff() throws {
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let ready = try gate.begin(
            .finiteAcquisitionReady,
            through: 8,
            authority: authority
        )
        try gate.markBoundaryRecorded(
            ready,
            lastProcessedQueueSequence: 8,
            currentAuthority: authority
        )

        do {
            _ = try gate.begin(
                .observationHorizon,
                through: 4,
                authority: authority
            )
            Issue.record(
                "A horizon cutoff older than the committed ready cutoff must fail closed. " +
                "Otherwise callbacks accepted after ready can be withheld and later discarded " +
                "even though they predate horizon initiation."
            )
        } catch {
            // Any fail-closed state error is acceptable here; this regression owns
            // the invariant rather than prescribing the production error taxonomy.
        }

        #expect(gate.phase == .observing)
        #expect(gate.activeTransaction == nil)
        #expect(gate.permittedDrainUpperBound(firstPending: 9, pendingTail: 12) == 12)

        let validHorizon = try gate.begin(
            .observationHorizon,
            through: 12,
            authority: authority
        )
        #expect(validHorizon.revision == ready.revision + 1)
        #expect(gate.phase == .drainingHorizon(validHorizon))
    }

    @Test("horizon must retain the exact authority that committed ready")
    func horizonAuthorityCannotChangeAfterReadyCommit() throws {
        let changedAuthority = PassiveCoreBluetoothArtifactAuthorityContext(
            targetSessionGeneration: authority.targetSessionGeneration,
            authorityGeneration: authority.authorityGeneration + 1
        )

        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let ready = try gate.begin(
            .finiteAcquisitionReady,
            through: 8,
            authority: authority
        )
        try gate.markBoundaryRecorded(
            ready,
            lastProcessedQueueSequence: 8,
            currentAuthority: authority
        )

        do {
            _ = try gate.begin(
                .observationHorizon,
                through: 9,
                authority: changedAuthority
            )
            Issue.record(
                "The observation horizon must remain bound to the exact artifact authority " +
                "that committed finite acquisition ready. A new authority cannot inherit " +
                "the old ready boundary merely because the gate is in observing phase."
            )
        } catch {
            // Any fail-closed state error is acceptable here; this regression owns
            // the invariant rather than prescribing the production error taxonomy.
        }

        #expect(gate.phase == .observing)
        #expect(gate.activeTransaction == nil)
        #expect(gate.permittedDrainUpperBound(firstPending: 9, pendingTail: 12) == 12)

        let validHorizon = try gate.begin(
            .observationHorizon,
            through: 12,
            authority: authority
        )
        #expect(validHorizon.revision == ready.revision + 1)
        #expect(gate.phase == .drainingHorizon(validHorizon))
    }

    @Test("new capture reset clears the previous ready anchor but preserves revision chronology")
    func newCaptureResetClearsReadyAnchorWithoutReusingRevision() throws {
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let oldReady = try gate.begin(
            .finiteAcquisitionReady,
            through: 8,
            authority: authority
        )
        try gate.markBoundaryRecorded(
            oldReady,
            lastProcessedQueueSequence: 8,
            currentAuthority: authority
        )

        gate.resetForNewCaptureSession()

        let freshAuthority = PassiveCoreBluetoothArtifactAuthorityContext(
            targetSessionGeneration: authority.targetSessionGeneration + 1,
            authorityGeneration: authority.authorityGeneration + 1
        )
        let freshReady = try gate.begin(
            .finiteAcquisitionReady,
            through: 2,
            authority: freshAuthority
        )
        #expect(freshReady.revision == oldReady.revision + 1)

        try gate.markBoundaryRecorded(
            freshReady,
            lastProcessedQueueSequence: 2,
            currentAuthority: freshAuthority
        )

        let freshHorizon = try gate.begin(
            .observationHorizon,
            through: 3,
            authority: freshAuthority
        )
        #expect(freshHorizon.queueCutoff == 3)
        #expect(freshHorizon.authority == freshAuthority)
        #expect(freshHorizon.revision == freshReady.revision + 1)
        #expect(gate.phase == .drainingHorizon(freshHorizon))
    }

    @Test("reset cannot release a draining ready cutoff")
    func resetCannotReleaseDrainingReadyCutoff() throws {
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let ready = try gate.begin(
            .finiteAcquisitionReady,
            through: 4,
            authority: authority
        )
        #expect(gate.permittedDrainUpperBound(firstPending: 1, pendingTail: 6) == 4)
        #expect(gate.permittedDrainUpperBound(firstPending: 5, pendingTail: 6) == nil)

        gate.resetForNewCaptureSession()

        #expect(gate.phase == .drainingReady(ready))
        #expect(gate.activeTransaction == ready)
        #expect(gate.permittedDrainUpperBound(firstPending: 5, pendingTail: 6) == nil)
    }

    @Test("reset cannot release a draining horizon cutoff")
    func resetCannotReleaseDrainingHorizonCutoff() throws {
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
            through: 4,
            authority: authority
        )
        #expect(gate.permittedDrainUpperBound(firstPending: 3, pendingTail: 6) == 4)
        #expect(gate.permittedDrainUpperBound(firstPending: 5, pendingTail: 6) == nil)

        gate.resetForNewCaptureSession()

        #expect(gate.phase == .drainingHorizon(horizon))
        #expect(gate.activeTransaction == horizon)
        #expect(gate.permittedDrainUpperBound(firstPending: 5, pendingTail: 6) == nil)
    }

    @Test("reset cannot release horizon after boundary recording but before artifact freeze")
    func resetCannotReleaseRecordedHorizonBeforeFreeze() throws {
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
            through: 4,
            authority: authority
        )
        try gate.markBoundaryRecorded(
            horizon,
            lastProcessedQueueSequence: 4,
            currentAuthority: authority
        )
        #expect(gate.permittedDrainUpperBound(firstPending: 5, pendingTail: 6) == nil)

        gate.resetForNewCaptureSession()

        #expect(gate.phase == .horizonBoundaryRecorded(horizon))
        #expect(gate.activeTransaction == horizon)
        #expect(gate.permittedDrainUpperBound(firstPending: 5, pendingTail: 6) == nil)
    }
}
