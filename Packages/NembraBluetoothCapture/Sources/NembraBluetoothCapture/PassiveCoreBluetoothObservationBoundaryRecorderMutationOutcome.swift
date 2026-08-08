/// Result of routing one sealed observation-boundary decision through the recorder
/// mutation authority fence.
///
/// A rejection receipt is issued only when the exact sealed fence reports that the
/// decision's authority was replaced before the recorder mutation could enter its
/// synchronous critical section. It is software lifecycle authority only; it says
/// nothing about BLE/RF timing or physical scooter state.
enum PassiveCoreBluetoothObservationBoundaryRecorderMutationOutcome: Equatable, Sendable {
    case recorded
    case rejectedBeforeMutation(
        PassiveCoreBluetoothObservationBoundaryRecorderMutationRejectionReceipt
    )
}

/// Non-forgeable-in-package proof that one sealed boundary recorder mutation was
/// rejected by the exact artifact-authority fence before its mutation body ran.
///
/// The initializer is file-private. Other package files may inspect and consume a
/// receipt that the sealed decision actually issued, but they cannot manufacture one
/// from caller-supplied queue/authority scalars and use it to erase an in-flight gate
/// transaction.
struct PassiveCoreBluetoothObservationBoundaryRecorderMutationRejectionReceipt:
    Equatable,
    Sendable
{
    enum Reason: Equatable, Sendable {
        case artifactAuthorityChangedBeforeMutation
    }

    let queueKind: PassiveCoreBluetoothObservationBoundaryQueueGate.BoundaryKind
    let queueCutoff: UInt64
    let authority: PassiveCoreBluetoothArtifactAuthorityContext
    let reason: Reason

    fileprivate init(
        decision: PassiveCoreBluetoothObservationBoundaryTransactionDecision,
        reason: Reason
    ) {
        queueKind = decision.queueKind
        queueCutoff = decision.queueCutoff
        authority = decision.authority
        self.reason = reason
    }
}

extension PassiveCoreBluetoothObservationBoundaryTransactionDecision {
    /// Attempts the irreversible recorder mutation while preserving a mechanical
    /// recovery authority for the one failure that proves zero mutation occurred.
    ///
    /// `PassiveCoreBluetoothArtifactAuthorityMutationFence.StateError.authorityChanged`
    /// is thrown before the fenced mutation closure executes. That exact failure may
    /// therefore issue a rejection receipt. All recorder/session validation failures
    /// continue throwing and issue no rollback authority because durable mutation
    /// status cannot be inferred from a generic error.
    func recordBoundaryWithMutationOutcome(
        on recorder: PassiveCoreBluetoothCaptureRecorder
    ) async throws -> PassiveCoreBluetoothObservationBoundaryRecorderMutationOutcome {
        do {
            try await recordBoundary(on: recorder)
            return .recorded
        } catch let error as PassiveCoreBluetoothArtifactAuthorityMutationFence.StateError {
            guard error == .authorityChanged else {
                throw error
            }
            return .rejectedBeforeMutation(
                PassiveCoreBluetoothObservationBoundaryRecorderMutationRejectionReceipt(
                    decision: self,
                    reason: .artifactAuthorityChangedBeforeMutation
                )
            )
        }
    }
}
