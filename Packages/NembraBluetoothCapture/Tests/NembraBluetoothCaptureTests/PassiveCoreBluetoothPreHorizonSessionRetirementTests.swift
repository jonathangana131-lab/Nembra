import Testing
@testable import NembraBluetoothCapture

@Suite("Pre-Horizon target-session retirement")
struct PassiveCoreBluetoothPreHorizonSessionRetirementTests {
    private struct Event: Equatable {
        let queueSequence: UInt64
        let targetSessionGeneration: UInt64
    }

    private static let authority = PassiveCoreBluetoothArtifactAuthorityContext(
        targetSessionGeneration: 7,
        authorityGeneration: 3
    )

    @MainActor
    private static func observingGate() throws -> PassiveCoreBluetoothObservationBoundaryQueueGate {
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let ready = try gate.begin(
            .finiteAcquisitionReady,
            through: 10,
            authority: authority
        )
        try gate.markBoundaryRecorded(
            ready,
            lastProcessedQueueSequence: 10,
            currentAuthority: authority
        )
        return gate
    }

    @MainActor
    private static func drainingReadyGate() throws -> PassiveCoreBluetoothObservationBoundaryQueueGate {
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        _ = try gate.begin(
            .finiteAcquisitionReady,
            through: 10,
            authority: authority
        )
        return gate
    }

    @MainActor
    private static func drainingHorizonGate() throws -> PassiveCoreBluetoothObservationBoundaryQueueGate {
        var gate = try observingGate()
        _ = try gate.begin(
            .observationHorizon,
            through: 12,
            processedThrough: 10,
            authority: authority
        )
        return gate
    }

    @MainActor
    private static func horizonBoundaryRecordedGate() throws -> PassiveCoreBluetoothObservationBoundaryQueueGate {
        var gate = try observingGate()
        let horizon = try gate.begin(
            .observationHorizon,
            through: 12,
            processedThrough: 10,
            authority: authority
        )
        try gate.markBoundaryRecorded(
            horizon,
            lastProcessedQueueSequence: 12,
            currentAuthority: authority
        )
        return gate
    }

    @MainActor
    private static func terminalGate() throws -> PassiveCoreBluetoothObservationBoundaryQueueGate {
        var gate = try horizonBoundaryRecordedGate()
        guard case let .horizonBoundaryRecorded(horizon) = gate.phase else {
            Issue.record("expected horizonBoundaryRecorded")
            return gate
        }
        try gate.completeHorizonArtifactFreeze(
            horizon,
            currentAuthority: authority
        )
        return gate
    }

    private static func identity(
        _ event: Event
    ) -> PassiveCoreBluetoothPreHorizonSessionRetirement.PendingEvidenceIdentity {
        .init(
            queueSequence: event.queueSequence,
            targetSessionGeneration: event.targetSessionGeneration
        )
    }

    @Test("observing epoch retires the exact contiguous abandoned-session suffix")
    @MainActor
    func observingRetirementProducesFreshSessionReceipt() throws {
        let gate = try Self.observingGate()
        var pending = [
            Event(queueSequence: 11, targetSessionGeneration: 7),
            Event(queueSequence: 12, targetSessionGeneration: 7),
            Event(queueSequence: 13, targetSessionGeneration: 7),
        ]

        let receipt = try PassiveCoreBluetoothPreHorizonSessionRetirement.retire(
            from: &pending,
            boundaryGate: gate,
            abortedTargetSessionGeneration: 7,
            lastProcessedQueueSequence: 10,
            lastEnqueuedQueueSequence: 13,
            identity: Self.identity
        )

        #expect(pending.isEmpty)
        #expect(receipt.abortedPhase == .observing)
        #expect(receipt.abortedTargetSessionGeneration == 7)
        #expect(receipt.validatedProcessedQueueSequence == 10)
        #expect(receipt.validatedQueueTailSequence == 13)
        #expect(receipt.retiredEvidenceCount == 3)
        #expect(receipt.firstRetiredQueueSequence == 11)
        #expect(receipt.lastRetiredQueueSequence == 13)

        try PassiveCoreBluetoothPreHorizonSessionRetirement.validateFreshSessionAdmission(
            receipt: receipt,
            currentLastEnqueuedQueueSequence: 13,
            proposedTargetSessionGeneration: 8
        )
    }

    @Test("fully drained observing epoch may retire with an empty pending suffix")
    @MainActor
    func emptyPendingSuffixIsValidOnlyAtTheExactTail() throws {
        let gate = try Self.observingGate()
        var pending: [Event] = []

        let receipt = try PassiveCoreBluetoothPreHorizonSessionRetirement.retire(
            from: &pending,
            boundaryGate: gate,
            abortedTargetSessionGeneration: 7,
            lastProcessedQueueSequence: 10,
            lastEnqueuedQueueSequence: 10,
            identity: Self.identity
        )

        #expect(receipt.retiredEvidenceCount == 0)
        #expect(receipt.firstRetiredQueueSequence == nil)
        #expect(receipt.lastRetiredQueueSequence == nil)
        #expect(receipt.validatedQueueTailSequence == 10)
    }

    @Test("retirement supports every incomplete lifecycle after Ready has begun")
    @MainActor
    func supportedPreHorizonPhases() throws {
        var drainingReadyPending = [Event(queueSequence: 11, targetSessionGeneration: 7)]
        let drainingReadyReceipt = try PassiveCoreBluetoothPreHorizonSessionRetirement.retire(
            from: &drainingReadyPending,
            boundaryGate: Self.drainingReadyGate(),
            abortedTargetSessionGeneration: 7,
            lastProcessedQueueSequence: 10,
            lastEnqueuedQueueSequence: 11,
            identity: Self.identity
        )
        #expect(drainingReadyReceipt.abortedPhase == .drainingReady)

        var drainingHorizonPending = [
            Event(queueSequence: 11, targetSessionGeneration: 7),
            Event(queueSequence: 12, targetSessionGeneration: 7),
        ]
        let drainingHorizonReceipt = try PassiveCoreBluetoothPreHorizonSessionRetirement.retire(
            from: &drainingHorizonPending,
            boundaryGate: Self.drainingHorizonGate(),
            abortedTargetSessionGeneration: 7,
            lastProcessedQueueSequence: 10,
            lastEnqueuedQueueSequence: 12,
            identity: Self.identity
        )
        #expect(drainingHorizonReceipt.abortedPhase == .drainingHorizon)

        var recordedPending = [Event(queueSequence: 13, targetSessionGeneration: 7)]
        let recordedReceipt = try PassiveCoreBluetoothPreHorizonSessionRetirement.retire(
            from: &recordedPending,
            boundaryGate: Self.horizonBoundaryRecordedGate(),
            abortedTargetSessionGeneration: 7,
            lastProcessedQueueSequence: 12,
            lastEnqueuedQueueSequence: 13,
            identity: Self.identity
        )
        #expect(recordedReceipt.abortedPhase == .horizonBoundaryRecorded)
    }

    @Test("awaiting-Ready and terminal lifecycles use different reset/retirement contracts")
    @MainActor
    func unrelatedLifecyclePhasesFailClosed() throws {
        var awaitingPending = [Event(queueSequence: 1, targetSessionGeneration: 7)]
        let awaitingOriginal = awaitingPending
        do {
            try PassiveCoreBluetoothPreHorizonSessionRetirement.retire(
                from: &awaitingPending,
                boundaryGate: PassiveCoreBluetoothObservationBoundaryQueueGate(),
                abortedTargetSessionGeneration: 7,
                lastProcessedQueueSequence: 0,
                lastEnqueuedQueueSequence: 1,
                identity: Self.identity
            )
            Issue.record("awaiting-Ready retirement should fail")
        } catch let error as PassiveCoreBluetoothPreHorizonSessionRetirement.StateError {
            #expect(error == .preHorizonLifecycleRequired)
        }
        #expect(awaitingPending == awaitingOriginal)

        var terminalPending = [Event(queueSequence: 13, targetSessionGeneration: 7)]
        let terminalOriginal = terminalPending
        do {
            try PassiveCoreBluetoothPreHorizonSessionRetirement.retire(
                from: &terminalPending,
                boundaryGate: Self.terminalGate(),
                abortedTargetSessionGeneration: 7,
                lastProcessedQueueSequence: 12,
                lastEnqueuedQueueSequence: 13,
                identity: Self.identity
            )
            Issue.record("terminal retirement should use the terminal-Horizon contract")
        } catch let error as PassiveCoreBluetoothPreHorizonSessionRetirement.StateError {
            #expect(error == .preHorizonLifecycleRequired)
        }
        #expect(terminalPending == terminalOriginal)
    }

    @Test("an empty pending array cannot hide an in-flight queue item")
    @MainActor
    func missingPendingSuffixFailsAtomically() throws {
        let gate = try Self.observingGate()
        var pending: [Event] = []

        do {
            try PassiveCoreBluetoothPreHorizonSessionRetirement.retire(
                from: &pending,
                boundaryGate: gate,
                abortedTargetSessionGeneration: 7,
                lastProcessedQueueSequence: 10,
                lastEnqueuedQueueSequence: 11,
                identity: Self.identity
            )
            Issue.record("unaccounted queue range should fail")
        } catch let error as PassiveCoreBluetoothPreHorizonSessionRetirement.StateError {
            #expect(error == .unaccountedQueueRange(processedThrough: 10, queueTail: 11))
        }
        #expect(pending.isEmpty)
    }

    @Test("a gap inside the pending FIFO exposes an in-flight or missing callback")
    @MainActor
    func nonContiguousPendingSuffixFailsAtomically() throws {
        let gate = try Self.observingGate()
        var pending = [
            Event(queueSequence: 11, targetSessionGeneration: 7),
            Event(queueSequence: 13, targetSessionGeneration: 7),
        ]
        let original = pending

        do {
            try PassiveCoreBluetoothPreHorizonSessionRetirement.retire(
                from: &pending,
                boundaryGate: gate,
                abortedTargetSessionGeneration: 7,
                lastProcessedQueueSequence: 10,
                lastEnqueuedQueueSequence: 13,
                identity: Self.identity
            )
            Issue.record("queue gap should fail")
        } catch let error as PassiveCoreBluetoothPreHorizonSessionRetirement.StateError {
            #expect(error == .nonContiguousQueueSequence(expected: 12, actual: 13))
        }
        #expect(pending == original)
    }

    @Test("foreign target-session evidence is never collateral retirement")
    @MainActor
    func foreignSessionEvidenceFailsAtomically() throws {
        let gate = try Self.observingGate()
        var pending = [
            Event(queueSequence: 11, targetSessionGeneration: 7),
            Event(queueSequence: 12, targetSessionGeneration: 8),
            Event(queueSequence: 13, targetSessionGeneration: 7),
        ]
        let original = pending

        do {
            try PassiveCoreBluetoothPreHorizonSessionRetirement.retire(
                from: &pending,
                boundaryGate: gate,
                abortedTargetSessionGeneration: 7,
                lastProcessedQueueSequence: 10,
                lastEnqueuedQueueSequence: 13,
                identity: Self.identity
            )
            Issue.record("foreign target-session evidence should fail")
        } catch let error as PassiveCoreBluetoothPreHorizonSessionRetirement.StateError {
            #expect(error == .foreignSessionEvidence(queueSequence: 12, targetSessionGeneration: 8))
        }
        #expect(pending == original)
    }

    @Test("pending FIFO must reach the exact controller queue tail")
    @MainActor
    func pendingTailMismatchFailsAtomically() throws {
        let gate = try Self.observingGate()
        var pending = [
            Event(queueSequence: 11, targetSessionGeneration: 7),
            Event(queueSequence: 12, targetSessionGeneration: 7),
        ]
        let original = pending

        do {
            try PassiveCoreBluetoothPreHorizonSessionRetirement.retire(
                from: &pending,
                boundaryGate: gate,
                abortedTargetSessionGeneration: 7,
                lastProcessedQueueSequence: 10,
                lastEnqueuedQueueSequence: 13,
                identity: Self.identity
            )
            Issue.record("tail mismatch should fail")
        } catch let error as PassiveCoreBluetoothPreHorizonSessionRetirement.StateError {
            #expect(error == .queueTailMismatch(expected: 13, actual: 12))
        }
        #expect(pending == original)
    }

    @Test("queue chronology cannot continue after UInt64 max")
    @MainActor
    func exhaustedQueueSequenceRejectsDuplicateMaxAtomically() throws {
        let gate = try Self.observingGate()
        var pending = [
            Event(queueSequence: UInt64.max, targetSessionGeneration: 7),
            Event(queueSequence: UInt64.max, targetSessionGeneration: 7),
        ]
        let original = pending

        do {
            try PassiveCoreBluetoothPreHorizonSessionRetirement.retire(
                from: &pending,
                boundaryGate: gate,
                abortedTargetSessionGeneration: 7,
                lastProcessedQueueSequence: UInt64.max - 1,
                lastEnqueuedQueueSequence: UInt64.max,
                identity: Self.identity
            )
            Issue.record("duplicate max chronology should fail")
        } catch let error as PassiveCoreBluetoothPreHorizonSessionRetirement.StateError {
            #expect(error == .queueSequenceExhausted)
        }
        #expect(pending == original)
    }

    @Test("fresh-session admission rejects any callback after retirement")
    @MainActor
    func receiptBecomesStaleWhenQueueTailAdvances() throws {
        let gate = try Self.observingGate()
        var pending = [Event(queueSequence: 11, targetSessionGeneration: 7)]
        let receipt = try PassiveCoreBluetoothPreHorizonSessionRetirement.retire(
            from: &pending,
            boundaryGate: gate,
            abortedTargetSessionGeneration: 7,
            lastProcessedQueueSequence: 10,
            lastEnqueuedQueueSequence: 11,
            identity: Self.identity
        )

        do {
            try PassiveCoreBluetoothPreHorizonSessionRetirement.validateFreshSessionAdmission(
                receipt: receipt,
                currentLastEnqueuedQueueSequence: 12,
                proposedTargetSessionGeneration: 8
            )
            Issue.record("advanced queue tail should stale the receipt")
        } catch let error as PassiveCoreBluetoothPreHorizonSessionRetirement.StateError {
            #expect(error == .staleRetirementReceipt(expectedQueueTail: 11, currentQueueTail: 12))
        }
    }

    @Test("fresh session must be the exact next target-session generation")
    @MainActor
    func receiptCannotSkipOrReuseSessionGeneration() throws {
        let gate = try Self.observingGate()
        var pending = [Event(queueSequence: 11, targetSessionGeneration: 7)]
        let receipt = try PassiveCoreBluetoothPreHorizonSessionRetirement.retire(
            from: &pending,
            boundaryGate: gate,
            abortedTargetSessionGeneration: 7,
            lastProcessedQueueSequence: 10,
            lastEnqueuedQueueSequence: 11,
            identity: Self.identity
        )

        for proposedGeneration: UInt64 in [7, 9] {
            do {
                try PassiveCoreBluetoothPreHorizonSessionRetirement.validateFreshSessionAdmission(
                    receipt: receipt,
                    currentLastEnqueuedQueueSequence: 11,
                    proposedTargetSessionGeneration: proposedGeneration
                )
                Issue.record("non-successor target-session generation should fail")
            } catch let error as PassiveCoreBluetoothPreHorizonSessionRetirement.StateError {
                #expect(
                    error == .invalidFreshSessionGeneration(
                        aborted: 7,
                        proposed: proposedGeneration
                    )
                )
            }
        }
    }

    @Test("zero target-session generation is never an abort authority")
    @MainActor
    func zeroSessionGenerationFailsWithoutMutation() throws {
        let gate = try Self.observingGate()
        var pending = [Event(queueSequence: 11, targetSessionGeneration: 0)]
        let original = pending

        do {
            try PassiveCoreBluetoothPreHorizonSessionRetirement.retire(
                from: &pending,
                boundaryGate: gate,
                abortedTargetSessionGeneration: 0,
                lastProcessedQueueSequence: 10,
                lastEnqueuedQueueSequence: 11,
                identity: Self.identity
            )
            Issue.record("zero target-session generation should fail")
        } catch let error as PassiveCoreBluetoothPreHorizonSessionRetirement.StateError {
            #expect(error == .invalidAbortedSessionGeneration)
        }
        #expect(pending == original)
    }
}
