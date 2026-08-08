/// Package-owned field-execution lock for the first physical ES80 experiment.
///
/// V14's definitive physical runbook is currently NO-GO. Product UI must therefore keep every
/// action that asks the operator to begin the real OFF1 -> ON1 -> OFF2 -> ON2 physical procedure
/// unavailable in a field build, even when the underlying passive correlation producer is capable
/// of collecting software evidence.
///
/// This type deliberately has no GO state, no initializer, and no caller-supplied authorization
/// input. A future physical GO must be introduced by a deliberate accepted product change that
/// binds the final composed exact build, procedure/recipe provenance, app/runtime acceptance, and
/// the runbook's GO record. Flipping a UI Boolean or constructing a value in app code is not an
/// authorization path.
public enum PassiveBluetoothExperimentOneFieldExecutionGate {
    public static let recipeID: PassiveBluetoothExperimentRecipeID = .es80FingerprintV1
    public static let status: Status = .noGo(.finalComposedBuildNotAuthorized)
    public static let permitsPhysicalProcedure = false

    public enum Status: Equatable, Sendable {
        case noGo(NoGoBlocker)
    }

    public enum NoGoBlocker: Equatable, Sendable {
        /// The final app-visible Capture composition has not yet earned the V14 physical GO record.
        case finalComposedBuildNotAuthorized
    }
}
