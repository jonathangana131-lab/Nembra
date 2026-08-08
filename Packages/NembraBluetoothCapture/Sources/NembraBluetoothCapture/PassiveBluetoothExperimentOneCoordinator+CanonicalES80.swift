import NembraCore

public extension PassiveBluetoothExperimentOneCoordinator {
    enum CanonicalES80ConstructionError: Error, Equatable, Sendable {
        case fieldExecutionNotAuthorized
    }

    /// TODAY private Research Field Build construction path.
    ///
    /// This zero-argument API remains fail-closed for normal builds. It can instantiate CoreBluetooth
    /// only when the package itself mints a `ResearchBuildAdmission` from the exact running app's
    /// signed build-time Info.plist metadata for `ES80-FINGERPRINT-v1`. Callers cannot supply a Boolean,
    /// Settings value, launch marker, or imported JSON object to this method.
    ///
    /// The resulting coordinator is still downstream of stationary + charger-disconnected preflight,
    /// deterministic OFF/ON target correlation, explicit operator action, and Experiment One's
    /// no-application-write contract. This narrow research seam is not general/public release GO.
    @MainActor
    static func makeAuthorizedES80() throws -> PassiveBluetoothExperimentOneCoordinator {
        guard PassiveBluetoothExperimentOneFieldExecutionGate.admitCurrentApplicationResearchBuild() != nil else {
            throw CanonicalES80ConstructionError.fieldExecutionNotAuthorized
        }

        return try makeLiveES80Coordinator()
    }

    /// Future release-grade field-authorized construction seam.
    ///
    /// The caller must possess a `VerifiedAdmission` minted only from the package's cryptographically
    /// verified external field authorization AND the release-grade package field-execution policy must
    /// deliberately reach GO. The TODAY build-time research capability above does not change this path.
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
