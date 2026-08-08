import Foundation

enum PassiveCoreBluetoothObservationBoundaryMutationAttemptError: Error, Equatable, Sendable {
    case alreadyAttempted
}

/// Shared across every value copy of one exact Ready/Horizon admission.
///
/// Claim is synchronous and occurs before the recorder actor hop. The permit is
/// never released, even when the first attempt later throws: except for the
/// canonical authority-revoked-before-mutation proof, an arbitrary recorder error
/// does not prove that durable mutation did not occur. Retrying the same admission
/// would therefore risk duplicate/ambiguous lifecycle evidence.
private final class PassiveCoreBluetoothObservationBoundaryMutationPermit: @unchecked Sendable {
    private let lock = NSLock()
    private var attempted = false

    func claim() throws {
        lock.lock()
        defer { lock.unlock() }

        guard !attempted else {
            throw PassiveCoreBluetoothObservationBoundaryMutationAttemptError.alreadyAttempted
        }
        attempted = true
    }
}

/// Sealed Ready admission for one observation epoch.
///
/// Only this Ready entry point accepts the controller's canonical #427 authority
/// fence. A successful Ready recorder append + exact queue commit mints the sole
/// `CommittedReadyEpoch`, and Horizon can begin only from that proof. Horizon never
/// accepts another fence parameter, so an equal-valued second authority store cannot
/// substitute itself after Ready.
///
/// The lifecycle is deliberately typestated:
/// `ReadyAdmission -> RecordedReadyBoundary -> CommittedReadyEpoch
///                 -> HorizonAdmission -> RecordedHorizonBoundary
///                 -> CommittedHorizonBoundary`.
///
/// Ready and Horizon admissions each also own one shared mutation permit. Copying
/// an admission copies the permit reference, not recorder-mutation authority, so
/// sequential or concurrent replay of the same admission can enter the recorder at
/// most once.
///
/// This remains software FIFO / observation chronology only. It establishes no
/// BLE/RF emission time, physical scooter state, GATT/Tuya semantics, or hardware
/// acknowledgement.
struct PassiveCoreBluetoothObservationBoundaryTransactionDecision: Equatable, Sendable {
    struct RecordedReadyBoundary: Equatable, Sendable {
        private let decision: PassiveCoreBluetoothObservationBoundaryDecision
        private let transaction: PassiveCoreBluetoothObservationBoundaryQueueGate.Transaction
        private let authorityFence: PassiveCoreBluetoothArtifactAuthorityFence

        var queueCutoff: UInt64 { decision.queueCutoff }
        var authority: PassiveCoreBluetoothArtifactAuthorityContext { decision.authority }
        var observedAtUptimeNanoseconds: UInt64 { decision.observedAtUptimeNanoseconds }
        var observedAtDate: Date { decision.observedAtDate }

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.decision == rhs.decision
                && lhs.transaction == rhs.transaction
                && lhs.authorityFence === rhs.authorityFence
        }

        /// Commits the exact Ready transaction only after its authority-fenced
        /// recorder mutation returned successfully. Successful commit is the only
        /// producer of a Horizon-capable `CommittedReadyEpoch`.
        @MainActor
        func markBoundaryRecorded(
            on gate: inout PassiveCoreBluetoothObservationBoundaryQueueGate,
            lastProcessedQueueSequence: UInt64
        ) throws -> CommittedReadyEpoch {
            try gate.markBoundaryRecorded(
                transaction,
                lastProcessedQueueSequence: lastProcessedQueueSequence,
                currentAuthority: authorityFence.currentAuthority
            )

            return CommittedReadyEpoch(
                readyDecision: decision,
                readyTransaction: transaction,
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

    struct CommittedReadyEpoch: Equatable, Sendable {
        private let readyDecision: PassiveCoreBluetoothObservationBoundaryDecision
        private let readyTransaction: PassiveCoreBluetoothObservationBoundaryQueueGate.Transaction
        private let authorityFence: PassiveCoreBluetoothArtifactAuthorityFence

        var queueCutoff: UInt64 { readyDecision.queueCutoff }
        var authority: PassiveCoreBluetoothArtifactAuthorityContext { readyDecision.authority }
        var observedAtUptimeNanoseconds: UInt64 { readyDecision.observedAtUptimeNanoseconds }
        var observedAtDate: Date { readyDecision.observedAtDate }

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.readyDecision == rhs.readyDecision
                && lhs.readyTransaction == rhs.readyTransaction
                && lhs.authorityFence === rhs.authorityFence
        }

        /// Begins Horizon only from the exact Ready epoch that established the
        /// observation session. No authority-fence parameter is accepted here.
        ///
        /// The retained fence must still equal this token's original Ready
        /// authority before any Horizon clock is captured or queue state mutates.
        /// A retired Ready token therefore cannot follow the shared mutable fence
        /// into a later lifecycle. #427's strictly-forward / anti-ABA transition
        /// contract makes a retired Ready authority permanently stale.
        @MainActor
        func beginHorizon(
            queueCutoff: UInt64,
            processedThrough: UInt64,
            gate: inout PassiveCoreBluetoothObservationBoundaryQueueGate
        ) throws -> HorizonAdmission {
            let currentAuthority = authorityFence.currentAuthority
            guard currentAuthority == readyDecision.authority else {
                throw PassiveCoreBluetoothArtifactAuthorityFence.StateError.authorityChanged(
                    expected: readyDecision.authority,
                    current: currentAuthority
                )
            }

            let decision = try PassiveCoreBluetoothObservationBoundaryDecision.capture(
                kind: .observationHorizon,
                queueCutoff: queueCutoff,
                processedThrough: processedThrough,
                authority: readyDecision.authority
            )

            let transaction = try gate.begin(
                decision.queueKind,
                through: decision.queueCutoff,
                processedThrough: decision.processedThrough,
                authority: decision.authority
            )

            return HorizonAdmission(
                decision: decision,
                transaction: transaction,
                authorityFence: authorityFence,
                mutationPermit: PassiveCoreBluetoothObservationBoundaryMutationPermit()
            )
        }

        fileprivate init(
            readyDecision: PassiveCoreBluetoothObservationBoundaryDecision,
            readyTransaction: PassiveCoreBluetoothObservationBoundaryQueueGate.Transaction,
            authorityFence: PassiveCoreBluetoothArtifactAuthorityFence
        ) {
            self.readyDecision = readyDecision
            self.readyTransaction = readyTransaction
            self.authorityFence = authorityFence
        }
    }

    struct HorizonAdmission: Equatable, Sendable {
        private let decision: PassiveCoreBluetoothObservationBoundaryDecision
        private let transaction: PassiveCoreBluetoothObservationBoundaryQueueGate.Transaction
        private let authorityFence: PassiveCoreBluetoothArtifactAuthorityFence
        private let mutationPermit: PassiveCoreBluetoothObservationBoundaryMutationPermit

        var queueCutoff: UInt64 { decision.queueCutoff }
        var processedThrough: UInt64 { decision.processedThrough }
        var authority: PassiveCoreBluetoothArtifactAuthorityContext { decision.authority }
        var observedAtUptimeNanoseconds: UInt64 { decision.observedAtUptimeNanoseconds }
        var observedAtDate: Date { decision.observedAtDate }

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.decision == rhs.decision
                && lhs.transaction == rhs.transaction
                && lhs.authorityFence === rhs.authorityFence
                && lhs.mutationPermit === rhs.mutationPermit
        }

        /// Performs the mutation-point authority-fenced Horizon append exactly once
        /// for this admission and returns the only token allowed to commit the
        /// Horizon queue transaction.
        func recordBoundary(
            on recorder: PassiveCoreBluetoothCaptureRecorder
        ) async throws -> RecordedHorizonBoundary {
            try mutationPermit.claim()
            try await decision.recordBoundary(
                on: recorder,
                authorityFence: authorityFence
            )

            return RecordedHorizonBoundary(
                decision: decision,
                transaction: transaction,
                authorityFence: authorityFence
            )
        }

        fileprivate init(
            decision: PassiveCoreBluetoothObservationBoundaryDecision,
            transaction: PassiveCoreBluetoothObservationBoundaryQueueGate.Transaction,
            authorityFence: PassiveCoreBluetoothArtifactAuthorityFence,
            mutationPermit: PassiveCoreBluetoothObservationBoundaryMutationPermit
        ) {
            self.decision = decision
            self.transaction = transaction
            self.authorityFence = authorityFence
            self.mutationPermit = mutationPermit
        }
    }

    struct RecordedHorizonBoundary: Equatable, Sendable {
        private let decision: PassiveCoreBluetoothObservationBoundaryDecision
        private let transaction: PassiveCoreBluetoothObservationBoundaryQueueGate.Transaction
        private let authorityFence: PassiveCoreBluetoothArtifactAuthorityFence

        var queueCutoff: UInt64 { decision.queueCutoff }
        var authority: PassiveCoreBluetoothArtifactAuthorityContext { decision.authority }
        var observedAtUptimeNanoseconds: UInt64 { decision.observedAtUptimeNanoseconds }
        var observedAtDate: Date { decision.observedAtDate }

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.decision == rhs.decision
                && lhs.transaction == rhs.transaction
                && lhs.authorityFence === rhs.authorityFence
        }

        @MainActor
        func markBoundaryRecorded(
            on gate: inout PassiveCoreBluetoothObservationBoundaryQueueGate,
            lastProcessedQueueSequence: UInt64
        ) throws -> CommittedHorizonBoundary {
            try gate.markBoundaryRecorded(
                transaction,
                lastProcessedQueueSequence: lastProcessedQueueSequence,
                currentAuthority: authorityFence.currentAuthority
            )

            return CommittedHorizonBoundary(
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

    struct CommittedHorizonBoundary: Equatable, Sendable {
        private let decision: PassiveCoreBluetoothObservationBoundaryDecision
        private let transaction: PassiveCoreBluetoothObservationBoundaryQueueGate.Transaction
        private let authorityFence: PassiveCoreBluetoothArtifactAuthorityFence

        var queueCutoff: UInt64 { decision.queueCutoff }
        var authority: PassiveCoreBluetoothArtifactAuthorityContext { decision.authority }

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.decision == rhs.decision
                && lhs.transaction == rhs.transaction
                && lhs.authorityFence === rhs.authorityFence
        }

        /// Completes only this committed Horizon transaction after the caller has
        /// actually frozen the immutable artifact through the exact Horizon cutoff.
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
    private let mutationPermit: PassiveCoreBluetoothObservationBoundaryMutationPermit

    var queueCutoff: UInt64 { decision.queueCutoff }
    var processedThrough: UInt64 { decision.processedThrough }
    var authority: PassiveCoreBluetoothArtifactAuthorityContext { decision.authority }
    var observedAtUptimeNanoseconds: UInt64 { decision.observedAtUptimeNanoseconds }
    var observedAtDate: Date { decision.observedAtDate }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.decision == rhs.decision
            && lhs.transaction == rhs.transaction
            && lhs.authorityFence === rhs.authorityFence
            && lhs.mutationPermit === rhs.mutationPermit
    }

    /// Captures the sole Ready admission for one durable observation epoch.
    /// This is the only API in this composition that accepts an authority fence.
    @MainActor
    static func beginReady(
        queueCutoff: UInt64,
        processedThrough: UInt64,
        authorityFence: PassiveCoreBluetoothArtifactAuthorityFence,
        gate: inout PassiveCoreBluetoothObservationBoundaryQueueGate
    ) throws -> Self {
        let authority = authorityFence.currentAuthority
        let decision = try PassiveCoreBluetoothObservationBoundaryDecision.capture(
            kind: .finiteAcquisitionReady,
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
            authorityFence: authorityFence,
            mutationPermit: PassiveCoreBluetoothObservationBoundaryMutationPermit()
        )
    }

    /// Performs the authority-fenced Ready recorder mutation exactly once for this
    /// admission and returns the only token allowed to commit the Ready queue
    /// transaction.
    func recordBoundary(
        on recorder: PassiveCoreBluetoothCaptureRecorder
    ) async throws -> RecordedReadyBoundary {
        try mutationPermit.claim()
        try await decision.recordBoundary(
            on: recorder,
            authorityFence: authorityFence
        )

        return RecordedReadyBoundary(
            decision: decision,
            transaction: transaction,
            authorityFence: authorityFence
        )
    }

    private init(
        decision: PassiveCoreBluetoothObservationBoundaryDecision,
        transaction: PassiveCoreBluetoothObservationBoundaryQueueGate.Transaction,
        authorityFence: PassiveCoreBluetoothArtifactAuthorityFence,
        mutationPermit: PassiveCoreBluetoothObservationBoundaryMutationPermit
    ) {
        self.decision = decision
        self.transaction = transaction
        self.authorityFence = authorityFence
        self.mutationPermit = mutationPermit
    }
}
