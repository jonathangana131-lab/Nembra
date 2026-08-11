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
            _ = try gate.beginObservationHorizon(
                through: 4,
                processedThrough: 8,
                authority: authority,
                establishedByReadyRevision: ready.revision,
                establishedByReadyIdentity: ready.identity
            )
            Issue.record("A horizon cutoff older than the committed ready cutoff must fail closed. Otherwise callbacks accepted after ready can be withheld and later discarded even though they predate horizon initiation.")
        } catch let error as PassiveCoreBluetoothObservationBoundaryQueueGate.StateError {
            #expect(error == .horizonCutoffPrecedesReady)
        }

        #expect(gate.phase == .observing)
        #expect(gate.activeTransaction == nil)
        #expect(gate.permittedDrainUpperBound(firstPending: 9, pendingTail: 12) == 12)

        let validHorizon = try gate.beginObservationHorizon(
            through: 12,
            processedThrough: 8,
            authority: authority,
            establishedByReadyRevision: ready.revision,
            establishedByReadyIdentity: ready.identity
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
            _ = try gate.beginObservationHorizon(
                through: 9,
                processedThrough: 8,
                authority: changedAuthority,
                establishedByReadyRevision: ready.revision,
                establishedByReadyIdentity: ready.identity
            )
            Issue.record("The observation horizon must remain bound to the exact artifact authority that committed finite acquisition ready. A new authority cannot inherit the old ready boundary merely because the gate is in observing phase.")
        } catch let error as PassiveCoreBluetoothObservationBoundaryQueueGate.StateError {
            #expect(error == .authorityChanged)
        }

        #expect(gate.phase == .observing)
        #expect(gate.activeTransaction == nil)
        #expect(gate.permittedDrainUpperBound(firstPending: 9, pendingTail: 12) == 12)

        let validHorizon = try gate.beginObservationHorizon(
            through: 12,
            processedThrough: 8,
            authority: authority,
            establishedByReadyRevision: ready.revision,
            establishedByReadyIdentity: ready.identity
        )
        #expect(validHorizon.revision == ready.revision + 1)
        #expect(gate.phase == .drainingHorizon(validHorizon))
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

        do {
            _ = try gate.beginObservationHorizon(
                through: 10,
                processedThrough: 12,
                authority: authority,
                establishedByReadyRevision: ready.revision,
                establishedByReadyIdentity: ready.identity
            )
            Issue.record("A horizon cutoff may not move behind the recorder-completed queue prefix.")
        } catch let error as PassiveCoreBluetoothObservationBoundaryQueueGate.StateError {
            #expect(error == .horizonCutoffPrecedesProcessedPrefix)
        }

        #expect(gate.phase == .observing)
        #expect(gate.activeTransaction == nil)
        #expect(gate.permittedDrainUpperBound(firstPending: 9, pendingTail: 12) == 12)

        let validHorizon = try gate.beginObservationHorizon(
            through: 12,
            processedThrough: 12,
            authority: authority,
            establishedByReadyRevision: ready.revision,
            establishedByReadyIdentity: ready.identity
        )
        #expect(validHorizon.revision == ready.revision + 1)
        #expect(gate.phase == .drainingHorizon(validHorizon))
    }

    @Test("generic horizon entry cannot bypass processed-prefix and Ready-identity authority")
    func horizonRequiresProducerIdentityEntry() throws {
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
            Issue.record("Generic Horizon entry must not bypass the controller-owned processed frontier or exact Ready identity.")
        } catch let error as PassiveCoreBluetoothObservationBoundaryQueueGate.StateError {
            #expect(error == .invalidTransition)
        }

        #expect(gate.phase == .observing)
        #expect(gate.activeTransaction == nil)

        let validHorizon = try gate.beginObservationHorizon(
            through: 8,
            processedThrough: 8,
            authority: authority,
            establishedByReadyRevision: ready.revision,
            establishedByReadyIdentity: ready.identity
        )
        #expect(validHorizon.revision == ready.revision + 1)
    }
}