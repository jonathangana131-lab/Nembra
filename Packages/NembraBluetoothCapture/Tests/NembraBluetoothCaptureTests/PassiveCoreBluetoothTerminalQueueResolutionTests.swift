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
        let retirement = try retire(
            &events,
            currentTail: 14,
            horizonQueueCutoff: 12
        )
        #expect(events.isEmpty)
        #expect(retirement.retiredEvidenceCount == 2)
        #expect(!retirement.requiresRetainedEvidenceRoutingBeforeReopen)

        let resolution = try Resolution.resolve(
            currentResolvedThroughQueueSequence: 12,
            retirementReceipt: retirement
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
        let retirement = try retire(
            &events,
            currentTail: 12,
            horizonQueueCutoff: 12
        )

        let resolution = try Resolution.resolve(
            currentResolvedThroughQueueSequence: 12,
            retirementReceipt: retirement
        )

        #expect(resolution.horizonQueueCutoff == 12)
        #expect(resolution.previouslyResolvedThroughQueueSequence == 12)
        #expect(resolution.resolvedThroughQueueSequence == 12)
        #expect(resolution.retiredEvidenceCount == 0)
        #expect(!resolution.advancesResolvedFrontier)
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
        let retirement = try retire(
            &events,
            currentTail: 14,
            horizonQueueCutoff: 12
        )
        #expect(events.map(\.queueSequence) == [14])
        #expect(retirement.requiresRetainedEvidenceRoutingBeforeReopen)

        let error = capturedResolutionError {
            _ = try Resolution.resolve(
                currentResolvedThroughQueueSequence: 12,
                retirementReceipt: retirement
            )
        }

        #expect(error == .retainedEvidenceRoutingRequired(retainedCount: 1))
    }

    @Test
    func unresolvedPrefixBeforeHorizonFailsClosed() throws {
        var events = [
            Event(queueSequence: 13, authority: terminalAuthority)
        ]
        let retirement = try retire(
            &events,
            currentTail: 13,
            horizonQueueCutoff: 12
        )

        let error = capturedResolutionError {
            _ = try Resolution.resolve(
                currentResolvedThroughQueueSequence: 11,
                retirementReceipt: retirement
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
        let retirement = try retire(
            &events,
            currentTail: 14,
            horizonQueueCutoff: 12
        )
        let first = try Resolution.resolve(
            currentResolvedThroughQueueSequence: 12,
            retirementReceipt: retirement
        )

        let error = capturedResolutionError {
            _ = try Resolution.resolve(
                currentResolvedThroughQueueSequence: first.resolvedThroughQueueSequence,
                retirementReceipt: retirement
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
    ) throws -> Retirement.Receipt {
        try Retirement.retire(
            from: &events,
            currentLastEnqueuedEventSequence: currentTail,
            terminalGate: try terminalGate(horizonQueueCutoff: horizonQueueCutoff),
            identity: { event in
                Retirement.PendingEvidenceIdentity(
                    queueSequence: event.queueSequence,
                    authority: event.authority
                )
            }
        )
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
        let horizon = try gate.begin(
            .observationHorizon,
            through: horizonQueueCutoff,
            processedThrough: 8,
            authority: terminalAuthority
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
