import Foundation

/// One sealed synchronous admission for a lifecycle observation boundary.
///
/// This composes the already-accepted queue-gate transaction with the canonical
/// artifact-authority fence from the dedicated authority-fence lane. The exact
/// decision, queue transaction, and fence are kept private so controller wiring
/// cannot carry valid pieces from different lifecycle admissions across the
/// recorder actor hop.
///
/// This remains software FIFO / observation chronology only. It establishes no
/// BLE/RF emission time, physical scooter state, GATT/Tuya semantics, or hardware
/// acknowledgement.
struct PassiveCoreBluetoothObservationBoundaryTransactionDecision: Equatable, Sendable {
    private let decision: PassiveCoreBluetoothObservationBoundaryDecision
    private let transaction: PassiveCoreBluetoothObservationBoundaryQueueGate.Transaction
    private let authorityFence: PassiveCoreBluetoothArtifactAuthorityFence

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

    var observedAtUptimeNanoseconds: UInt64 {
        decision.observedAtUptimeNanoseconds
    }

    var observedAtDate: Date {
        decision.observedAtDate
    }

    static func == (
        lhs: PassiveCoreBluetoothObservationBoundaryTransactionDecision,
        rhs: PassiveCoreBluetoothObservationBoundaryTransactionDecision
    ) -> Bool {
        lhs.decision == rhs.decision
            && lhs.transaction == rhs.transaction
            && lhs.authorityFence === rhs.authorityFence
    }

    /// Captures trusted local chronology and opens the matching queue transaction
    /// in one synchronous MainActor operation using the canonical fence as the sole
    /// artifact-authority source.
    ///
    /// There is deliberately no suspension between authority sampling, decision
    /// capture, and gate mutation. Because authority transition is also MainActor
    /// isolated, it cannot interleave this synchronous admission. The recorder actor
    /// later revalidates this exact sealed fence at the irreversible append point.
    @MainActor
    static func captureAndBegin(
        kind: PassiveCoreBluetoothObservationBoundaryQueueGate.BoundaryKind,
        queueCutoff: UInt64,
        processedThrough: UInt64,
        authorityFence: PassiveCoreBluetoothArtifactAuthorityFence,
        gate: inout PassiveCoreBluetoothObservationBoundaryQueueGate
    ) throws -> Self {
        let authority = authorityFence.currentAuthority
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

        return Self(
            decision: decision,
            transaction: transaction,
            authorityFence: authorityFence
        )
    }

    /// Routes this exact pre-await decision through the recorder actor. The
    /// canonical fence performs the final authority check in the same synchronous
    /// critical section as the durable boundary append, so stale authority loses
    /// before evidence mutation rather than after it.
    func recordBoundary(on recorder: PassiveCoreBluetoothCaptureRecorder) async throws {
        try await decision.recordBoundary(
            on: recorder,
            authorityFence: authorityFence
        )
    }

    /// Commits only this admission's private queue transaction after the recorder
    /// hop, using the same sealed fence as the current-authority source.
    @MainActor
    func markBoundaryRecorded(
        on gate: inout PassiveCoreBluetoothObservationBoundaryQueueGate,
        lastProcessedQueueSequence: UInt64
    ) throws {
        try gate.markBoundaryRecorded(
            transaction,
            lastProcessedQueueSequence: lastProcessedQueueSequence,
            currentAuthority: authorityFence.currentAuthority
        )
    }

    /// Completes only this admission's private Horizon transaction after the caller
    /// has actually frozen the immutable artifact through the exact Horizon cutoff.
    /// This helper does not perform, imply, or fabricate that artifact read.
    @MainActor
    func completeHorizonArtifactFreeze(
        on gate: inout PassiveCoreBluetoothObservationBoundaryQueueGate
    ) throws {
        try gate.completeHorizonArtifactFreeze(
            transaction,
            currentAuthority: authorityFence.currentAuthority
        )
    }

    private init(
        decision: PassiveCoreBluetoothObservationBoundaryDecision,
        transaction: PassiveCoreBluetoothObservationBoundaryQueueGate.Transaction,
        authorityFence: PassiveCoreBluetoothArtifactAuthorityFence
    ) {
        self.decision = decision
        self.transaction = transaction
        self.authorityFence = authorityFence
    }
}
