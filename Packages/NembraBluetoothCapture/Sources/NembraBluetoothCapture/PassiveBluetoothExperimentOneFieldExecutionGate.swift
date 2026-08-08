/// Package-owned field-execution lock for the first physical ES80 experiment.
///
/// The default V14 state remains mechanically NO-GO. The only GO vocabulary requires a
/// `PassiveBluetoothCaptureVerifiedFieldAuthorization`, whose initializer is package-sealed and
/// whose public producer verifies an externally signed exact-build authorization against the
/// application that is actually running.
///
/// A UI Boolean, preference, caller-selected SHA, parsed-but-unsigned build record, or directly
/// constructed status can therefore never authorize the physical OFF1 -> ON1 -> OFF2 -> ON2 flow.
public enum PassiveBluetoothExperimentOneFieldExecutionGate {
    public static let recipeID: PassiveBluetoothExperimentRecipeID = .es80FingerprintV1

    /// Repository/default field state. This remains NO-GO even though the vocabulary now knows how
    /// to represent a separately verified exact-build authorization.
    public static let status: Status = .noGo(.finalComposedBuildNotAuthorized)

    /// Default builds remain locked. Kept for current app/source compatibility and for an explicit
    /// truthful NO-GO surface when no verified external authorization has been supplied.
    public static var permitsPhysicalProcedure: Bool {
        permitsPhysicalProcedure(status: status)
    }

    /// Maps only the package verifier's non-forgeable result into GO state.
    public static func status(
        for authorization: PassiveBluetoothCaptureVerifiedFieldAuthorization
    ) -> Status {
        .go(authorization)
    }

    /// Convenience for product callers that already hold a verified authorization. This accepts no
    /// Boolean, build string, digest, or untrusted external record.
    public static func permitsPhysicalProcedure(
        for authorization: PassiveBluetoothCaptureVerifiedFieldAuthorization
    ) -> Bool {
        permitsPhysicalProcedure(status: status(for: authorization))
    }

    package static func permitsPhysicalProcedure(status: Status) -> Bool {
        switch status {
        case .noGo:
            return false
        case .go:
            return true
        }
    }

    public enum Status: Equatable, Sendable {
        case noGo(NoGoBlocker)
        case go(PassiveBluetoothCaptureVerifiedFieldAuthorization)
    }

    public enum NoGoBlocker: Equatable, Sendable {
        /// No verified exact-build authorization has been supplied for this running app.
        case finalComposedBuildNotAuthorized
    }
}
