import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Terminal queue resolution fresh-session reopen V14")
struct PassiveCoreBluetoothTerminalQueueResolutionReopenV14Tests {
    private typealias Gate = PassiveCoreBluetoothObservationBoundaryQueueGate
    private typealias Retirement = PassiveCoreBluetoothTerminalQueueRetirement
    private typealias Resolution = PassiveCoreBluetoothTerminalQueueResolution

    private struct Event: Equatable {
        let queueSequence: UInt64
        let authority: PassiveCoreBluetoothArtifactAuthorityContext
    }

    private let terminalAuthority = PassiveCoreBluetoothArtifactAuthorityContext(
        targetSessionGeneration: 7,
        authorityGeneration: 11
    )

    private let es80 = VehicleIdentity(
        manufacturer: "AOVOPRO",
        model: "ES80",
        displayName: "AOVOPRO ES80",
        protocolFamily: "Tuya / AOVOPRO (hardware validation pending)"
    )

    @Test("terminal resolution reopens only for the exact bound fresh durable target session")
    @MainActor
    func exactFreshSessionIsRequired() async throws {
        var gate = try await terminalGate(horizon: 12)
        let terminal = try #require(terminalTransaction(from: gate))
        let resolution = try resolveTerminalQueue(gate: gate, tail: 14)

        try gate.reopenAfterTerminalQueueResolution(
            resolution,
            currentResolvedThroughQueueSequence: 14,
            currentLastEnqueuedEventSequence: 14,
            freshTargetSessionGeneration: 8
        )
        #expect(gate.phase == .awaitingReady)

        let oldAuthority = PassiveCoreBluetoothArtifactAuthorityContext(
            targetSessionGeneration: 7,
            authorityGeneration: 12
        )
        #expect(throws: Gate.StateError.freshTargetSessionRequired) {
            _ = try gate.begin(
                .finiteAcquisitionReady,
                through: 14,
                authority: oldAuthority
            )
        }

        let unrelatedLaterAuthority = PassiveCoreBluetoothArtifactAuthorityContext(
            targetSessionGeneration: 9,
            authorityGeneration: 1
        )
        #expect(throws: Gate.StateError.freshTargetSessionRequired) {
            _ = try gate.begin(
                .finiteAcquisitionReady,
                through: 14,
                authority: unrelatedLaterAuthority
            )
        }

        let exactFreshAuthority = PassiveCoreBluetoothArtifactAuthorityContext(
            targetSessionGeneration: 8,
            authorityGeneration: 1
        )
        let ready = try gate.begin(
            .finiteAcquisitionReady,
            through: 14,
            authority: exactFreshAuthority
        )
        #expect(ready.revision > terminal.revision)
        #expect(ready.authority == exactFreshAuthority)
    }

    @Test("equal-scalar foreign terminal resolution cannot reopen this gate")
    @MainActor
    func foreignTerminalIdentityFailsClosed() async throws {
        let gateA = try await terminalGate(horizon: 12)
        var gateB = try await terminalGate(horizon: 12)
        let terminalA = try #require(terminalTransaction(from: gateA))
        let terminalB = try #require(terminalTransaction(from: gateB))
        #expect(terminalA.revision == terminalB.revision)
        #expect(terminalA.queueCutoff == terminalB.queueCutoff)
        #expect(terminalA.authority == terminalB.authority)
        #expect(terminalA.identity != terminalB.identity)

        let resolutionA = try resolveTerminalQueue(gate: gateA, tail: 13)
        #expect(throws: Gate.StateError.staleTransaction) {
            try gateB.reopenAfterTerminalQueueResolution(
                resolutionA,
                currentResolvedThroughQueueSequence: 13,
                currentLastEnqueuedEventSequence: 13,
                freshTargetSessionGeneration: 8
            )
        }
        #expect(gateB.phase == .terminal(terminalB))
    }

    @Test("callback tail drift after resolution keeps terminal gate closed")
    @MainActor
    func queueTailDriftFailsClosed() async throws {
        var gate = try await terminalGate(horizon: 12)
        let terminal = try #require(terminalTransaction(from: gate))
        let resolution = try resolveTerminalQueue(gate: gate, tail: 13)

        #expect(
            throws: Gate.StateError.terminalQueueChangedAfterResolution(
                expected: 13,
                actual: 14
            )
        ) {
            try gate.reopenAfterTerminalQueueResolution(
                resolution,
                currentResolvedThroughQueueSequence: 13,
                currentLastEnqueuedEventSequence: 14,
                freshTargetSessionGeneration: 8
            )
        }
        #expect(gate.phase == .terminal(terminal))
    }

    @Test("reset cannot erase fresh-session binding after terminal recovery")
    @MainActor
    func resetPreservesExactFreshSessionBinding() async throws {
        var gate = try await terminalGate(horizon: 12)
        let resolution = try resolveTerminalQueue(gate: gate, tail: 12)
        try gate.reopenAfterTerminalQueueResolution(
            resolution,
            currentResolvedThroughQueueSequence: 12,
            currentLastEnqueuedEventSequence: 12,
            freshTargetSessionGeneration: 8
        )

        #expect(gate.resetForNewCaptureSession())
        let wrongAuthority = PassiveCoreBluetoothArtifactAuthorityContext(
            targetSessionGeneration: 9,
            authorityGeneration: 1
        )
        #expect(throws: Gate.StateError.freshTargetSessionRequired) {
            _ = try gate.begin(
                .finiteAcquisitionReady,
                through: 12,
                authority: wrongAuthority
            )
        }
    }

    @MainActor
    private func terminalGate(horizon: UInt64) async throws -> Gate {
        var gate = Gate()
        let fence = PassiveCoreBluetoothArtifactAuthorityFence(authority: terminalAuthority)
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
    private func resolveTerminalQueue(
        gate: Gate,
        tail: UInt64
    ) throws -> Resolution.Receipt {
        let horizon = try #require(gate.terminalQueueCutoff)
        var events: [Event] = []
        if tail > horizon {
            for sequence in (horizon + 1)...tail {
                events.append(Event(queueSequence: sequence, authority: terminalAuthority))
            }
        }

        let retirement = try Retirement.retire(
            from: &events,
            currentLastEnqueuedEventSequence: tail,
            terminalGate: gate
        ) {
            Retirement.PendingEvidenceIdentity(
                queueSequence: $0.queueSequence,
                authority: $0.authority
            )
        }
        #expect(events.isEmpty)
        return try Resolution.resolve(
            currentResolvedThroughQueueSequence: horizon,
            currentLastEnqueuedEventSequence: tail,
            retirementReceipt: retirement,
            terminalGate: gate
        )
    }

    private func terminalTransaction(from gate: Gate) -> Gate.Transaction? {
        guard case let .terminal(transaction) = gate.phase else { return nil }
        return transaction
    }
}
