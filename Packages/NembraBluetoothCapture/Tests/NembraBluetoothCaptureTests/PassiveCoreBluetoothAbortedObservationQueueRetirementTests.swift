import Testing
@testable import NembraBluetoothCapture

@Suite("Passive CoreBluetooth aborted-observation queue retirement")
struct PassiveCoreBluetoothAbortedObservationQueueRetirementTests {
    private struct PendingEvent: Equatable {
        let queueSequence: UInt64
        let authority: PassiveCoreBluetoothArtifactAuthorityContext
    }

    private let authority = PassiveCoreBluetoothArtifactAuthorityContext(
        targetSessionGeneration: 7,
        authorityGeneration: 11
    )

    private func quarantinedGate(
        readyCutoff: UInt64 = 4
    ) throws -> PassiveCoreBluetoothObservationBoundaryQueueGate {
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
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

    private func identity(
        _ event: PendingEvent
    ) -> PassiveCoreBluetoothAbortedObservationQueueRetirement.PendingEvidenceIdentity {
        .init(queueSequence: event.queueSequence, authority: event.authority)
    }

    @Test("retires the complete contiguous abandoned-session suffix across authority generations")
    @MainActor
    func retiresCompleteAbandonedSessionSuffix() throws {
        let gate = try quarantinedGate()
        var pending = [
            PendingEvent(
                queueSequence: 5,
                authority: authority
            ),
            PendingEvent(
                queueSequence: 6,
                authority: .init(
                    targetSessionGeneration: authority.targetSessionGeneration,
                    authorityGeneration: authority.authorityGeneration + 1
                )
            ),
            PendingEvent(
                queueSequence: 7,
                authority: .init(
                    targetSessionGeneration: authority.targetSessionGeneration,
                    authorityGeneration: authority.authorityGeneration + 2
                )
            ),
        ]

        let receipt = try PassiveCoreBluetoothAbortedObservationQueueRetirement.retire(
            from: &pending,
            currentLastEnqueuedEventSequence: 7,
            currentSettledQueueSequence: 4,
            drainIsIdle: true,
            abortedGate: gate,
            identity: identity
        )

        #expect(pending.isEmpty)
        #expect(receipt.abortReceipt.abandonedTargetSessionGeneration == 7)
        #expect(receipt.abortReceipt.abandonedReadyQueueCutoff == 4)
        #expect(receipt.validatedQueueTailSequence == 7)
        #expect(receipt.validatedSettledQueueSequence == 4)
        #expect(receipt.retiredEvidenceCount == 3)
        #expect(receipt.retainedPendingEvidenceCount == 0)
    }

    @Test("empty pending queue is valid only when settled frontier equals enqueue tail")
    @MainActor
    func emptyQueueRequiresSettledTailEquality() throws {
        let gate = try quarantinedGate()
        var empty: [PendingEvent] = []

        #expect(
            capturedRetirementError {
                try PassiveCoreBluetoothAbortedObservationQueueRetirement.retire(
                    from: &empty,
                    currentLastEnqueuedEventSequence: 6,
                    currentSettledQueueSequence: 5,
                    drainIsIdle: true,
                    abortedGate: gate,
                    identity: identity
                )
            } == .pendingQueueTailMismatch(
                expectedControllerTail: 6,
                actualPendingTail: nil
            )
        )
        #expect(empty.isEmpty)

        let receipt = try PassiveCoreBluetoothAbortedObservationQueueRetirement.retire(
            from: &empty,
            currentLastEnqueuedEventSequence: 6,
            currentSettledQueueSequence: 6,
            drainIsIdle: true,
            abortedGate: gate,
            identity: identity
        )
        #expect(receipt.retiredEvidenceCount == 0)
        #expect(receipt.validatedQueueTailSequence == 6)
    }

    @Test("active drain rejects retirement before any pending mutation")
    @MainActor
    func activeDrainFailsAtomically() throws {
        let gate = try quarantinedGate()
        var pending = [PendingEvent(queueSequence: 5, authority: authority)]
        let original = pending

        #expect(
            capturedRetirementError {
                try PassiveCoreBluetoothAbortedObservationQueueRetirement.retire(
                    from: &pending,
                    currentLastEnqueuedEventSequence: 5,
                    currentSettledQueueSequence: 4,
                    drainIsIdle: false,
                    abortedGate: gate,
                    identity: identity
                )
            } == .eventDrainStillActive
        )
        #expect(pending == original)
    }

    @Test("sequence hole exposes a popped/in-flight or manually truncated FIFO and fails atomically")
    @MainActor
    func queueHoleFailsAtomically() throws {
        let gate = try quarantinedGate()
        var pending = [
            PendingEvent(queueSequence: 6, authority: authority),
            PendingEvent(queueSequence: 7, authority: authority),
        ]
        let original = pending

        #expect(
            capturedRetirementError {
                try PassiveCoreBluetoothAbortedObservationQueueRetirement.retire(
                    from: &pending,
                    currentLastEnqueuedEventSequence: 7,
                    currentSettledQueueSequence: 4,
                    drainIsIdle: true,
                    abortedGate: gate,
                    identity: identity
                )
            } == .nonContiguousQueueSequence(expected: 5, actual: 6)
        )
        #expect(pending == original)
    }

    @Test("foreign target-session evidence is never collateral retirement")
    @MainActor
    func foreignTargetSessionFailsAtomically() throws {
        let gate = try quarantinedGate()
        var pending = [
            PendingEvent(queueSequence: 5, authority: authority),
            PendingEvent(
                queueSequence: 6,
                authority: .init(
                    targetSessionGeneration: authority.targetSessionGeneration + 1,
                    authorityGeneration: 1
                )
            ),
        ]
        let original = pending

        #expect(
            capturedRetirementError {
                try PassiveCoreBluetoothAbortedObservationQueueRetirement.retire(
                    from: &pending,
                    currentLastEnqueuedEventSequence: 6,
                    currentSettledQueueSequence: 4,
                    drainIsIdle: true,
                    abortedGate: gate,
                    identity: identity
                )
            } == .foreignTargetSessionPending(expected: 7, actual: 8)
        )
        #expect(pending == original)
    }

    @Test("Ready prefix must already be settled before abandoned-session retirement")
    @MainActor
    func unsettledReadyPrefixFailsClosed() throws {
        let gate = try quarantinedGate(readyCutoff: 4)
        var pending = [PendingEvent(queueSequence: 4, authority: authority)]
        let original = pending

        #expect(
            capturedRetirementError {
                try PassiveCoreBluetoothAbortedObservationQueueRetirement.retire(
                    from: &pending,
                    currentLastEnqueuedEventSequence: 4,
                    currentSettledQueueSequence: 3,
                    drainIsIdle: true,
                    abortedGate: gate,
                    identity: identity
                )
            } == .readyPrefixNotSettled(settled: 3, readyCutoff: 4)
        )
        #expect(pending == original)
    }

    @Test("non-quarantined gate cannot authorize pre-H retirement")
    @MainActor
    func observingGateFailsClosed() throws {
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
        var pending = [PendingEvent(queueSequence: 5, authority: authority)]
        let original = pending

        #expect(
            capturedRetirementError {
                try PassiveCoreBluetoothAbortedObservationQueueRetirement.retire(
                    from: &pending,
                    currentLastEnqueuedEventSequence: 5,
                    currentSettledQueueSequence: 4,
                    drainIsIdle: true,
                    abortedGate: gate,
                    identity: identity
                )
            } == .abortQuarantineRequired
        )
        #expect(pending == original)
    }
}

private func capturedRetirementError<T>(
    _ operation: () throws -> T
) -> PassiveCoreBluetoothAbortedObservationQueueRetirement.StateError? {
    do {
        _ = try operation()
        return nil
    } catch let error as PassiveCoreBluetoothAbortedObservationQueueRetirement.StateError {
        return error
    } catch {
        return nil
    }
}
