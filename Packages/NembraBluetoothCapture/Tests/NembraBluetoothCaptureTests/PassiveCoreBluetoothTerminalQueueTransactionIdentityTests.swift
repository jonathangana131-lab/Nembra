import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Terminal FIFO transaction identity")
struct PassiveCoreBluetoothTerminalQueueTransactionIdentityTests {
    private typealias Retirement = PassiveCoreBluetoothTerminalQueueRetirement
    private typealias Resolution = PassiveCoreBluetoothTerminalQueueResolution

    private struct Event {
        let queueSequence: UInt64
        let authority: PassiveCoreBluetoothArtifactAuthorityContext
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

    @Test("retirement and resolution retain exact terminal UUID")
    @MainActor
    func receiptIdentityPropagates() async throws {
        let gate = try await terminalGate(horizon: 12)
        let terminal = try #require(terminalTransaction(from: gate))
        var events = [Event(queueSequence: 13, authority: authority)]

        let retirement = try retire(&events, tail: 13, gate: gate)
        #expect(events.isEmpty)
        #expect(retirement.terminalTransactionIdentity == terminal.identity)

        let resolution = try Resolution.resolve(
            currentResolvedThroughQueueSequence: 12,
            currentLastEnqueuedEventSequence: 13,
            retirementReceipt: retirement,
            terminalGate: gate
        )
        #expect(resolution.terminalTransactionIdentity == terminal.identity)
    }

    @Test("equal-scalar foreign terminal is rejected by process-local UUID")
    @MainActor
    func equalScalarForeignTerminalFailsClosed() async throws {
        let producerGate = try await terminalGate(horizon: 12)
        let foreignGate = try await terminalGate(horizon: 12)
        let producer = try #require(terminalTransaction(from: producerGate))
        let foreign = try #require(terminalTransaction(from: foreignGate))

        #expect(producer.authority == foreign.authority)
        #expect(producer.revision == foreign.revision)
        #expect(producer.queueCutoff == foreign.queueCutoff)
        #expect(producer.identity != foreign.identity)

        var events = [Event(queueSequence: 13, authority: authority)]
        let retirement = try retire(&events, tail: 13, gate: producerGate)
        #expect(events.isEmpty)

        #expect(throws: Resolution.StateError.staleTerminalTransaction) {
            _ = try Resolution.resolve(
                currentResolvedThroughQueueSequence: 12,
                currentLastEnqueuedEventSequence: 13,
                retirementReceipt: retirement,
                terminalGate: foreignGate
            )
        }
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
