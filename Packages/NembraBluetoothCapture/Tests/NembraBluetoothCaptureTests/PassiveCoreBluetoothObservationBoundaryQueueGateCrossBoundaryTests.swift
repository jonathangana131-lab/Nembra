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
    }
}
