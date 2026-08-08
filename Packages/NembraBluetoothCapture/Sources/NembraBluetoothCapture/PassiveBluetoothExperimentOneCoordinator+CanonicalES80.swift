import NembraCore

public extension PassiveBluetoothExperimentOneCoordinator {
    enum CanonicalES80ConstructionError: Error, Equatable, Sendable {
        case fieldExecutionNotAuthorized
    }

    /// Legacy/current NembraApp construction path.
    ///
    /// This zero-argument API is intentionally permanently fail-closed. It must never become a live
    /// field path merely because the repository-wide final gate is later changed to GO: doing that
    /// would let app code bypass non-forgeable package admission entirely.
    @MainActor
    static func makeAuthorizedES80() throws -> PassiveBluetoothExperimentOneCoordinator {
        throw CanonicalES80ConstructionError.fieldExecutionNotAuthorized
    }

    /// Public/release field-authorized construction seam.
    ///
    /// The caller must possess a `VerifiedAdmission` minted only from the package's cryptographically
    /// verified external field authorization AND the package's final public field-execution policy
    /// must have deliberately reached GO. While the repository gate remains NO-GO this overload
    /// fails before CoreBluetooth is instantiated.
    @MainActor
    static func makeAuthorizedES80(
        verifiedAdmission _: PassiveBluetoothExperimentOneFieldExecutionGate.VerifiedAdmission
    ) throws -> PassiveBluetoothExperimentOneCoordinator {
        guard PassiveBluetoothExperimentOneFieldExecutionGate.permitsPhysicalProcedure else {
            throw CanonicalES80ConstructionError.fieldExecutionNotAuthorized
        }

        return try makeLiveES80Coordinator()
    }

    /// TODAY-only private research construction seam for the first stationary read-only artifact.
    ///
    /// `PrivateResearchAdmission` has no public initializer. It can be minted only after the package
    /// verifies the running app's exact recipe/source/build-instance marker against its measured
    /// executable/Info.plist build identity. This path deliberately does not flip or consult the
    /// public release `permitsPhysicalProcedure` Boolean; the admission itself is the narrow private
    /// authority. App code must still require explicit operator confirmation before calling here.
    @MainActor
    static func makeAuthorizedES80(
        privateResearchAdmission _: PassiveBluetoothExperimentOneFieldExecutionGate.PrivateResearchAdmission
    ) throws -> PassiveBluetoothExperimentOneCoordinator {
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
