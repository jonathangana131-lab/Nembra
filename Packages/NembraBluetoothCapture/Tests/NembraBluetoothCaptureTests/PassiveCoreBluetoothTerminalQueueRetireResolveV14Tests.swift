import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Terminal FIFO retirement and resolution V14")
struct PassiveCoreBluetoothTerminalQueueRetireResolveV14Tests {
    private typealias Retirement = PassiveCoreBluetoothTerminalQueueRetirement
    private typealias Resolution = PassiveCoreBluetoothTerminalQueueResolution

    private struct Event: Equatable {
        let queueSequence: UInt64
        let authority: PassiveCoreBluetoothArtifactAuthorityContext
        let label: String
    }

    private let authority = PassiveCoreBluetoothArtifactAuthorityContext(
        targetSessionGeneration: 7,
        authorityGeneration: 11
    )

    private let es80 = VehicleIdentity(
        manufacturer: "AOVOPRO",
        model: "ES80",
        displayName: "AOVOPRO ES80",
        protocolFamily: "Tuya / AOVOPRO (hardware validation pending)"
    )

    @Test("complete exact-authority suffix retires and resolves without recorder laundering")
    @MainActor
    func completeSuffixResolves() async throws {
        let gate = try await terminalGate(horizon: 12)
        let terminal = try #require(terminalTransaction(from: gate))
        var events = [
            Event(queueSequence: 13, authority: authority, label: "post-h-1"),
            Event(queueSequence: 14, authority: authority, label: "post-h-2")
        ]

        let retirement = try retire(&events, tail: 14, gate: gate)
        #expect(events.isEmpty)
        #expect(retirement.terminalTransactionRevision == terminal.revision)
        #expect(retirement.terminalTransactionIdentity == terminal.identity)
        #expect(retirement.horizonQueueCutoff == 12)
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
        #expect(resolution.terminalTransactionIdentity == terminal.identity)
        #expect(resolution.previouslyResolvedThroughQueueSequence == 12)
        #expect(resolution.resolvedThroughQueueSequence == 14)
        #expect(resolution.advancesResolvedFrontier)
        #expect(resolution.retiredEvidenceCount == 2)
    }

    @Test("equal-scalar foreign terminal cannot consume another gate's retirement")
    @MainActor
    func foreignTerminalIdentityFailsClosed() async throws {
        let gateA = try await terminalGate(horizon: 12)
        let gateB = try await terminalGate(horizon: 12)
        let terminalA = try #require(terminalTransaction(from: gateA))
        let terminalB = try #require(terminalTransaction(from: gateB))
        #expect(terminalA.revision == terminalB.revision)
        #expect(terminalA.queueCutoff == terminalB.queueCutoff)
        #expect(terminalA.authority == terminalB.authority)
        #expect(terminalA.identity != terminalB.identity)

        var events = [Event(queueSequence: 13, authority: authority, label: "post-h")]
        let retirement = try retire(&events, tail: 13, gate: gateA)
        #expect(events.isEmpty)

        #expect(throws: Resolution.StateError.staleTerminalTransaction) {
            _ = try Resolution.resolve(
                currentResolvedThroughQueueSequence: 12,
                currentLastEnqueuedEventSequence: 13,
                retirementReceipt: retirement,
                terminalGate: gateB
            )
        }
    }

    @Test("retained foreign authority blocks global resolution")
    @MainActor
    func retainedEvidenceRequiresSeparateRouting() async throws {
        let gate = try await terminalGate(horizon: 12)
        let foreign = PassiveCoreBluetoothArtifactAuthorityContext(
            targetSessionGeneration: authority.targetSessionGeneration + 1,
            authorityGeneration: 1
        )
        var events = [
            Event(queueSequence: 13, authority: authority, label: "retire"),
            Event(queueSequence: 14, authority: foreign, label: "retain")
        ]

        let retirement = try retire(&events, tail: 14, gate: gate)
        #expect(events.map(\.label) == ["retain"])
        #expect(retirement.retainedPendingEvidenceCount == 1)
        #expect(retirement.requiresRetainedEvidenceRoutingBeforeReopen)

        #expect(throws: Resolution.StateError.retainedEvidenceRoutingRequired(retainedCount: 1)) {
            _ = try Resolution.resolve(
                currentResolvedThroughQueueSequence: 12,
                currentLastEnqueuedEventSequence: 14,
                retirementReceipt: retirement,
                terminalGate: gate
            )
        }
    }

    @Test("callback tail drift after retirement invalidates resolution")
    @MainActor
    func tailDriftFailsClosed() async throws {
        let gate = try await terminalGate(horizon: 12)
        var events = [Event(queueSequence: 13, authority: authority, label: "post-h")]
        let retirement = try retire(&events, tail: 13, gate: gate)

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

    @Test("empty exact-H queue issues a no-op resolution receipt")
    @MainActor
    func exactHNoOpIsTruthful() async throws {
        let gate = try await terminalGate(horizon: 12)
        var events: [Event] = []
        let retirement = try retire(&events, tail: 12, gate: gate)
        #expect(retirement.retiredEvidenceCount == 0)
        #expect(retirement.validatedQueueTailSequence == 12)

        let resolution = try Resolution.resolve(
            currentResolvedThroughQueueSequence: 12,
            currentLastEnqueuedEventSequence: 12,
            retirementReceipt: retirement,
            terminalGate: gate
        )
        #expect(resolution.resolvedThroughQueueSequence == 12)
        #expect(!resolution.advancesResolvedFrontier)
    }

    @Test("FIFO gap fails retirement atomically")
    @MainActor
    func fifoGapFailsWithoutMutation() async throws {
        let gate = try await terminalGate(horizon: 12)
        var events = [Event(queueSequence: 14, authority: authority, label: "gap")]
        let before = events

        let error: Retirement.StateError?
        do {
            _ = try retire(&events, tail: 14, gate: gate)
            error = nil
        } catch let stateError as Retirement.StateError {
            error = stateError
        }
        #expect(
            error == .nonContiguousPendingQueueSequence(
                expected: 13,
                actual: 14
            )
        )
        #expect(events == before)
    }

    @MainActor
    private func terminalGate(
        horizon: UInt64
    ) async throws -> PassiveCoreBluetoothObservationBoundaryQueueGate {
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let fence = PassiveCoreBluetoothArtifactAuthorityFence(authority: authority)
        let recorder = try PassiveCoreBluetoothCaptureRecorder(
            vehicleIdentity: es80,
            startedAt: Date(timeIntervalSince1970: 1)
        )

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

        let horizonAdmission = try committedReady.beginHorizon(
            queueCutoff: horizon,
            processedThrough: horizon,
            gate: &gate
        )
        let recordedHorizon = try await horizonAdmission.recordBoundary(on: recorder)
        let committedHorizon = try recordedHorizon.markBoundaryRecorded(
            on: &gate,
            lastProcessedQueueSequence: horizon
        )
        try committedHorizon.completeHorizonArtifactFreeze(on: &gate)
        return gate
    }

    @MainActor
    private func retire(
        _ events: inout [Event],
        tail: UInt64,
        gate: PassiveCoreBluetoothObservationBoundaryQueueGate
    ) throws -> Retirement.Receipt {
        try Retirement.retire(
            from: &events,
            currentLastEnqueuedEventSequence: tail,
            terminalGate: gate
        ) {
            Retirement.PendingEvidenceIdentity(
                queueSequence: $0.queueSequence,
                authority: $0.authority
            )
        }
    }

    private func terminalTransaction(
        from gate: PassiveCoreBluetoothObservationBoundaryQueueGate
    ) -> PassiveCoreBluetoothObservationBoundaryQueueGate.Transaction? {
        guard case let .terminal(transaction) = gate.phase else { return nil }
        return transaction
    }
}
