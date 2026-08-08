import Testing
@testable import NembraBluetoothCapture

@MainActor
struct PassiveCoreBluetoothTerminalQueueRetirementTests {
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

        let receipt = try PassiveCoreBluetoothTerminalQueueRetirement.retire(
            from: &events,
            terminalGate: try terminalGate(horizonQueueCutoff: 12),
            identity: identity
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
    }

    @Test
    func terminalPrefixStillPendingFailsWithoutMutation() throws {
        var events = [
            Event(queueSequence: 12, authority: terminalAuthority, label: "at-h"),
            Event(queueSequence: 13, authority: terminalAuthority, label: "post-h")
        ]
        let before = events

        do {
            _ = try PassiveCoreBluetoothTerminalQueueRetirement.retire(
                from: &events,
                terminalGate: try terminalGate(horizonQueueCutoff: 12),
                identity: identity
            )
            Issue.record("Expected terminal-prefix retirement to fail closed.")
        } catch {
            #expect(
                error as? PassiveCoreBluetoothTerminalQueueRetirement.StateError
                    == .terminalPrefixStillPending(queueSequence: 12)
            )
        }

        #expect(events == before)
    }

    @Test
    func preHorizonTerminalAuthorityFailsWithoutMutation() throws {
        var events = [
            Event(queueSequence: 11, authority: terminalAuthority, label: "pre-h"),
            Event(queueSequence: 13, authority: terminalAuthority, label: "post-h")
        ]
        let before = events

        do {
            _ = try PassiveCoreBluetoothTerminalQueueRetirement.retire(
                from: &events,
                terminalGate: try terminalGate(horizonQueueCutoff: 12),
                identity: identity
            )
            Issue.record("Expected an undrained pre-H event to fail closed.")
        } catch {
            #expect(
                error as? PassiveCoreBluetoothTerminalQueueRetirement.StateError
                    == .terminalPrefixStillPending(queueSequence: 11)
            )
        }

        #expect(events == before)
    }

    @Test
    func foreignAuthorityAtOrBeforeHorizonAlsoFailsWithoutMutation() throws {
        let foreignAuthority = PassiveCoreBluetoothArtifactAuthorityContext(
            targetSessionGeneration: 5,
            authorityGeneration: 10
        )
        var events = [
            Event(queueSequence: 12, authority: foreignAuthority, label: "foreign-at-h"),
            Event(queueSequence: 13, authority: terminalAuthority, label: "post-h")
        ]
        let before = events

        do {
            _ = try PassiveCoreBluetoothTerminalQueueRetirement.retire(
                from: &events,
                terminalGate: try terminalGate(horizonQueueCutoff: 12),
                identity: identity
            )
            Issue.record("Expected any undrained global FIFO prefix to fail closed.")
        } catch {
            #expect(
                error as? PassiveCoreBluetoothTerminalQueueRetirement.StateError
                    == .terminalPrefixStillPending(queueSequence: 12)
            )
        }

        #expect(events == before)
    }

    @Test
    func nonterminalGateFailsWithoutMutation() throws {
        var events = [
            Event(queueSequence: 13, authority: terminalAuthority, label: "old")
        ]
        let before = events

        do {
            _ = try PassiveCoreBluetoothTerminalQueueRetirement.retire(
                from: &events,
                terminalGate: PassiveCoreBluetoothObservationBoundaryQueueGate(),
                identity: identity
            )
            Issue.record("Expected nonterminal retirement to fail closed.")
        } catch {
            #expect(
                error as? PassiveCoreBluetoothTerminalQueueRetirement.StateError
                    == .terminalHorizonRequired
            )
        }

        #expect(events == before)
    }

    @Test
    func duplicateSequenceFailsWithoutMutation() throws {
        var events = [
            Event(queueSequence: 14, authority: terminalAuthority, label: "a"),
            Event(queueSequence: 14, authority: terminalAuthority, label: "b")
        ]
        let before = events

        do {
            _ = try PassiveCoreBluetoothTerminalQueueRetirement.retire(
                from: &events,
                terminalGate: try terminalGate(horizonQueueCutoff: 12),
                identity: identity
            )
            Issue.record("Expected duplicate queue chronology to fail closed.")
        } catch {
            #expect(
                error as? PassiveCoreBluetoothTerminalQueueRetirement.StateError
                    == .nonIncreasingQueueSequence(previous: 14, current: 14)
            )
        }

        #expect(events == before)
    }

    @Test
    func regressingSequenceFailsWithoutMutation() throws {
        let newerAuthority = PassiveCoreBluetoothArtifactAuthorityContext(
            targetSessionGeneration: 4,
            authorityGeneration: 10
        )
        var events = [
            Event(queueSequence: 15, authority: newerAuthority, label: "newer"),
            Event(queueSequence: 14, authority: terminalAuthority, label: "older-sequence")
        ]
        let before = events

        do {
            _ = try PassiveCoreBluetoothTerminalQueueRetirement.retire(
                from: &events,
                terminalGate: try terminalGate(horizonQueueCutoff: 12),
                identity: identity
            )
            Issue.record("Expected regressing queue chronology to fail closed.")
        } catch {
            #expect(
                error as? PassiveCoreBluetoothTerminalQueueRetirement.StateError
                    == .nonIncreasingQueueSequence(previous: 15, current: 14)
            )
        }

        #expect(events == before)
    }

    @Test
    func zeroSequenceFailsWithoutMutation() throws {
        let newerAuthority = PassiveCoreBluetoothArtifactAuthorityContext(
            targetSessionGeneration: 4,
            authorityGeneration: 10
        )
        var events = [
            Event(queueSequence: 0, authority: newerAuthority, label: "invalid")
        ]
        let before = events

        do {
            _ = try PassiveCoreBluetoothTerminalQueueRetirement.retire(
                from: &events,
                terminalGate: try terminalGate(horizonQueueCutoff: 12),
                identity: identity
            )
            Issue.record("Expected zero queue sequence to fail closed.")
        } catch {
            #expect(
                error as? PassiveCoreBluetoothTerminalQueueRetirement.StateError
                    == .invalidQueueSequence(0)
            )
        }

        #expect(events == before)
    }

    @Test
    func emptyRetirementStillIssuesReceiptBoundToTerminalTransaction() throws {
        let newerAuthority = PassiveCoreBluetoothArtifactAuthorityContext(
            targetSessionGeneration: 4,
            authorityGeneration: 10
        )
        var events = [
            Event(queueSequence: 13, authority: newerAuthority, label: "new")
        ]

        let receipt = try PassiveCoreBluetoothTerminalQueueRetirement.retire(
            from: &events,
            terminalGate: try terminalGate(horizonQueueCutoff: 12),
            identity: identity
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
    }

    @Test
    func receiptKeepsValidatedGlobalTailWhenThatTailIsRetired() throws {
        let newerAuthority = PassiveCoreBluetoothArtifactAuthorityContext(
            targetSessionGeneration: 4,
            authorityGeneration: 10
        )
        var events = [
            Event(queueSequence: 13, authority: newerAuthority, label: "retained"),
            Event(queueSequence: 14, authority: terminalAuthority, label: "retired-tail")
        ]

        let receipt = try PassiveCoreBluetoothTerminalQueueRetirement.retire(
            from: &events,
            terminalGate: try terminalGate(horizonQueueCutoff: 12),
            identity: identity
        )

        #expect(events.map(\.label) == ["retained"])
        #expect(receipt.validatedQueueTailSequence == 14)
        #expect(receipt.lastRetiredQueueSequence == 14)
        #expect(receipt.retainedPendingEvidenceCount == 1)
    }

    @Test
    func emptyPendingQueueStillIssuesReceiptBoundToTerminalTransaction() throws {
        var events: [Event] = []

        let receipt = try PassiveCoreBluetoothTerminalQueueRetirement.retire(
            from: &events,
            terminalGate: try terminalGate(horizonQueueCutoff: 12),
            identity: identity
        )

        #expect(events.isEmpty)
        #expect(receipt.terminalAuthority == terminalAuthority)
        #expect(receipt.terminalTransactionRevision == 2)
        #expect(receipt.horizonQueueCutoff == 12)
        #expect(receipt.validatedQueueTailSequence == 12)
        #expect(receipt.retiredEvidenceCount == 0)
        #expect(receipt.retainedPendingEvidenceCount == 0)
    }

    private func identity(
        _ event: Event
    ) -> PassiveCoreBluetoothTerminalQueueRetirement.PendingEvidenceIdentity {
        PassiveCoreBluetoothTerminalQueueRetirement.PendingEvidenceIdentity(
            queueSequence: event.queueSequence,
            authority: event.authority
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
}
