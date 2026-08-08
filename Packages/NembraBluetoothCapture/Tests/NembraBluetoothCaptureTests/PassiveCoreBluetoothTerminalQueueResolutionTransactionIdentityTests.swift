import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Terminal resolution exact transaction identity")
struct PassiveCoreBluetoothTerminalQueueResolutionTransactionIdentityTests {
    private typealias Gate = PassiveCoreBluetoothObservationBoundaryQueueGate

    private struct Event: Equatable {
        let queueSequence: UInt64
        let authority: PassiveCoreBluetoothArtifactAuthorityContext
    }

    private let authority = PassiveCoreBluetoothArtifactAuthorityContext(
        targetSessionGeneration: 7,
        authorityGeneration: 11
    )

    @Test("scalar-identical foreign terminal resolution cannot reopen another gate")
    @MainActor
    func foreignTerminalResolutionFailsClosed() throws {
        let terminalA = try terminalGate(horizonQueueCutoff: 12)
        let terminalB = try terminalGate(horizonQueueCutoff: 12)

        #expect(terminalA.horizon.revision == terminalB.horizon.revision)
        #expect(terminalA.horizon.queueCutoff == terminalB.horizon.queueCutoff)
        #expect(terminalA.horizon.authority == terminalB.horizon.authority)
        #expect(terminalA.horizon.identity != terminalB.horizon.identity)

        var eventsA: [Event] = []
        let retirementA = try PassiveCoreBluetoothTerminalQueueRetirement.retire(
            from: &eventsA,
            currentLastEnqueuedEventSequence: 12,
            terminalGate: terminalA.gate,
            identity: { .init(queueSequence: $0.queueSequence, authority: $0.authority) }
        )
        let resolutionA = try PassiveCoreBluetoothTerminalQueueResolution.resolve(
            currentResolvedThroughQueueSequence: 12,
            currentLastEnqueuedEventSequence: 12,
            retirementReceipt: retirementA,
            terminalGate: terminalA.gate
        )

        var gateB = terminalB.gate
        #expect(throws: Gate.StateError.staleTransaction) {
            try gateB.reopenAfterTerminalQueueResolution(
                resolutionA,
                currentLastEnqueuedEventSequence: 12,
                freshTargetSessionGeneration: 8
            )
        }
        #expect(gateB.phase == .terminal(terminalB.horizon))
    }

    @MainActor
    private func terminalGate(
        horizonQueueCutoff: UInt64
    ) throws -> (gate: Gate, horizon: Gate.Transaction) {
        var gate = Gate()
        let ready = try gate.begin(
            .finiteAcquisitionReady,
            through: 5,
            authority: authority
        )
        try gate.markBoundaryRecorded(
            ready,
            lastProcessedQueueSequence: 5,
            currentAuthority: authority
        )
        let horizon = try gate.beginObservationHorizon(
            through: horizonQueueCutoff,
            processedThrough: 8,
            authority: authority,
            establishedByReadyRevision: ready.revision,
            establishedByReadyIdentity: ready.identity
        )
        try gate.markBoundaryRecorded(
            horizon,
            lastProcessedQueueSequence: horizonQueueCutoff,
            currentAuthority: authority
        )
        try gate.completeHorizonArtifactFreeze(
            horizon,
            currentAuthority: authority
        )
        return (gate, horizon)
    }
}
