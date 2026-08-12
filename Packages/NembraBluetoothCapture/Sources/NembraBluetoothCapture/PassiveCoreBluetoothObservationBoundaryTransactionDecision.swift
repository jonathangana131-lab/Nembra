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

    /// Producer-issued proof that the exact Ready admission was deliberately
    /// abandoned before any recorder attempt. Claiming this receipt consumes the
    /// same shared one-shot permit as recording, so no copy can later append Ready.
    struct ReadyPreAttemptAbandonmentReceipt: Equatable, Sendable {
        let queueCutoff: UInt64
        let authority: PassiveCoreBluetoothArtifactAuthorityContext
        let transactionRevision: UInt64
        let transactionIdentity: UUID

        fileprivate init(
            decision: PassiveCoreBluetoothObservationBoundaryDecision,
            transaction: PassiveCoreBluetoothObservationBoundaryQueueGate.Transaction
        ) {
            queueCutoff = decision.queueCutoff
            authority = decision.authority
            transactionRevision = transaction.revision
            transactionIdentity = transaction.identity
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

    /// Issued only when the exact one-shot Horizon admission loses canonical
    /// authority before the recorder mutation body executes. It proves zero durable H
    /// mutation for this exact producer transaction; it is not a recorded-H token.
    struct HorizonRecorderMutationRejectionReceipt: Equatable, Sendable {
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

    /// Producer-issued proof that the exact Horizon admission was deliberately
    /// abandoned before any recorder mutation attempt. Claiming this receipt consumes
    /// the same shared one-shot permit as recording, so no copy can later append H.
    struct HorizonRecorderMutationAbandonmentReceipt: Equatable, Sendable {
        let queueCutoff: UInt64
        let authority: PassiveCoreBluetoothArtifactAuthorityContext
        let transactionRevision: UInt64
        let transactionIdentity: UUID

        fileprivate init(
            decision: PassiveCoreBluetoothObservationBoundaryDecision,
            transaction: PassiveCoreBluetoothObservationBoundaryQueueGate.Transaction
        ) {
            queueCutoff = decision.queueCutoff
            authority = decision.authority
            transactionRevision = transaction.revision
            transactionIdentity = transaction.identity
        }
    }

    enum HorizonRecorderMutationOutcome: Equatable, Sendable {
        case recorded(RecordedHorizonBoundary)
        case rejectedBeforeMutation(HorizonRecorderMutationRejectionReceipt)
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

        /// Deliberately abandons this exact admission before any recorder call. The
        /// shared permit proves no value copy has already attempted H mutation and is
        /// consumed permanently so later recording/rejection cannot be fabricated.
        func abandonBeforeRecorderMutation() throws -> HorizonRecorderMutationAbandonmentReceipt {
            try mutationPermit.claim()
            return HorizonRecorderMutationAbandonmentReceipt(
                decision: decision,
                transaction: transaction
            )
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

        /// Consumes the same one-shot permit as ordinary `recordBoundary`. Only
        /// canonical authority revocation before the recorder mutation body executes
        /// produces zero-H recovery authority. Arbitrary recorder errors do not.
        func recordBoundaryWithMutationOutcome(
            on recorder: PassiveCoreBluetoothCaptureRecorder
        ) async throws -> HorizonRecorderMutationOutcome {
            try mutationPermit.claim()
            do {
                try await decision.recordBoundary(on: recorder, authorityFence: authorityFence)
                return .recorded(
                    RecordedHorizonBoundary(
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
                        HorizonRecorderMutationRejectionReceipt(
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
        var transactionRevision: UInt64 { transaction.revision }
        var transactionIdentity: UUID { transaction.identity }

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

    /// Deliberately abandons this exact Ready admission before any recorder call.
    /// The shared permit proves no value copy has already attempted Ready mutation
    /// and is consumed permanently so later recording/rejection cannot be fabricated.
    func abandonBeforeRecorderAttempt() throws -> ReadyPreAttemptAbandonmentReceipt {
        try mutationPermit.claim()
        return ReadyPreAttemptAbandonmentReceipt(
            decision: decision,
            transaction: transaction
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
