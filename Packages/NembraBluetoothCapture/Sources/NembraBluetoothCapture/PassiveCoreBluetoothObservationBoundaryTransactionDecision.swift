import Foundation

/// One sealed synchronous admission for a lifecycle observation boundary.
///
/// This composes the already-accepted queue-gate transaction with the canonical
/// artifact-authority fence from the dedicated authority-fence lane. The exact
/// decision, queue transaction, and fence are kept private so controller wiring
/// cannot carry valid pieces from different lifecycle admissions across the
/// recorder actor hop.
///
/// The API is deliberately typestated:
/// `Admission -> RecordedBoundary -> CommittedBoundary`.
/// A caller cannot advance the queue gate to "boundary recorded" using an
/// admission that never successfully returned from the recorder mutation.
///
/// This remains software FIFO / observation chronology only. It establishes no
/// BLE/RF emission time, physical scooter state, GATT/Tuya semantics, or hardware
/// acknowledgement.
struct PassiveCoreBluetoothObservationBoundaryTransactionDecision: Equatable, Sendable {
    struct RecordedBoundary: Equatable, Sendable {
        private let decision: PassiveCoreBluetoothObservationBoundaryDecision
        private let transaction: PassiveCoreBluetoothObservationBoundaryQueueGate.Transaction
        private let authorityFence: PassiveCoreBluetoothArtifactAuthorityFence

        var queueKind: PassiveCoreBluetoothObservationBoundaryQueueGate.BoundaryKind {
            decision.queueKind
        }

        var queueCutoff: UInt64 {
            decision.queueCutoff
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

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.decision == rhs.decision
                && lhs.transaction == rhs.transaction
                && lhs.authorityFence === rhs.authorityFence
        }

        /// Commits only the exact queue transaction whose recorder mutation has
        /// already returned successfully. Current authority is sampled from the
        /// same sealed canonical fence after the actor hop.
        @MainActor
        func markBoundaryRecorded(
            on gate: inout PassiveCoreBluetoothObservationBoundaryQueueGate,
            lastProcessedQueueSequence: UInt64
        ) throws -> CommittedBoundary {
            try gate.markBoundaryRecorded(
                transaction,
                lastProcessedQueueSequence: lastProcessedQueueSequence,
                currentAuthority: authorityFence.currentAuthority
            )

            return CommittedBoundary(
                decision: decision,
                transaction: transaction,
                authorityFence: authorityFence
            )
        }

        fileprivate init(
            decision: PassiveCoreBluetoothObservationBoundaryDecision,
            transaction: PassiveCoreBluetoothObservationBoundaryQueueGate.Transaction,
            authorityFence: PassiveCoreBluetoothArtifactAuthorityFence
        ) {
            self.decision = decision
            self.transaction = transaction
            self.authorityFence = authorityFence
        }
    }

    struct CommittedBoundary: Equatable, Sendable {
        private let decision: PassiveCoreBluetoothObservationBoundaryDecision
        private let transaction: PassiveCoreBluetoothObservationBoundaryQueueGate.Transaction
        private let authorityFence: PassiveCoreBluetoothArtifactAuthorityFence

        var queueKind: PassiveCoreBluetoothObservationBoundaryQueueGate.BoundaryKind {
            decision.queueKind
        }

        var queueCutoff: UInt64 {
            decision.queueCutoff
        }

        var authority: PassiveCoreBluetoothArtifactAuthorityContext {
            decision.authority
        }

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.decision == rhs.decision
                && lhs.transaction == rhs.transaction
                && lhs.authorityFence === rhs.authorityFence
        }

        /// Completes only this committed Horizon transaction after the caller has
        /// actually frozen the immutable artifact through the exact Horizon cutoff.
        /// This helper does not perform, imply, or fabricate that artifact read.
        /// Calling it for a committed Ready boundary still fails closed in the gate.
        @MainActor
        func completeHorizonArtifactFreeze(
            on gate: inout PassiveCoreBluetoothObservationBoundaryQueueGate
        ) throws {
            try gate.completeHorizonArtifactFreeze(
                transaction,
                currentAuthority: authorityFence.currentAuthority
            )
        }

        fileprivate init(
            decision: PassiveCoreBluetoothObservationBoundaryDecision,
            transaction: PassiveCoreBluetoothObservationBoundaryQueueGate.Transaction,
            authorityFence: PassiveCoreBluetoothArtifactAuthorityFence
        ) {
            self.decision = decision
            self.transaction = transaction
            self.authorityFence = authorityFence
        }
    }

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

    static func == (lhs: Self, rhs: Self) -> Bool {
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

    /// Performs the authority-fenced recorder mutation and returns the only token
    /// that is allowed to commit the queue boundary. If revocation wins before the
    /// recorder mutation, this throws and no `RecordedBoundary` can be constructed.
    func recordBoundary(
        on recorder: PassiveCoreBluetoothCaptureRecorder
    ) async throws -> RecordedBoundary {
        try await decision.recordBoundary(
            on: recorder,
            authorityFence: authorityFence
        )

        return RecordedBoundary(
            decision: decision,
            transaction: transaction,
            authorityFence: authorityFence
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
