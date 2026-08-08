import NembraCore

public extension PassiveBluetoothExperimentOneCoordinator {
    enum CanonicalES80ConstructionError: Error, Equatable, Sendable {
        case fieldExecutionNotAuthorized
    }

    /// The only production construction path for the physical ES80 Experiment One owner.
    ///
    /// The package-owned mechanical field gate must already permit the physical procedure before a
    /// live CoreBluetooth controller is created. In the current V14 build the gate has no GO case,
    /// so this factory fails closed and SwiftUI cannot expose OFF/ON field actions merely because it
    /// knows the coordinator type exists.
    @MainActor
    static func makeAuthorizedES80() throws -> PassiveBluetoothExperimentOneCoordinator {
        guard PassiveBluetoothExperimentOneFieldExecutionGate.permitsPhysicalProcedure else {
            throw CanonicalES80ConstructionError.fieldExecutionNotAuthorized
        }

        let controller = try ForegroundCoreBluetoothCaptureController(
            vehicleIdentity: VehicleProfile.aovoproES80.identity
        )
        return try PassiveBluetoothExperimentOneCoordinator(controller: controller)
    }
}
