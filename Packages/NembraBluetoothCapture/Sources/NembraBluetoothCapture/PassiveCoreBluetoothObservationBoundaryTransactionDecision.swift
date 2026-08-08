import Foundation

/// One sealed, synchronous MainActor admission for an observation boundary.
///
/// The existing queue gate owns callback-prefix ordering and the existing decision
/// token owns the trusted pre-await clocks. This type binds those two authorities
/// into one non-forgeable value before the first asynchronous hop so controller
/// integration cannot accidentally carry a decision for one cutoff/authority and
/// later commit a different queue transaction.
///
/// This remains software FIFO / observation chronology only. It does not establish
/// BLE/RF emission time, physical scooter state, GATT/Tuya semantics, or hardware
/// acknowledgement.
struct PassiveCoreBluetoothObservationBoundaryTransactionDecision: Equatable, Sendable {
    let decision: PassiveCoreBluetoothObservationBoundaryDecision
    let transaction: PassiveCoreBluetoothObservationBoundaryQueueGate.Transaction

    var queueKind: PassiveCoreBluetoothObservationBoundaryQueueGate.BoundaryKind {
        decision.queueKind
    }

    var queueCutoff: UInt64 {
        decision.queueCutoff
    }

    var processedThrough: UInt64 {
        decision.processedThrough
    }

    var authority: PassiveCoreBluetoothArtifactAuthorityContext {
        decision.authority
    }

    /// Captures trusted local chronology and opens the matching queue transaction
    /// in one synchronous MainActor operation.
    ///
    /// There is deliberately no `await` between decision capture and gate mutation.
    /// The decision is captured first so a malformed `processedThrough > cutoff`
    /// fails before the gate can mutate. `QueueGate.begin` itself validates all of
    /// its cross-boundary invariants before allocating a revision or changing phase,
    /// so every thrown path leaves the gate semantically unchanged.
    @MainActor
    static func captureAndBegin(
        kind: PassiveCoreBluetoothObservationBoundaryQueueGate.BoundaryKind,
        queueCutoff: UInt64,
        processedThrough: UInt64,
        authority: PassiveCoreBluetoothArtifactAuthorityContext,
        gate: inout PassiveCoreBluetoothObservationBoundaryQueueGate
    ) throws -> Self {
        let decision = try PassiveCoreBluetoothObservationBoundaryDecision.capture(
            kind: kind,
            queueCutoff: queueCutoff,
            processedThrough: processedThrough,
            authority: authority
        )

        let transaction = try gate.begin(
            decision.queueKind,
            through: decision.queueCutoff,
            processedThrough: decision.processedThrough,
            authority: decision.authority
        )

        return Self(decision: decision, transaction: transaction)
    }

    /// Routes the exact pre-await boundary decision through the recorder actor.
    /// No clock or cutoff is resampled here.
    func recordBoundary(on recorder: PassiveCoreBluetoothCaptureRecorder) async throws {
        try await decision.recordBoundary(on: recorder)
    }

    /// Commits only the queue transaction sealed into this same decision bundle.
    /// A controller does not receive a transaction parameter here, removing one
    /// opportunity to pair an awaited recorder result with the wrong transaction.
    @MainActor
    func markBoundaryRecorded(
        on gate: inout PassiveCoreBluetoothObservationBoundaryQueueGate,
        lastProcessedQueueSequence: UInt64,
        currentAuthority: PassiveCoreBluetoothArtifactAuthorityContext
    ) throws {
        try gate.markBoundaryRecorded(
            transaction,
            lastProcessedQueueSequence: lastProcessedQueueSequence,
            currentAuthority: currentAuthority
        )
    }

    /// Completes the gate's terminal transition only for the horizon transaction
    /// sealed into this same bundle. The caller still must first freeze the actual
    /// immutable artifact through the exact horizon cutoff; this helper neither
    /// performs nor fabricates that artifact read.
    @MainActor
    func completeHorizonArtifactFreeze(
        on gate: inout PassiveCoreBluetoothObservationBoundaryQueueGate,
        currentAuthority: PassiveCoreBluetoothArtifactAuthorityContext
    ) throws {
        try gate.completeHorizonArtifactFreeze(
            transaction,
            currentAuthority: currentAuthority
        )
    }

    private init(
        decision: PassiveCoreBluetoothObservationBoundaryDecision,
        transaction: PassiveCoreBluetoothObservationBoundaryQueueGate.Transaction
    ) {
        self.decision = decision
        self.transaction = transaction
    }
}
