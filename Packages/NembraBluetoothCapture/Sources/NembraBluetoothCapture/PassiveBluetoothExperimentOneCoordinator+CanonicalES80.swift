import NembraCore

public extension PassiveBluetoothExperimentOneCoordinator {
    /// Creates the canonical ES80 Experiment One owner, including its foreground
    /// controller, inside the capture package.
    ///
    /// Product UI should prefer this initializer so it cannot accidentally splice a
    /// separately-created generic controller into the package-owned Experiment One
    /// provenance life. The canonical software vehicle context is still not physical
    /// scooter authentication.
    @MainActor
    convenience init() throws {
        let vehicleIdentity = VehicleProfile.aovoproES80.identity
        let controller = try ForegroundCoreBluetoothCaptureController(
            vehicleIdentity: vehicleIdentity
        )
        try self.init(
            controller: controller,
            vehicleIdentity: vehicleIdentity
        )
    }
}
