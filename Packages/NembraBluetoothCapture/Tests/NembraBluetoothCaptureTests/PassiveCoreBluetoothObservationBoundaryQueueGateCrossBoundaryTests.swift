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
                processedThrough: 8,
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
            processedThrough: 8,
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
                processedThrough: 8,
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
            processedThrough: 8,
            authority: authority
        )
        #expect(validHorizon.revision == ready.revision + 1)
        #expect(gate.phase == .drainingHorizon(validHorizon))
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
            processedThrough: 2,
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
            processedThrough: 2,
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

    @Test("horizon cutoff cannot trail raw evidence already processed while observing")
    func horizonCutoffCannotTrailProcessedPrefix() throws {
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

        // Ordinary observation draining has already completed recorder hops through
        // queue sequence 12. A stale horizon decision at 10 cannot put records 11-12
        // "after" a horizon that is only being opened now.
        do {
            _ = try gate.begin(
                .observationHorizon,
                through: 10,
                processedThrough: 12,
                authority: authority
            )
            Issue.record(
                "A horizon cutoff may not move behind the recorder-completed queue prefix."
            )
        } catch {
            // Taxonomy is intentionally not the contract; atomic rejection is.
        }

        #expect(gate.phase == .observing)
        #expect(gate.activeTransaction == nil)
        #expect(gate.permittedDrainUpperBound(firstPending: 9, pendingTail: 12) == 12)

        let validHorizon = try gate.begin(
            .observationHorizon,
            through: 12,
            processedThrough: 12,
            authority: authority
        )
        #expect(validHorizon.revision == ready.revision + 1)
        #expect(gate.phase == .drainingHorizon(validHorizon))
    }

    @Test("horizon cannot open without the recorder-completed processed frontier")
    func horizonRequiresProcessedPrefix() throws {
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
                through: 8,
                authority: authority
            )
            Issue.record(
                "A horizon without the controller-owned processed frontier must fail closed."
            )
        } catch let error as PassiveCoreBluetoothObservationBoundaryQueueGate.StateError {
            #expect(error == .horizonProcessedPrefixRequired)
        }

        #expect(gate.phase == .observing)
        #expect(gate.activeTransaction == nil)

        let validHorizon = try gate.begin(
            .observationHorizon,
            through: 8,
            processedThrough: 8,
            authority: authority
        )
        #expect(validHorizon.revision == ready.revision + 1)
    }
}
