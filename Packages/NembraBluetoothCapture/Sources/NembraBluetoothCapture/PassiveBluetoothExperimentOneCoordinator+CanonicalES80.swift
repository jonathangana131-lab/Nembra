import NembraCore

public extension PassiveBluetoothExperimentOneCoordinator {
    enum CanonicalES80ConstructionError: Error, Equatable, Sendable {
        case fieldExecutionNotAuthorized
    }

    /// Legacy/current NembraApp construction path.
    ///
    /// This zero-argument API is intentionally permanently fail-closed. It must never become a live
    /// field path merely because the repository-wide final gate is later changed to GO: doing that
    /// would let app code bypass the non-forgeable exact signed-field `VerifiedAdmission` entirely.
    /// NembraApp may continue calling this while physical execution is locked; future real field
    /// wiring must migrate to the admission-bearing overload rather than weakening this method.
    @MainActor
    static func makeAuthorizedES80() throws -> PassiveBluetoothExperimentOneCoordinator {
        throw CanonicalES80ConstructionError.fieldExecutionNotAuthorized
    }

    /// Future field-authorized construction seam.
    ///
    /// The caller must possess a `VerifiedAdmission` minted only from the package's cryptographically
    /// verified external field authorization AND the package's final field-execution policy must have
    /// deliberately reached GO. Signed evidence is necessary but not sufficient: while the repository
    /// gate remains NO-GO this overload fails before CoreBluetooth is instantiated, so merely parsing
    /// an independently signed authorization cannot cause Bluetooth permission/transport side effects.
    /// The admission type has no public initializer, so this overload also does not create a
    /// caller-forgeable Boolean/setting path.
    @MainActor
    static func makeAuthorizedES80(
        verifiedAdmission _: PassiveBluetoothExperimentOneFieldExecutionGate.VerifiedAdmission
    ) throws -> PassiveBluetoothExperimentOneCoordinator {
        guard PassiveBluetoothExperimentOneFieldExecutionGate.permitsPhysicalProcedure else {
            throw CanonicalES80ConstructionError.fieldExecutionNotAuthorized
        }

        return try makeLiveES80Coordinator()
    }

    @MainActor
    private static func makeLiveES80Coordinator() throws -> PassiveBluetoothExperimentOneCoordinator {
        let controller = try ForegroundCoreBluetoothCaptureController(
            vehicleIdentity: VehicleProfile.aovoproES80.identity
        )
        return try PassiveBluetoothExperimentOneCoordinator(controller: controller)
    }
}
