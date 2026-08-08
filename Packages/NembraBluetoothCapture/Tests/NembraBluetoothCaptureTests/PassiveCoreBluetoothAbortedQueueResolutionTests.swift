import Testing
@testable import NembraBluetoothCapture

@Suite("Pre-H aborted queue resolution")
struct PassiveCoreBluetoothAbortedQueueResolutionTests {
    private typealias Gate = PassiveCoreBluetoothObservationBoundaryQueueGate
    private typealias Retirement = PassiveCoreBluetoothAbortedObservationQueueRetirement
    private typealias Resolution = PassiveCoreBluetoothAbortedQueueResolution

    private struct PendingEvent: Equatable {
        let queueSequence: UInt64
        let authority: PassiveCoreBluetoothArtifactAuthorityContext
    }

    private let authority = PassiveCoreBluetoothArtifactAuthorityContext(
        targetSessionGeneration: 7,
        authorityGeneration: 11
    )

    @Test("complete abandoned-session suffix advances resolved frontier without recorder claim")
    @MainActor
    func exactRetirementResolvesThroughQueueTail() throws {
        var gate = try quarantinedCommittedReadyGate(readyCutoff: 4)
        var pending = [
            pendingEvent(sequence: 5, authorityGeneration: 12),
            pendingEvent(sequence: 6, authorityGeneration: 13),
        ]

        let retirement = try Retirement.retire(
            from: &pending,
            currentLastEnqueuedEventSequence: 6,
            currentSettledQueueSequence: 4,
            drainIsIdle: true,
            abortedGate: gate,
            identity: identity
        )
        #expect(pending.isEmpty)
        #expect(retirement.retiredEvidenceCount == 2)

        let resolution = try Resolution.resolve(
            currentResolvedThroughQueueSequence: 4,
            currentLastEnqueuedEventSequence: 6,
            retirementReceipt: retirement
        )

        #expect(resolution.abortReceipt == retirement.abortReceipt)
        #expect(resolution.previouslyResolvedThroughQueueSequence == 4)
        #expect(resolution.resolvedThroughQueueSequence == 6)
        #expect(resolution.retiredEvidenceCount == 2)
        #expect(resolution.advancesResolvedFrontier)

        // Resolution is descriptive authority only: it must not reopen the gate or
        // turn the abandoned recorder into a completed observation epoch.
        #expect(gate.isAbortQuarantined)
    }

    @Test("already-settled recorded prefix remains distinct from retired suffix")
    @MainActor
    func settledPrefixMayExtendPastReadyBeforeRetirement() throws {
        let gate = try quarantinedCommittedReadyGate(readyCutoff: 4)
        var pending = [
            pendingEvent(sequence: 6, authorityGeneration: 12),
            pendingEvent(sequence: 7, authorityGeneration: 13),
        ]

        // Sequence 5 was already settled before quarantine. The retirement producer
        // therefore owns only 6...7, and resolution must advance from 5 rather than
        // pretending the whole Ready->tail interval was retired.
        let retirement = try Retirement.retire(
            from: &pending,
            currentLastEnqueuedEventSequence: 7,
            currentSettledQueueSequence: 5,
            drainIsIdle: true,
            abortedGate: gate,
            identity: identity
        )
        let resolution = try Resolution.resolve(
            currentResolvedThroughQueueSequence: 5,
            currentLastEnqueuedEventSequence: 7,
            retirementReceipt: retirement
        )

        #expect(resolution.previouslyResolvedThroughQueueSequence == 5)
        #expect(resolution.resolvedThroughQueueSequence == 7)
        #expect(resolution.retiredEvidenceCount == 2)
    }

    @Test("callback accepted after retirement invalidates resolution")
    @MainActor
    func queueTailMovementFailsClosed() throws {
        let gate = try quarantinedCommittedReadyGate(readyCutoff: 4)
        var pending = [pendingEvent(sequence: 5, authorityGeneration: 12)]
        let retirement = try Retirement.retire(
            from: &pending,
            currentLastEnqueuedEventSequence: 5,
            currentSettledQueueSequence: 4,
            drainIsIdle: true,
            abortedGate: gate,
            identity: identity
        )

        let error = captureResolutionError {
            _ = try Resolution.resolve(
                currentResolvedThroughQueueSequence: 4,
                currentLastEnqueuedEventSequence: 6,
                retirementReceipt: retirement
            )
        }
        #expect(error == .controllerQueueChangedAfterRetirement(expected: 5, actual: 6))
    }

    @Test("resolution requires the exact previously-settled frontier")
    @MainActor
    func staleResolvedFrontierFailsClosed() throws {
        let gate = try quarantinedCommittedReadyGate(readyCutoff: 4)
        var pending = [pendingEvent(sequence: 5, authorityGeneration: 12)]
        let retirement = try Retirement.retire(
            from: &pending,
            currentLastEnqueuedEventSequence: 5,
            currentSettledQueueSequence: 4,
            drainIsIdle: true,
            abortedGate: gate,
            identity: identity
        )

        let error = captureResolutionError {
            _ = try Resolution.resolve(
                currentResolvedThroughQueueSequence: 3,
                currentLastEnqueuedEventSequence: 5,
                retirementReceipt: retirement
            )
        }
        #expect(error == .resolvedFrontierDoesNotMatchRetirementSettled(current: 3, settled: 4))
    }

    @Test("empty retirement is an exact no-op resolution")
    @MainActor
    func noPendingSuffixKeepsResolvedFrontierStable() throws {
        let gate = try quarantinedCommittedReadyGate(readyCutoff: 4)
        var pending: [PendingEvent] = []
        let retirement = try Retirement.retire(
            from: &pending,
            currentLastEnqueuedEventSequence: 4,
            currentSettledQueueSequence: 4,
            drainIsIdle: true,
            abortedGate: gate,
            identity: identity
        )

        let resolution = try Resolution.resolve(
            currentResolvedThroughQueueSequence: 4,
            currentLastEnqueuedEventSequence: 4,
            retirementReceipt: retirement
        )
        #expect(resolution.previouslyResolvedThroughQueueSequence == 4)
        #expect(resolution.resolvedThroughQueueSequence == 4)
        #expect(resolution.retiredEvidenceCount == 0)
        #expect(!resolution.advancesResolvedFrontier)
    }

    @Test("same retirement proof cannot be replayed after caller advances frontier")
    @MainActor
    func replayAfterResolutionFailsClosed() throws {
        let gate = try quarantinedCommittedReadyGate(readyCutoff: 4)
        var pending = [pendingEvent(sequence: 5, authorityGeneration: 12)]
        let retirement = try Retirement.retire(
            from: &pending,
            currentLastEnqueuedEventSequence: 5,
            currentSettledQueueSequence: 4,
            drainIsIdle: true,
            abortedGate: gate,
            identity: identity
        )
        let first = try Resolution.resolve(
            currentResolvedThroughQueueSequence: 4,
            currentLastEnqueuedEventSequence: 5,
            retirementReceipt: retirement
        )
        #expect(first.resolvedThroughQueueSequence == 5)

        let replayError = captureResolutionError {
            _ = try Resolution.resolve(
                currentResolvedThroughQueueSequence: first.resolvedThroughQueueSequence,
                currentLastEnqueuedEventSequence: 5,
                retirementReceipt: retirement
            )
        }
        #expect(replayError == .resolvedFrontierDoesNotMatchRetirementSettled(current: 5, settled: 4))
    }

    @MainActor
    private func quarantinedCommittedReadyGate(
        readyCutoff: UInt64
    ) throws -> Gate {
        var gate = Gate()
        let ready = try gate.begin(
            .finiteAcquisitionReady,
            through: readyCutoff,
            authority: authority
        )
        try gate.markBoundaryRecorded(
            ready,
            lastProcessedQueueSequence: readyCutoff,
            currentAuthority: authority
        )
        _ = try gate.abortObservationEpoch(
            expectedReadyAuthority: authority,
            expectedReadyQueueCutoff: readyCutoff
        )
        return gate
    }

    private func pendingEvent(
        sequence: UInt64,
        authorityGeneration: UInt64
    ) -> PendingEvent {
        PendingEvent(
            queueSequence: sequence,
            authority: .init(
                targetSessionGeneration: authority.targetSessionGeneration,
                authorityGeneration: authorityGeneration
            )
        )
    }

    private func identity(_ event: PendingEvent) -> Retirement.PendingEvidenceIdentity {
        .init(queueSequence: event.queueSequence, authority: event.authority)
    }

    @MainActor
    private func captureResolutionError(
        _ operation: () throws -> Void
    ) -> Resolution.StateError? {
        do {
            try operation()
            return nil
        } catch {
            return error as? Resolution.StateError
        }
    }
}
