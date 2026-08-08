import Foundation

enum PassiveCoreBluetoothObservationBoundaryMutationAttemptError: Error, Equatable, Sendable {
    case alreadyAttempted
}

/// Shared across every value copy of one exact Ready/Horizon admission.
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

/// Sealed Ready -> Horizon typestate using the canonical artifact-authority fence.
/// Software FIFO / artifact chronology only; no physical ES80 semantics are implied.
struct PassiveCoreBluetoothObservationBoundaryTransactionDecision: Equatable, Sendable {
    /// Issued only when the exact one-shot Ready admission loses canonical authority
    /// before the recorder mutation body executes. Other recorder failures mint no
    /// rollback authority because zero durable mutation is not proven.
    struct ReadyRecorderMutationRejectionReceipt: Equatable, Sendable {
        let queueCutoff: UInt64
        let authority: PassiveCoreBluetoothArtifactAuthorityContext
        let transactionRevision: UInt64
        let transactionIdentity: UUID
        let currentAuthority: PassiveCoreBluetoothArtifactAuthorityContext

        fileprivate init(
            decision: PassiveCoreBluetoothObservationBoundaryDecision,
            transaction: PassiveCoreBluetoothObservationBoundaryQueueGate.Transaction,
            currentAuthority: PassiveCoreBluetoothArtifactAuthorityContext
        ) {
            queueCutoff = decision.queueCutoff
            authority = decision.authority
            transactionRevision = transaction.revision
            transactionIdentity = transaction.identity
            self.currentAuthority = currentAuthority
        }
    }

    enum ReadyRecorderMutationOutcome: Equatable, Sendable {
        case recorded(RecordedReadyBoundary)
        case rejectedBeforeMutation(ReadyRecorderMutationRejectionReceipt)
    }

    struct RecordedReadyBoundary: Equatable, Sendable {
        private let decision: PassiveCoreBluetoothObservationBoundaryDecision
        private let transaction: PassiveCoreBluetoothObservationBoundaryQueueGate.Transaction
        private let authorityFence: PassiveCoreBluetoothArtifactAuthorityFence

        var queueCutoff: UInt64 { decision.queueCutoff }
        var authority: PassiveCoreBluetoothArtifactAuthorityContext { decision.authority }
        var observedAtUptimeNanoseconds: UInt64 { decision.observedAtUptimeNanoseconds }
        var observedAtDate: Date { decision.observedAtDate }
        var transactionRevision: UInt64 { transaction.revision }
        var transactionIdentity: UUID { transaction.identity }

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.decision == rhs.decision
                && lhs.transaction == rhs.transaction
                && lhs.authorityFence === rhs.authorityFence
        }

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
        var transactionRevision: UInt64 { readyTransaction.revision }
        var transactionIdentity: UUID { readyTransaction.identity }

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.readyDecision == rhs.readyDecision
                && lhs.readyTransaction == rhs.readyTransaction
                && lhs.authorityFence === rhs.authorityFence
        }

        /// Horizon admission consumes the exact process-local Ready transaction
        /// identity committed by this gate. Equal authority/cutoff values from another
        /// gate are not sufficient.
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
            let transaction = try gate.beginObservationHorizon(
                through: decision.queueCutoff,
                processedThrough: decision.processedThrough,
                authority: decision.authority,
                establishedByReadyRevision: readyTransaction.revision,
                establishedByReadyIdentity: readyTransaction.identity
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

        func recordBoundary(
            on recorder: PassiveCoreBluetoothCaptureRecorder
        ) async throws -> RecordedHorizonBoundary {
            try mutationPermit.claim()
            try await decision.recordBoundary(on: recorder, authorityFence: authorityFence)
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
        var transactionRevision: UInt64 { transaction.revision }
        var transactionIdentity: UUID { transaction.identity }

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
            authority: decision.authority
        )
        return Self(
            decision: decision,
            transaction: transaction,
            authorityFence: authorityFence,
            mutationPermit: PassiveCoreBluetoothObservationBoundaryMutationPermit()
        )
    }

    func recordBoundary(
        on recorder: PassiveCoreBluetoothCaptureRecorder
    ) async throws -> RecordedReadyBoundary {
        try mutationPermit.claim()
        try await decision.recordBoundary(on: recorder, authorityFence: authorityFence)
        return RecordedReadyBoundary(
            decision: decision,
            transaction: transaction,
            authorityFence: authorityFence
        )
    }

    /// Consumes the same one-shot permit as ordinary `recordBoundary`. Only canonical
    /// authority revocation before mutation produces a recovery receipt.
    func recordBoundaryWithMutationOutcome(
        on recorder: PassiveCoreBluetoothCaptureRecorder
    ) async throws -> ReadyRecorderMutationOutcome {
        try mutationPermit.claim()
        do {
            try await decision.recordBoundary(on: recorder, authorityFence: authorityFence)
            return .recorded(
                RecordedReadyBoundary(
                    decision: decision,
                    transaction: transaction,
                    authorityFence: authorityFence
                )
            )
        } catch let error as PassiveCoreBluetoothArtifactAuthorityFence.StateError {
            switch error {
            case let .authorityChanged(expected, current):
                guard expected == decision.authority else { throw error }
                return .rejectedBeforeMutation(
                    ReadyRecorderMutationRejectionReceipt(
                        decision: decision,
                        transaction: transaction,
                        currentAuthority: current
                    )
                )
            case .nonAdvancingTransition:
                throw error
            }
        }
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
