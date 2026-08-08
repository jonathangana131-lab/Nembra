import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Terminal retirement and resolved FIFO on current sealed Horizon typestate")
struct PassiveCoreBluetoothTerminalQueueCurrentCompositionTests {
    private typealias Retirement = PassiveCoreBluetoothTerminalQueueRetirement
    private typealias Resolution = PassiveCoreBluetoothTerminalQueueResolution

    private struct PendingEvent: Equatable {
        let queueSequence: UInt64
        let authority: PassiveCoreBluetoothArtifactAuthorityContext
    }

    private let authority = PassiveCoreBluetoothArtifactAuthorityContext(
        targetSessionGeneration: 7,
        authorityGeneration: 11
    )

    private let vehicle = VehicleIdentity(
        manufacturer: "AOVOPRO",
        model: "ES80",
        displayName: "AOVOPRO ES80",
        protocolFamily: "Tuya / AOVOPRO (hardware validation pending)"
    )

    @Test("terminal H retires the exact contiguous suffix then resolves it without calling it recorder-written")
    @MainActor
    func terminalSuffixRetiresThenResolves() async throws {
        let gate = try await terminalGate(horizonQueueCutoff: 12)
        var pending = [
            PendingEvent(queueSequence: 13, authority: authority),
            PendingEvent(queueSequence: 14, authority: authority)
        ]

        let retirement = try Retirement.retire(
            from: &pending,
            currentLastEnqueuedEventSequence: 14,
            terminalGate: gate,
            identity: identity
        )

        #expect(pending.isEmpty)
        #expect(retirement.terminalAuthority == authority)
        #expect(retirement.horizonQueueCutoff == 12)
        #expect(retirement.validatedQueueTailSequence == 14)
        #expect(retirement.retiredEvidenceCount == 2)
        #expect(retirement.firstRetiredQueueSequence == 13)
        #expect(retirement.lastRetiredQueueSequence == 14)
        #expect(!retirement.requiresRetainedEvidenceRoutingBeforeReopen)

        let resolution = try Resolution.resolve(
            currentResolvedThroughQueueSequence: 12,
            currentLastEnqueuedEventSequence: 14,
            retirementReceipt: retirement,
            terminalGate: gate
        )

        #expect(resolution.terminalAuthority == authority)
        #expect(resolution.horizonQueueCutoff == 12)
        #expect(resolution.previouslyResolvedThroughQueueSequence == 12)
        #expect(resolution.resolvedThroughQueueSequence == 14)
        #expect(resolution.retiredEvidenceCount == 2)
        #expect(resolution.advancesResolvedFrontier)
    }

    @Test("retained foreign authority evidence blocks resolution instead of being destroyed or laundered")
    @MainActor
    func retainedEvidenceRequiresSeparateRoutingAuthority() async throws {
        let gate = try await terminalGate(horizonQueueCutoff: 12)
        let foreign = PassiveCoreBluetoothArtifactAuthorityContext(
            targetSessionGeneration: 8,
            authorityGeneration: 1
        )
        var pending = [
            PendingEvent(queueSequence: 13, authority: authority),
            PendingEvent(queueSequence: 14, authority: foreign)
        ]

        let retirement = try Retirement.retire(
            from: &pending,
            currentLastEnqueuedEventSequence: 14,
            terminalGate: gate,
            identity: identity
        )

        #expect(pending == [PendingEvent(queueSequence: 14, authority: foreign)])
        #expect(retirement.retiredEvidenceCount == 1)
        #expect(retirement.retainedPendingEvidenceCount == 1)
        #expect(retirement.requiresRetainedEvidenceRoutingBeforeReopen)

        #expect(
            throws: Resolution.StateError.retainedEvidenceRoutingRequired(retainedCount: 1)
        ) {
            _ = try Resolution.resolve(
                currentResolvedThroughQueueSequence: 12,
                currentLastEnqueuedEventSequence: 14,
                retirementReceipt: retirement,
                terminalGate: gate
            )
        }
    }

    @Test("a callback accepted after retirement invalidates the receipt before FIFO resolution")
    @MainActor
    func queueTailDriftRejectsResolution() async throws {
        let gate = try await terminalGate(horizonQueueCutoff: 12)
        var pending = [PendingEvent(queueSequence: 13, authority: authority)]

        let retirement = try Retirement.retire(
            from: &pending,
            currentLastEnqueuedEventSequence: 13,
            terminalGate: gate,
            identity: identity
        )
        #expect(pending.isEmpty)

        #expect(
            throws: Resolution.StateError.controllerQueueChangedAfterRetirement(
                expected: 13,
                actual: 14
            )
        ) {
            _ = try Resolution.resolve(
                currentResolvedThroughQueueSequence: 12,
                currentLastEnqueuedEventSequence: 14,
                retirementReceipt: retirement,
                terminalGate: gate
            )
        }
    }

    @Test("pending evidence at or before H fails atomically on the current sealed gate")
    @MainActor
    func terminalPrefixResidueFailsWithoutMutation() async throws {
        let gate = try await terminalGate(horizonQueueCutoff: 12)
        var pending = [
            PendingEvent(queueSequence: 12, authority: authority),
            PendingEvent(queueSequence: 13, authority: authority)
        ]
        let before = pending

        #expect(throws: Retirement.StateError.terminalPrefixStillPending(queueSequence: 12)) {
            _ = try Retirement.retire(
                from: &pending,
                currentLastEnqueuedEventSequence: 13,
                terminalGate: gate,
                identity: identity
            )
        }
        #expect(pending == before)
    }

    @MainActor
    private func terminalGate(
        horizonQueueCutoff: UInt64
    ) async throws -> PassiveCoreBluetoothObservationBoundaryQueueGate {
        let recorder = try PassiveCoreBluetoothCaptureRecorder(
            vehicleIdentity: vehicle,
            startedAt: Date(timeIntervalSince1970: 1)
        )
        let fence = PassiveCoreBluetoothArtifactAuthorityFence(authority: authority)
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()

        let ready = try PassiveCoreBluetoothObservationBoundaryTransactionDecision.beginReady(
            queueCutoff: 5,
            processedThrough: 5,
            authorityFence: fence,
            gate: &gate
        )
        let recordedReady = try await ready.recordBoundary(on: recorder)
        let committedReady = try recordedReady.markBoundaryRecorded(
            on: &gate,
            lastProcessedQueueSequence: 5
        )
        let horizon = try committedReady.beginHorizon(
            queueCutoff: horizonQueueCutoff,
            processedThrough: 8,
            gate: &gate
        )
        let recordedHorizon = try await horizon.recordBoundary(on: recorder)
        let committedHorizon = try recordedHorizon.markBoundaryRecorded(
            on: &gate,
            lastProcessedQueueSequence: horizonQueueCutoff
        )
        try committedHorizon.completeHorizonArtifactFreeze(on: &gate)
        #expect(gate.isTerminal)
        return gate
    }

    private func identity(_ event: PendingEvent) -> Retirement.PendingEvidenceIdentity {
        Retirement.PendingEvidenceIdentity(
            queueSequence: event.queueSequence,
            authority: event.authority
        )
    }
}
