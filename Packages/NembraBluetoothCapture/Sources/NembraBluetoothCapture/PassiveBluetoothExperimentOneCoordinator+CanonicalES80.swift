import NembraCore

public extension PassiveBluetoothExperimentOneCoordinator {
    /// Creates the one canonical ES80 Experiment One owner, including its foreground controller,
    /// only after the package-owned mechanical physical gate has deliberately earned GO.
    ///
    /// Product UI cannot choose a controller, vehicle identity, target UUID, recorder, admission,
    /// recipe, or local preference that bypasses this check. In the current V14 build the field gate
    /// has no GO case, so this factory fails closed and exposes no physical OFF/ON workflow.
    @MainActor
    static func makeAuthorizedES80() throws -> PassiveBluetoothExperimentOneCoordinator {
        guard PassiveBluetoothExperimentOneFieldExecutionGate.permitsPhysicalProcedure else {
            throw CoordinatorError.fieldExecutionNotAuthorized
        }

        let vehicleIdentity = VehicleProfile.aovoproES80.identity
        let controller = try ForegroundCoreBluetoothCaptureController(
            vehicleIdentity: vehicleIdentity
        )
        return try PassiveBluetoothExperimentOneCoordinator(controller: controller)
    }
}