import NembraCore

public extension PassiveBluetoothExperimentOneCoordinator {
    enum CanonicalES80ConstructionError: Error, Equatable, Sendable {
        case fieldExecutionNotAuthorized
    }

    /// The current production construction path used by NembraApp.
    ///
    /// It intentionally remains tied to the zero-argument package field gate, which is hard NO-GO.
    /// A Release launch marker, app preference, environment variable, or caller Boolean therefore
    /// cannot construct a live ES80 controller in today's build.
    @MainActor
    static func makeAuthorizedES80() throws -> PassiveBluetoothExperimentOneCoordinator {
        guard PassiveBluetoothExperimentOneFieldExecutionGate.permitsPhysicalProcedure else {
            throw CanonicalES80ConstructionError.fieldExecutionNotAuthorized
        }

        return try makeLiveES80Coordinator()
    }

    /// Future field-authorized construction seam.
    ///
    /// The caller must possess a `VerifiedAdmission` minted only from the package's cryptographically
    /// verified external field authorization. The admission type has no public initializer, so this
    /// overload does not create a caller-forgeable Boolean/setting path. Production cannot reach it
    /// today because the package authorization trust root remains unconfigured and NembraApp still
    /// calls the locked zero-argument factory.
    @MainActor
    static func makeAuthorizedES80(
        verifiedAdmission _: PassiveBluetoothExperimentOneFieldExecutionGate.VerifiedAdmission
    ) throws -> PassiveBluetoothExperimentOneCoordinator {
        try makeLiveES80Coordinator()
    }

    @MainActor
    private static func makeLiveES80Coordinator() throws -> PassiveBluetoothExperimentOneCoordinator {
        let controller = try ForegroundCoreBluetoothCaptureController(
            vehicleIdentity: VehicleProfile.aovoproES80.identity
        )
        return try PassiveBluetoothExperimentOneCoordinator(controller: controller)
    }
}
