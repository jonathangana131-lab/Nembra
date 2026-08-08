import NembraCore

public extension PassiveBluetoothExperimentOneCoordinator {
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