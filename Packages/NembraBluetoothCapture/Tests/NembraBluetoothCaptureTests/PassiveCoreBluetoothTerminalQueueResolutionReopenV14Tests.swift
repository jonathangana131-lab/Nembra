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

    private let targetPeripheralIdentifier = UUID(
        uuidString: "57E94B09-81C9-4B45-9C20-2D79355FB34D"
    )!

    private let es80 = VehicleIdentity(
        manufacturer: "AOVOPRO",
        model: "ES80",
        displayName: "AOVOPRO ES80",
        protocolFamily: "Tuya / AOVOPRO (hardware validation pending)"
    )

    @Test("terminal resolution reopens only for the exact producer-created fresh target session")
    @MainActor
    func exactFreshSessionIsRequired() async throws {
        var gate = try await terminalGate(horizon: 12)
        let terminal = try #require(terminalTransaction(from: gate))
        let resolution = try resolveTerminalQueue(gate: gate, tail: 14)
        let freshSession = try makeFreshSession(after: resolution)

        try gate.reopenAfterTerminalQueueResolution(
            resolution,
            freshSession: freshSession,
            currentLastEnqueuedEventSequence: 14,
            currentResolvedThroughQueueSequence: 14
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

        let exactFreshAuthority = freshSession.reopenAuthority.freshArtifactAuthority
        let ready = try gate.begin(
            .finiteAcquisitionReady,
            through: 14,
            authority: exactFreshAuthority
        )
        #expect(ready.revision > terminal.revision)
        #expect(ready.authority == exactFreshAuthority)
    }

    @Test("fresh-session producer constructs the recorder before exposing reopen authority")
    @MainActor
    func producerBacksAuthorityWithRealRecorder() async throws {
        let gate = try await terminalGate(horizon: 12)
        let resolution = try resolveTerminalQueue(gate: gate, tail: 12)
        let sessionID = UUID(uuidString: "43F13675-8C1A-4B6B-9C86-5BAAF916453D")!
        let freshSession = try PassiveCoreBluetoothFreshTerminalCaptureSession.create(
            after: resolution,
            targetPeripheralIdentifier: targetPeripheralIdentifier,
            vehicleIdentity: es80,
            sessionID: sessionID,
            startedAt: Date(timeIntervalSince1970: 300)
        )

        let snapshot = await freshSession.recorder.snapshot()
        #expect(snapshot.id == sessionID)
        #expect(freshSession.reopenAuthority.terminalAuthority == terminalAuthority)
        #expect(freshSession.reopenAuthority.freshArtifactAuthority.targetSessionGeneration == 8)
        #expect(freshSession.reopenAuthority.freshArtifactAuthority.authorityGeneration == 1)
        #expect(freshSession.reopenAuthority.targetPeripheralIdentifier == targetPeripheralIdentifier)
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
        let freshSessionA = try makeFreshSession(after: resolutionA)
        #expect(throws: Gate.StateError.staleTransaction) {
            try gateB.reopenAfterTerminalQueueResolution(
                resolutionA,
                freshSession: freshSessionA,
                currentLastEnqueuedEventSequence: 13,
                currentResolvedThroughQueueSequence: 13
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
        let freshSession = try makeFreshSession(after: resolution)

        #expect(
            throws: Gate.StateError.terminalQueueChangedAfterResolution(
                expected: 13,
                actual: 14
            )
        ) {
            try gate.reopenAfterTerminalQueueResolution(
                resolution,
                freshSession: freshSession,
                currentLastEnqueuedEventSequence: 14,
                currentResolvedThroughQueueSequence: 13
            )
        }
        #expect(gate.phase == .terminal(terminal))
    }

    @Test("resolution possession without controller frontier application cannot reopen")
    @MainActor
    func unappliedResolvedFrontierFailsClosed() async throws {
        var gate = try await terminalGate(horizon: 12)
        let terminal = try #require(terminalTransaction(from: gate))
        let resolution = try resolveTerminalQueue(gate: gate, tail: 14)
        let freshSession = try makeFreshSession(after: resolution)

        #expect(
            throws: Gate.StateError.terminalResolutionNotApplied(
                expected: 14,
                actual: 12
            )
        ) {
            try gate.reopenAfterTerminalQueueResolution(
                resolution,
                freshSession: freshSession,
                currentLastEnqueuedEventSequence: 14,
                currentResolvedThroughQueueSequence: 12
            )
        }
        #expect(gate.phase == .terminal(terminal))
    }

    @Test("fresh authority from a different real terminal cannot substitute")
    @MainActor
    func foreignFreshSessionAuthorityFailsClosed() async throws {
        var gateA = try await terminalGate(horizon: 12)
        let gateB = try await terminalGate(horizon: 12)
        let terminalA = try #require(terminalTransaction(from: gateA))
        let resolutionA = try resolveTerminalQueue(gate: gateA, tail: 12)
        let resolutionB = try resolveTerminalQueue(gate: gateB, tail: 12)
        let freshSessionB = try makeFreshSession(after: resolutionB)

        #expect(throws: Gate.StateError.staleTransaction) {
            try gateA.reopenAfterTerminalQueueResolution(
                resolutionA,
                freshSession: freshSessionB,
                currentLastEnqueuedEventSequence: 12,
                currentResolvedThroughQueueSequence: 12
            )
        }
        #expect(gateA.phase == .terminal(terminalA))
    }

    @Test("reset cannot erase fresh-session binding after terminal recovery")
    @MainActor
    func resetPreservesExactFreshSessionBinding() async throws {
        var gate = try await terminalGate(horizon: 12)
        let resolution = try resolveTerminalQueue(gate: gate, tail: 12)
        let freshSession = try makeFreshSession(after: resolution)
        try gate.reopenAfterTerminalQueueResolution(
            resolution,
            freshSession: freshSession,
            currentLastEnqueuedEventSequence: 12,
            currentResolvedThroughQueueSequence: 12
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

    private func makeFreshSession(
        after resolution: Resolution.Receipt
    ) throws -> PassiveCoreBluetoothFreshTerminalCaptureSession {
        try PassiveCoreBluetoothFreshTerminalCaptureSession.create(
            after: resolution,
            targetPeripheralIdentifier: targetPeripheralIdentifier,
            vehicleIdentity: es80,
            startedAt: Date(timeIntervalSince1970: 200)
        )
    }

    private func terminalTransaction(from gate: Gate) -> Gate.Transaction? {
        guard case let .terminal(transaction) = gate.phase else { return nil }
        return transaction
    }
}
