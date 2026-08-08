import Foundation

/// Producer-issued proof that an exact one-shot Horizon admission was rejected by
/// the canonical artifact-authority fence before the recorder mutation body ran.
///
/// This is deliberately distinct from `RecordedHorizonBoundary`: it proves **zero
/// durable Horizon mutation**. It therefore cannot be used to claim Horizon
/// evidence, terminal freeze, or physical capture completeness.
struct PassiveCoreBluetoothHorizonRecorderMutationRejectionReceipt: Equatable, Sendable {
    let queueCutoff: UInt64
    let authority: PassiveCoreBluetoothArtifactAuthorityContext
    let transactionRevision: UInt64
    let transactionIdentity: UUID
    let currentAuthority: PassiveCoreBluetoothArtifactAuthorityContext

    fileprivate init(
        admission: PassiveCoreBluetoothObservationBoundaryTransactionDecision.HorizonAdmission,
        currentAuthority: PassiveCoreBluetoothArtifactAuthorityContext
    ) {
        queueCutoff = admission.queueCutoff
        authority = admission.authority
        transactionRevision = admission.transactionRevision
        transactionIdentity = admission.transactionIdentity
        self.currentAuthority = currentAuthority
    }
}

enum PassiveCoreBluetoothHorizonRecorderMutationOutcome: Equatable, Sendable {
    case recorded(PassiveCoreBluetoothObservationBoundaryTransactionDecision.RecordedHorizonBoundary)
    case rejectedBeforeMutation(PassiveCoreBluetoothHorizonRecorderMutationRejectionReceipt)
}

extension PassiveCoreBluetoothObservationBoundaryTransactionDecision.HorizonAdmission {
    /// Consumes the same one-shot mutation permit as ordinary `recordBoundary`.
    /// Only canonical authority revocation may mint zero-mutation recovery proof.
    /// Generic recorder failures remain ambiguous and issue no rollback authority.
    func recordBoundaryWithMutationOutcome(
        on recorder: PassiveCoreBluetoothCaptureRecorder
    ) async throws -> PassiveCoreBluetoothHorizonRecorderMutationOutcome {
        do {
            return .recorded(try await recordBoundary(on: recorder))
        } catch let error as PassiveCoreBluetoothArtifactAuthorityFence.StateError {
            switch error {
            case let .authorityChanged(expected, current):
                guard expected == authority else { throw error }
                return .rejectedBeforeMutation(
                    PassiveCoreBluetoothHorizonRecorderMutationRejectionReceipt(
                        admission: self,
                        currentAuthority: current
                    )
                )
            case .nonAdvancingTransition:
                throw error
            }
        }
    }
}
