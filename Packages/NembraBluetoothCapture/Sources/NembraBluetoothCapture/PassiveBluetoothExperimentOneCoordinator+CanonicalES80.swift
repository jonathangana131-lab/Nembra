import NembraCore

public extension PassiveBluetoothExperimentOneCoordinator {
    enum CanonicalES80ConstructionError: Error, Equatable, Sendable {
        case fieldExecutionNotAuthorized
    }

    /// Legacy zero-argument path.
    ///
    /// This API is intentionally permanently fail-closed. It must never become a live field path
    /// merely because either the release-grade or private-research authority model changes.
    @MainActor
    static func makeAuthorizedES80() throws -> PassiveBluetoothExperimentOneCoordinator {
        throw CanonicalES80ConstructionError.fieldExecutionNotAuthorized
    }

    /// Release-grade field-authorized construction seam.
    ///
    /// The caller must possess a `VerifiedAdmission` minted only from the package's independently
    /// verified signed field authorization AND the default package field gate must deliberately be GO.
    /// The current public-release gate remains NO-GO, so this path still fails before CoreBluetooth.
    @MainActor
    static func makeAuthorizedES80(
        verifiedAdmission _: PassiveBluetoothExperimentOneFieldExecutionGate.VerifiedAdmission
    ) throws -> PassiveBluetoothExperimentOneCoordinator {
        guard PassiveBluetoothExperimentOneFieldExecutionGate.permitsPhysicalProcedure else {
            throw CanonicalES80ConstructionError.fieldExecutionNotAuthorized
        }

        return try makeLiveES80Coordinator()
    }

    /// Narrow private-research path for the first stationary passive ES80 artifact.
    ///
    /// No admission value is supplied by app/UI code. The package first derives an opaque capability
    /// from the exact running app's producer-shaped build metadata plus executable / Info.plist hashes.
    /// Only after that succeeds is CoreBluetooth instantiated. This cannot be enabled by UserDefaults,
    /// launch arguments, imported JSON, a target UUID, or a caller-provided Boolean.
    @MainActor
    static func makeResearchAuthorizedES80ForCurrentApplication() throws
        -> PassiveBluetoothExperimentOneCoordinator {
        let admission: PassiveBluetoothExperimentOneFieldExecutionGate.ResearchAdmission
        do {
            admission = try PassiveBluetoothExperimentOneFieldExecutionGate
                .researchAdmissionForCurrentApplication()
        } catch {
            throw CanonicalES80ConstructionError.fieldExecutionNotAuthorized
        }

        return try makeLiveResearchES80Coordinator(admission: admission)
    }

    @MainActor
    private static func makeLiveES80Coordinator() throws -> PassiveBluetoothExperimentOneCoordinator {
        let controller = try ForegroundCoreBluetoothCaptureController(
            vehicleIdentity: VehicleProfile.aovoproES80.identity
        )
        return try PassiveBluetoothExperimentOneCoordinator(controller: controller)
    }

    @MainActor
    private static func makeLiveResearchES80Coordinator(
        admission: PassiveBluetoothExperimentOneFieldExecutionGate.ResearchAdmission
    ) throws -> PassiveBluetoothExperimentOneCoordinator {
        let controller = try ForegroundCoreBluetoothCaptureController(
            vehicleIdentity: VehicleProfile.aovoproES80.identity
        )
        return try PassiveBluetoothExperimentOneCoordinator(
            controller: controller,
            researchAdmission: admission
        )
    }
}
