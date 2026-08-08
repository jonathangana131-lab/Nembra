import Foundation

/// One sealed, synchronous MainActor admission for an observation boundary.
///
/// The existing queue gate owns callback-prefix ordering and the existing decision
/// token owns the trusted pre-await clocks. This type binds those two authorities
/// together with the exact artifact-authority mutation fence before the first
/// asynchronous hop so controller integration cannot accidentally carry a decision,
/// queue transaction, and authority source from different lifecycle epochs.
///
/// This remains software FIFO / observation chronology only. It does not establish
/// BLE/RF emission time, physical scooter state, GATT/Tuya semantics, or hardware
/// acknowledgement.
struct PassiveCoreBluetoothObservationBoundaryTransactionDecision: Equatable, Sendable {
    private let decision: PassiveCoreBluetoothObservationBoundaryDecision
    private let transaction: PassiveCoreBluetoothObservationBoundaryQueueGate.Transaction
    private let authorityFence: PassiveCoreBluetoothArtifactAuthorityMutationFence

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
    /// in one synchronous MainActor operation using the fence's exact current
    /// authority as the sole authority source.
    ///
    /// There is deliberately no `await` between authority capture, decision capture,
    /// and gate mutation. Authority replacement is MainActor-isolated, so it cannot
    /// interleave this synchronous admission. The recorder actor later revalidates
    /// the same sealed fence at the durable mutation point.
    @MainActor
    static func captureAndBegin(
        kind: PassiveCoreBluetoothObservationBoundaryQueueGate.BoundaryKind,
        queueCutoff: UInt64,
        processedThrough: UInt64,
        authorityFence: PassiveCoreBluetoothArtifactAuthorityMutationFence,
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

    /// Routes the exact pre-await boundary decision through the recorder actor and
    /// revalidates the same sealed artifact-authority fence at the durable mutation
    /// point. No clock, cutoff, transaction, or authority source is resampled here.
    func recordBoundary(on recorder: PassiveCoreBluetoothCaptureRecorder) async throws {
        try await decision.recordBoundary(
            on: recorder,
            authorityFence: authorityFence
        )
    }

    /// Commits only the queue transaction sealed into this same decision bundle,
    /// using the same fence as the current-authority source after the actor hop.
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

    /// Completes the gate's terminal transition only for the horizon transaction
    /// sealed into this same bundle and the same current authority source. The
    /// caller still must first freeze the actual immutable artifact through the
    /// exact horizon cutoff; this helper neither performs nor fabricates that read.
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
        authorityFence: PassiveCoreBluetoothArtifactAuthorityMutationFence
    ) {
        self.decision = decision
        self.transaction = transaction
        self.authorityFence = authorityFence
    }
}
