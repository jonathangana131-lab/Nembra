import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Terminal resolution applied-frontier authority")
struct PassiveCoreBluetoothTerminalResolutionAppliedFrontierTests {
    private typealias Gate = PassiveCoreBluetoothObservationBoundaryQueueGate
    private typealias Retirement = PassiveCoreBluetoothTerminalQueueRetirement
    private typealias Resolution = PassiveCoreBluetoothTerminalQueueResolution

    private struct Event: Equatable {
        let queueSequence: UInt64
        let authority: PassiveCoreBluetoothArtifactAuthorityContext
    }

    private let authority = PassiveCoreBluetoothArtifactAuthorityContext(
        targetSessionGeneration: 7,
        authorityGeneration: 11
    )

    private let targetPeripheralIdentifier = UUID(
        uuidString: "EA744F98-AB7E-40D5-9BCE-46564EE7CF19"
    )!

    private let es80 = VehicleIdentity(
        manufacturer: "AOVOPRO",
        model: "ES80",
        displayName: "AOVOPRO ES80",
        protocolFamily: "Tuya / AOVOPRO (hardware validation pending)"
    )

    @Test("resolution receipt and fresh recorder cannot reopen until controller applies resolved frontier")
    @MainActor
    func receiptAloneIsNotAppliedChronology() async throws {
        var gate = try await terminalGate(horizon: 12)
        let terminal = try #require(terminalTransaction(from: gate))

        var pending = [
            Event(queueSequence: 13, authority: authority),
            Event(queueSequence: 14, authority: authority),
        ]
        let retirement = try Retirement.retire(
            from: &pending,
            currentLastEnqueuedEventSequence: 14,
            terminalGate: gate
        ) {
            Retirement.PendingEvidenceIdentity(
                queueSequence: $0.queueSequence,
                authority: $0.authority
            )
        }
        #expect(pending.isEmpty)

        let resolution = try Resolution.resolve(
            currentResolvedThroughQueueSequence: 12,
            currentLastEnqueuedEventSequence: 14,
            retirementReceipt: retirement,
            terminalGate: gate
        )
        #expect(resolution.resolvedThroughQueueSequence == 14)

        let freshSession = try PassiveCoreBluetoothFreshTerminalCaptureSession.create(
            after: resolution,
            targetPeripheralIdentifier: targetPeripheralIdentifier,
            vehicleIdentity: es80,
            startedAt: Date(timeIntervalSince1970: 200)
        )

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

        try gate.reopenAfterTerminalQueueResolution(
            resolution,
            freshSession: freshSession,
            currentLastEnqueuedEventSequence: 14,
            currentResolvedThroughQueueSequence: 14
        )
        #expect(gate.phase == .awaitingReady)
    }

    @MainActor
    private func terminalGate(horizon: UInt64) async throws -> Gate {
        var gate = Gate()
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

    private func terminalTransaction(from gate: Gate) -> Gate.Transaction? {
        guard case let .terminal(transaction) = gate.phase else { return nil }
        return transaction
    }
}
