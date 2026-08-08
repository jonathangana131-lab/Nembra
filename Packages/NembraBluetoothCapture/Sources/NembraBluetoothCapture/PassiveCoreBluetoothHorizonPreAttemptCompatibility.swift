import Foundation

/// Temporary source-compatibility bridge while the two accepted fourth-state Horizon
/// lineages converge on one spelling. The app-visible #598 lineage names the exact
/// producer proof around the recorder mutation boundary, while the reviewed controller
/// consumer from #571 names the same boundary as a pre-attempt abandonment.
///
/// Both forwarding methods preserve the original producer-issued one-shot receipt and
/// exact queue-gate validation; they mint no new authority and perform no lifecycle
/// mutation beyond the underlying accepted operations. Remove this bridge once the
/// shared Capture spine selects one canonical spelling and the controller is updated
/// directly to that API.
extension PassiveCoreBluetoothObservationBoundaryTransactionDecision.HorizonAdmission {
    func abandonBeforeRecorderAttempt() throws
        -> PassiveCoreBluetoothObservationBoundaryTransactionDecision.HorizonRecorderMutationAbandonmentReceipt {
        try abandonBeforeRecorderMutation()
    }
}

extension PassiveCoreBluetoothObservationBoundaryQueueGate {
    @discardableResult
    mutating func abortHorizonBeforeRecorderAttempt(
        after abandonment: PassiveCoreBluetoothObservationBoundaryTransactionDecision.HorizonRecorderMutationAbandonmentReceipt
    ) throws -> ObservationEpochAbortReceipt {
        try abortUncommittedHorizon(after: abandonment)
    }
}
