import Testing
@testable import NembraBluetoothCapture

@MainActor
struct PassiveCoreBluetoothTerminalQueueResolutionTests {
    private typealias Retirement = PassiveCoreBluetoothTerminalQueueRetirement
    private typealias Resolution = PassiveCoreBluetoothTerminalQueueResolution

    private struct Event: Equatable {
        let queueSequence: UInt64
        let authority: PassiveCoreBluetoothArtifactAuthorityContext
    }

    private let terminalAuthority = PassiveCoreBluetoothArtifactAuthorityContext(
        targetSessionGeneration: 4,
        authorityGeneration: 9
    )

    @Test
    func fullyRetiredPostHorizonSuffixAdvancesOnlyResolvedFrontier() throws {
        var events = [
            Event(queueSequence: 13, authority: terminalAuthority),
            Event(queueSequence: 14, authority: terminalAuthority)
        ]
        let result = try retire(
            &events,
            currentTail: 14,
            horizonQueueCutoff: 12
        )
        let retirement = result.receipt
        #expect(events.isEmpty)
        #expect(retirement.retiredEvidenceCount == 2)
        #expect(!retirement.requiresRetainedEvidenceRoutingBeforeReopen)

        let resolution = try Resolution.resolve(
            currentResolvedThroughQueueSequence: 12,
            currentLastEnqueuedEventSequence: 14,
            retirementReceipt: retirement,
            terminalGate: result.terminalGate
        )

        #expect(resolution.terminalAuthority == terminalAuthority)
        #expect(resolution.terminalTransactionRevision == 2)
        #expect(resolution.horizonQueueCutoff == 12)
        #expect(resolution.previouslyResolvedThroughQueueSequence == 12)
        #expect(resolution.resolvedThroughQueueSequence == 14)
        #expect(resolution.retiredEvidenceCount == 2)
        #expect(resolution.advancesResolvedFrontier)
    }

    @Test
    func exactHorizonWithNoPostCutCallbacksIsAValidNoOpResolution() throws {
        var events: [Event] = []
        let result = try retire(
            &events,
            currentTail: 12,
            horizonQueueCutoff: 12
        )

        let resolution = try Resolution.resolve(
            currentResolvedThroughQueueSequence: 12,
            currentLastEnqueuedEventSequence: 12,
            retirementReceipt: result.receipt,
            terminalGate: result.terminalGate
        )

        #expect(resolution.horizonQueueCutoff == 12)
        #expect(resolution.previouslyResolvedThroughQueueSequence == 12)
        #expect(resolution.resolvedThroughQueueSequence == 12)
        #expect(resolution.retiredEvidenceCount == 0)
        #expect(!resolution.advancesResolvedFrontier)
    }

    @Test
    func nonterminalGateCannotResolveTerminalRetirement() throws {
        var events = [
            Event(queueSequence: 13, authority: terminalAuthority)
        ]
        let result = try retire(
            &events,
            currentTail: 13,
            horizonQueueCutoff: 12
        )

        let error = capturedResolutionError {
            _ = try Resolution.resolve(
                currentResolvedThroughQueueSequence: 12,
                currentLastEnqueuedEventSequence: 13,
                retirementReceipt: result.receipt,
                terminalGate: PassiveCoreBluetoothObservationBoundaryQueueGate()
            )
        }

        #expect(error == .terminalHorizonRequired)
    }

    @Test
    func differentTerminalTransactionCannotResolveRetirementReceipt() throws {
        var events = [
            Event(queueSequence: 13, authority: terminalAuthority)
        ]
        let result = try retire(
            &events,
            currentTail: 13,
            horizonQueueCutoff: 12
        )
        let differentTerminalGate = try terminalGate(horizonQueueCutoff: 13)

        let error = capturedResolutionError {
            _ = try Resolution.resolve(
                currentResolvedThroughQueueSequence: 12,
                currentLastEnqueuedEventSequence: 13,
                retirementReceipt: result.receipt,
                terminalGate: differentTerminalGate
            )
        }

        #expect(error == .staleTerminalTransaction)
    }

    @Test
    func differentTerminalAuthorityCannotResolveRetirementReceipt() throws {
        var events = [
            Event(queueSequence: 13, authority: terminalAuthority)
        ]
        let result = try retire(
            &events,
            currentTail: 13,
            horizonQueueCutoff: 12
        )
        let foreignAuthority = PassiveCoreBluetoothArtifactAuthorityContext(
            targetSessionGeneration: 5,
            authorityGeneration: 1
        )
        let foreignTerminalGate = try terminalGate(
            horizonQueueCutoff: 12,
            authority: foreignAuthority
        )

        let error = capturedResolutionError {
            _ = try Resolution.resolve(
                currentResolvedThroughQueueSequence: 12,
                currentLastEnqueuedEventSequence: 13,
                retirementReceipt: result.receipt,
                terminalGate: foreignTerminalGate
            )
        }

        #expect(error == .staleTerminalTransaction)
    }

    @Test
    func callbackAfterRetirementInvalidatesQueueTailProof() throws {
        var events = [
            Event(queueSequence: 13, authority: terminalAuthority),
            Event(queueSequence: 14, authority: terminalAuthority)
        ]
        let result = try retire(
            &events,
            currentTail: 14,
            horizonQueueCutoff: 12
        )
        #expect(events.isEmpty)

        let error = capturedResolutionError {
            _ = try Resolution.resolve(
                currentResolvedThroughQueueSequence: 12,
                currentLastEnqueuedEventSequence: 15,
                retirementReceipt: result.receipt,
                terminalGate: result.terminalGate
            )
        }

        #expect(
            error == .controllerQueueChangedAfterRetirement(
                expected: 14,
                actual: 15
            )
        )
    }

    @Test
    func retainedEvidenceCannotBeDeclaredResolvedByRetirementAlone() throws {
        let newerAuthority = PassiveCoreBluetoothArtifactAuthorityContext(
            targetSessionGeneration: 4,
            authorityGeneration: 10
        )
        var events = [
            Event(queueSequence: 13, authority: terminalAuthority),
            Event(queueSequence: 14, authority: newerAuthority)
        ]
        let result = try retire(
            &events,
            currentTail: 14,
            horizonQueueCutoff: 12
        )
        #expect(events.map(\.queueSequence) == [14])
        #expect(result.receipt.requiresRetainedEvidenceRoutingBeforeReopen)

        let error = capturedResolutionError {
            _ = try Resolution.resolve(
                currentResolvedThroughQueueSequence: 12,
                currentLastEnqueuedEventSequence: 14,
                retirementReceipt: result.receipt,
                terminalGate: result.terminalGate
            )
        }

        #expect(error == .retainedEvidenceRoutingRequired(retainedCount: 1))
    }

    @Test
    func unresolvedPrefixBeforeHorizonFailsClosed() throws {
        var events = [
            Event(queueSequence: 13, authority: terminalAuthority)
        ]
        let result = try retire(
            &events,
            currentTail: 13,
            horizonQueueCutoff: 12
        )

        let error = capturedResolutionError {
            _ = try Resolution.resolve(
                currentResolvedThroughQueueSequence: 11,
                currentLastEnqueuedEventSequence: 13,
                retirementReceipt: result.receipt,
                terminalGate: result.terminalGate
            )
        }

        #expect(
            error == .resolvedFrontierDoesNotMatchHorizon(
                current: 11,
                horizon: 12
            )
        )
    }

    @Test
    func frontierAlreadyPastHorizonCannotReplayRetirementReceipt() throws {
        var events = [
            Event(queueSequence: 13, authority: terminalAuthority),
            Event(queueSequence: 14, authority: terminalAuthority)
        ]
        let result = try retire(
            &events,
            currentTail: 14,
            horizonQueueCutoff: 12
        )
        let first = try Resolution.resolve(
            currentResolvedThroughQueueSequence: 12,
            currentLastEnqueuedEventSequence: 14,
            retirementReceipt: result.receipt,
            terminalGate: result.terminalGate
        )

        let error = capturedResolutionError {
            _ = try Resolution.resolve(
                currentResolvedThroughQueueSequence: first.resolvedThroughQueueSequence,
                currentLastEnqueuedEventSequence: 14,
                retirementReceipt: result.receipt,
                terminalGate: result.terminalGate
            )
        }

        #expect(
            error == .resolvedFrontierDoesNotMatchHorizon(
                current: 14,
                horizon: 12
            )
        )
    }

    private func retire(
        _ events: inout [Event],
        currentTail: UInt64,
        horizonQueueCutoff: UInt64
    ) throws -> (
        receipt: Retirement.Receipt,
        terminalGate: PassiveCoreBluetoothObservationBoundaryQueueGate
    ) {
        let gate = try terminalGate(horizonQueueCutoff: horizonQueueCutoff)
        let receipt = try Retirement.retire(
            from: &events,
            currentLastEnqueuedEventSequence: currentTail,
            terminalGate: gate,
            identity: { event in
                Retirement.PendingEvidenceIdentity(
                    queueSequence: event.queueSequence,
                    authority: event.authority
                )
            }
        )
        return (receipt, gate)
    }

    private func terminalGate(
        horizonQueueCutoff: UInt64,
        authority: PassiveCoreBluetoothArtifactAuthorityContext? = nil
    ) throws -> PassiveCoreBluetoothObservationBoundaryQueueGate {
        let boundaryAuthority = authority ?? terminalAuthority
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let ready = try gate.begin(
            .finiteAcquisitionReady,
            through: 5,
            authority: boundaryAuthority
        )
        try gate.markBoundaryRecorded(
            ready,
            lastProcessedQueueSequence: 5,
            currentAuthority: boundaryAuthority
        )
        let horizon = try gate.beginObservationHorizon(
            through: horizonQueueCutoff,
            processedThrough: 8,
            authority: boundaryAuthority,
            establishedByReadyRevision: ready.revision,
            establishedByReadyIdentity: ready.identity
        )
        try gate.markBoundaryRecorded(
            horizon,
            lastProcessedQueueSequence: horizonQueueCutoff,
            currentAuthority: boundaryAuthority
        )
        try gate.completeHorizonArtifactFreeze(
            horizon,
            currentAuthority: boundaryAuthority
        )
        return gate
    }

    private func capturedResolutionError(
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
