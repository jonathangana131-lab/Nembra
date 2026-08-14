import Testing
@testable import NembraBluetoothCapture

@MainActor
struct PassiveCoreBluetoothTerminalQueueRetirementTests {
    private typealias Retirement = PassiveCoreBluetoothTerminalQueueRetirement

    private struct Event: Equatable {
        let queueSequence: UInt64
        let authority: PassiveCoreBluetoothArtifactAuthorityContext
        let label: String
    }

    private let terminalAuthority = PassiveCoreBluetoothArtifactAuthorityContext(
        targetSessionGeneration: 4,
        authorityGeneration: 9
    )

    @Test
    func retiresOnlyExactTerminalAuthorityAfterHorizon() throws {
        let newerSameSessionAuthority = PassiveCoreBluetoothArtifactAuthorityContext(
            targetSessionGeneration: 4,
            authorityGeneration: 10
        )
        let foreignSessionAuthority = PassiveCoreBluetoothArtifactAuthorityContext(
            targetSessionGeneration: 5,
            authorityGeneration: 1
        )
        var events = [
            Event(queueSequence: 13, authority: terminalAuthority, label: "old-a"),
            Event(queueSequence: 14, authority: newerSameSessionAuthority, label: "new"),
            Event(queueSequence: 15, authority: terminalAuthority, label: "old-b"),
            Event(queueSequence: 16, authority: foreignSessionAuthority, label: "foreign")
        ]

        let receipt = try retire(
            &events,
            currentTail: 16,
            gate: try terminalGate(horizonQueueCutoff: 12)
        )

        #expect(events.map(\.label) == ["new", "foreign"])
        #expect(receipt.terminalAuthority == terminalAuthority)
        #expect(receipt.terminalTransactionRevision == 2)
        #expect(receipt.horizonQueueCutoff == 12)
        #expect(receipt.validatedQueueTailSequence == 16)
        #expect(receipt.retiredEvidenceCount == 2)
        #expect(receipt.firstRetiredQueueSequence == 13)
        #expect(receipt.lastRetiredQueueSequence == 15)
        #expect(receipt.retainedPendingEvidenceCount == 2)
        #expect(receipt.requiresRetainedEvidenceRoutingBeforeReopen)
    }

    @Test
    func anyPendingEvidenceAtHorizonFailsWithoutMutation() throws {
        let foreignAuthority = PassiveCoreBluetoothArtifactAuthorityContext(
            targetSessionGeneration: 5,
            authorityGeneration: 10
        )
        var events = [
            Event(queueSequence: 12, authority: foreignAuthority, label: "foreign-at-h"),
            Event(queueSequence: 13, authority: terminalAuthority, label: "post-h")
        ]
        let before = events

        let error = captureStateError {
            _ = try retire(
                &events,
                currentTail: 13,
                gate: try terminalGate(horizonQueueCutoff: 12)
            )
        }

        #expect(error == .terminalPrefixStillPending(queueSequence: 12))
        #expect(events == before)
    }

    @Test
    func anyPendingEvidenceBeforeHorizonFailsWithoutMutation() throws {
        var events = [
            Event(queueSequence: 11, authority: terminalAuthority, label: "pre-h"),
            Event(queueSequence: 13, authority: terminalAuthority, label: "post-h")
        ]
        let before = events

        let error = captureStateError {
            _ = try retire(
                &events,
                currentTail: 13,
                gate: try terminalGate(horizonQueueCutoff: 12)
            )
        }

        #expect(error == .terminalPrefixStillPending(queueSequence: 11))
        #expect(events == before)
    }

    @Test
    func missingFirstPostHorizonSequenceFailsWithoutMutation() throws {
        var events = [
            Event(queueSequence: 14, authority: terminalAuthority, label: "gap-after-h")
        ]
        let before = events

        let error = captureStateError {
            _ = try retire(
                &events,
                currentTail: 14,
                gate: try terminalGate(horizonQueueCutoff: 12)
            )
        }

        #expect(
            error == .nonContiguousPendingQueueSequence(
                expected: 13,
                actual: 14
            )
        )
        #expect(events == before)
    }

    @Test
    func missingInteriorPostHorizonSequenceFailsWithoutMutation() throws {
        var events = [
            Event(queueSequence: 13, authority: terminalAuthority, label: "first"),
            Event(queueSequence: 15, authority: terminalAuthority, label: "gap")
        ]
        let before = events

        let error = captureStateError {
            _ = try retire(
                &events,
                currentTail: 15,
                gate: try terminalGate(horizonQueueCutoff: 12)
            )
        }

        #expect(
            error == .nonContiguousPendingQueueSequence(
                expected: 14,
                actual: 15
            )
        )
        #expect(events == before)
    }

    @Test
    func controllerTailCannotRegressBehindTerminalHorizon() throws {
        var events: [Event] = []
        let before = events

        let error = captureStateError {
            _ = try retire(
                &events,
                currentTail: 11,
                gate: try terminalGate(horizonQueueCutoff: 12)
            )
        }

        #expect(error == .controllerQueueTailBeforeHorizon(tail: 11, horizon: 12))
        #expect(events == before)
    }

    @Test
    func truncatedPendingQueueCannotMintRetirementReceipt() throws {
        var events = [
            Event(queueSequence: 13, authority: terminalAuthority, label: "known")
        ]
        let before = events

        let error = captureStateError {
            _ = try retire(
                &events,
                currentTail: 14,
                gate: try terminalGate(horizonQueueCutoff: 12)
            )
        }

        #expect(
            error == .pendingQueueTailMismatch(
                expectedControllerTail: 14,
                actualPendingTail: 13
            )
        )
        #expect(events == before)
    }

    @Test
    func emptyQueueCannotHideCallbacksAfterHorizon() throws {
        var events: [Event] = []

        let error = captureStateError {
            _ = try retire(
                &events,
                currentTail: 14,
                gate: try terminalGate(horizonQueueCutoff: 12)
            )
        }

        #expect(
            error == .pendingQueueTailMismatch(
                expectedControllerTail: 14,
                actualPendingTail: nil
            )
        )
        #expect(events.isEmpty)
    }

    @Test
    func secondRetirementCannotInferOldGlobalTailFromAlreadyRetiredQueue() throws {
        var events = [
            Event(queueSequence: 13, authority: terminalAuthority, label: "old-a"),
            Event(queueSequence: 14, authority: terminalAuthority, label: "old-b")
        ]
        let gate = try terminalGate(horizonQueueCutoff: 12)

        let receipt = try retire(&events, currentTail: 14, gate: gate)
        #expect(events.isEmpty)
        #expect(receipt.validatedQueueTailSequence == 14)
        #expect(!receipt.requiresRetainedEvidenceRoutingBeforeReopen)

        let error = captureStateError {
            _ = try retire(&events, currentTail: 14, gate: gate)
        }
        #expect(
            error == .pendingQueueTailMismatch(
                expectedControllerTail: 14,
                actualPendingTail: nil
            )
        )
    }

    @Test
    func receiptKeepsControllerTailWhenThatTailIsRetired() throws {
        let newerAuthority = PassiveCoreBluetoothArtifactAuthorityContext(
            targetSessionGeneration: 4,
            authorityGeneration: 10
        )
        var events = [
            Event(queueSequence: 13, authority: newerAuthority, label: "retained"),
            Event(queueSequence: 14, authority: terminalAuthority, label: "retired-tail")
        ]

        let receipt = try retire(
            &events,
            currentTail: 14,
            gate: try terminalGate(horizonQueueCutoff: 12)
        )

        #expect(events.map(\.label) == ["retained"])
        #expect(receipt.validatedQueueTailSequence == 14)
        #expect(receipt.lastRetiredQueueSequence == 14)
        #expect(receipt.retainedPendingEvidenceCount == 1)
        #expect(receipt.requiresRetainedEvidenceRoutingBeforeReopen)
    }

    @Test
    func newerAuthorityOnlyQueueProducesNoOpReceiptBoundToControllerTail() throws {
        let newerAuthority = PassiveCoreBluetoothArtifactAuthorityContext(
            targetSessionGeneration: 4,
            authorityGeneration: 10
        )
        var events = [
            Event(queueSequence: 13, authority: newerAuthority, label: "new")
        ]

        let receipt = try retire(
            &events,
            currentTail: 13,
            gate: try terminalGate(horizonQueueCutoff: 12)
        )

        #expect(events.map(\.label) == ["new"])
        #expect(receipt.terminalAuthority == terminalAuthority)
        #expect(receipt.terminalTransactionRevision == 2)
        #expect(receipt.horizonQueueCutoff == 12)
        #expect(receipt.validatedQueueTailSequence == 13)
        #expect(receipt.retiredEvidenceCount == 0)
        #expect(receipt.firstRetiredQueueSequence == nil)
        #expect(receipt.lastRetiredQueueSequence == nil)
        #expect(receipt.retainedPendingEvidenceCount == 1)
        #expect(receipt.requiresRetainedEvidenceRoutingBeforeReopen)
    }

    @Test
    func emptyQueueAtExactHorizonProducesNoOpReceipt() throws {
        var events: [Event] = []

        let receipt = try retire(
            &events,
            currentTail: 12,
            gate: try terminalGate(horizonQueueCutoff: 12)
        )

        #expect(events.isEmpty)
        #expect(receipt.terminalAuthority == terminalAuthority)
        #expect(receipt.terminalTransactionRevision == 2)
        #expect(receipt.horizonQueueCutoff == 12)
        #expect(receipt.validatedQueueTailSequence == 12)
        #expect(receipt.retiredEvidenceCount == 0)
        #expect(receipt.retainedPendingEvidenceCount == 0)
        #expect(!receipt.requiresRetainedEvidenceRoutingBeforeReopen)
    }

    @Test
    func nonterminalGateFailsWithoutMutation() throws {
        var events = [
            Event(queueSequence: 13, authority: terminalAuthority, label: "old")
        ]
        let before = events

        let error = captureStateError {
            _ = try retire(
                &events,
                currentTail: 13,
                gate: PassiveCoreBluetoothObservationBoundaryQueueGate()
            )
        }

        #expect(error == .terminalHorizonRequired)
        #expect(events == before)
    }

    @Test
    func malformedQueueChronologyFailsAtomically() throws {
        var duplicate = [
            Event(queueSequence: 13, authority: terminalAuthority, label: "a"),
            Event(queueSequence: 13, authority: terminalAuthority, label: "b")
        ]
        let duplicateBefore = duplicate
        let duplicateError = captureStateError {
            _ = try retire(
                &duplicate,
                currentTail: 13,
                gate: try terminalGate(horizonQueueCutoff: 12)
            )
        }
        #expect(
            duplicateError == .nonIncreasingQueueSequence(previous: 13, current: 13)
        )
        #expect(duplicate == duplicateBefore)

        var regressing = [
            Event(queueSequence: 13, authority: terminalAuthority, label: "a"),
            Event(queueSequence: 14, authority: terminalAuthority, label: "b"),
            Event(queueSequence: 13, authority: terminalAuthority, label: "c")
        ]
        let regressingBefore = regressing
        let regressingError = captureStateError {
            _ = try retire(
                &regressing,
                currentTail: 13,
                gate: try terminalGate(horizonQueueCutoff: 12)
            )
        }
        #expect(
            regressingError == .nonIncreasingQueueSequence(previous: 14, current: 13)
        )
        #expect(regressing == regressingBefore)

        var zero = [
            Event(queueSequence: 0, authority: terminalAuthority, label: "zero")
        ]
        let zeroBefore = zero
        let zeroError = captureStateError {
            _ = try retire(
                &zero,
                currentTail: 13,
                gate: try terminalGate(horizonQueueCutoff: 12)
            )
        }
        #expect(zeroError == .invalidQueueSequence(0))
        #expect(zero == zeroBefore)
    }

    private func retire(
        _ events: inout [Event],
        currentTail: UInt64,
        gate: PassiveCoreBluetoothObservationBoundaryQueueGate
    ) throws -> Retirement.Receipt {
        try Retirement.retire(
            from: &events,
            currentLastEnqueuedEventSequence: currentTail,
            terminalGate: gate,
            identity: identity
        )
    }

    private func identity(_ event: Event) -> Retirement.PendingEvidenceIdentity {
        Retirement.PendingEvidenceIdentity(
            queueSequence: event.queueSequence,
            authority: event.authority
        )
    }

    private func captureStateError(
        _ operation: () throws -> Void
    ) -> Retirement.StateError? {
        do {
            try operation()
            return nil
        } catch {
            return error as? Retirement.StateError
        }
    }

    private func terminalGate(
        horizonQueueCutoff: UInt64
    ) throws -> PassiveCoreBluetoothObservationBoundaryQueueGate {
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let ready = try gate.begin(
            .finiteAcquisitionReady,
            through: 5,
            authority: terminalAuthority
        )
        try gate.markBoundaryRecorded(
            ready,
            lastProcessedQueueSequence: 5,
            currentAuthority: terminalAuthority
        )
        let horizon = try gate.beginObservationHorizon(
            through: horizonQueueCutoff,
            processedThrough: 8,
            authority: terminalAuthority,
            establishedByReadyRevision: ready.revision,
            establishedByReadyIdentity: ready.identity
        )
        try gate.markBoundaryRecorded(
            horizon,
            lastProcessedQueueSequence: horizonQueueCutoff,
            currentAuthority: terminalAuthority
        )
        try gate.completeHorizonArtifactFreeze(
            horizon,
            currentAuthority: terminalAuthority
        )
        return gate
    }
}
