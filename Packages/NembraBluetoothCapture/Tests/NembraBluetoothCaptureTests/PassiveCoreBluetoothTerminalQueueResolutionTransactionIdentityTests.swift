import Foundation
import Testing
@testable import NembraBluetoothCapture

/// Expected-red adversarial contract for terminal FIFO authority.
///
/// Revision/cutoff/authority equality is not exact producer identity: two independent
/// queue gates can allocate equal-scalar terminal transactions with distinct process-local
/// UUIDs. Retirement -> resolution must carry that UUID so one gate's receipt cannot be
/// substituted into another otherwise-equal terminal epoch.
struct PassiveCoreBluetoothTerminalQueueResolutionTransactionIdentityTests {
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

    @Test("equal-scalar foreign terminal retirement cannot resolve another gate")
    @MainActor
    func foreignTerminalRetirementReceiptFailsExactIdentity() throws {
        let terminalA = try terminalGate()
        let terminalB = try terminalGate()

        guard case let .terminal(transactionA) = terminalA.phase,
              case let .terminal(transactionB) = terminalB.phase else {
            Issue.record("expected both independent gates to be terminal")
            return
        }

        #expect(transactionA.authority == transactionB.authority)
        #expect(transactionA.queueCutoff == transactionB.queueCutoff)
        #expect(transactionA.revision == transactionB.revision)
        #expect(transactionA.identity != transactionB.identity)

        var eventsA: [Event] = []
        let retirementA = try Retirement.retire(
            from: &eventsA,
            currentLastEnqueuedEventSequence: transactionA.queueCutoff,
            terminalGate: terminalA,
            identity: { .init(queueSequence: $0.queueSequence, authority: $0.authority) }
        )

        #expect(throws: Resolution.StateError.staleTerminalTransaction) {
            _ = try Resolution.resolve(
                currentResolvedThroughQueueSequence: transactionB.queueCutoff,
                currentLastEnqueuedEventSequence: transactionB.queueCutoff,
                retirementReceipt: retirementA,
                terminalGate: terminalB
            )
        }
    }

    @MainActor
    private func terminalGate() throws -> Gate {
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
            through: 12,
            processedThrough: 8,
            authority: authority,
            establishedByReadyRevision: ready.revision,
            establishedByReadyIdentity: ready.identity
        )
        try gate.markBoundaryRecorded(
            horizon,
            lastProcessedQueueSequence: 12,
            currentAuthority: authority
        )
        try gate.completeHorizonArtifactFreeze(
            horizon,
            currentAuthority: authority
        )
        return gate
    }
}
