import NembraCore

public extension PassiveBluetoothExperimentOneCoordinator {
    enum CanonicalES80ConstructionError: Error, Equatable, Sendable {
        case fieldExecutionNotAuthorized
    }

    /// Canonical TODAY research-build construction path.
    ///
    /// The package itself resolves the mechanically identifiable build-time admission from the
    /// running signed app bundle. App code cannot pass a Boolean, preference, environment value, or
    /// imported JSON object to mint authority. Ordinary builds therefore remain fail-closed, while
    /// the exact field-candidate producer metadata can unlock the stationary READ-ONLY recipe.
    @MainActor
    static func makeAuthorizedES80() throws -> PassiveBluetoothExperimentOneCoordinator {
        guard PassiveBluetoothExperimentOneFieldExecutionGate.currentResearchBuildAdmission() != nil else {
            throw CanonicalES80ConstructionError.fieldExecutionNotAuthorized
        }
        return try makeResearchBuildCoordinator()
    }

    /// Future public/release field-authorized construction seam.
    ///
    /// The caller must possess a `VerifiedAdmission` minted only from the package's cryptographically
    /// verified external field authorization. This remains separate from TODAY's build-time research
    /// exception so the future release threat model can return to independently signed authority
    /// without widening the current app surface.
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

    @MainActor
    private static func makeResearchBuildCoordinator() throws -> PassiveBluetoothExperimentOneCoordinator {
        try makeLiveES80Coordinator()
    }
}
