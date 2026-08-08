import NembraCore

public extension PassiveBluetoothExperimentOneCoordinator {
    enum CanonicalES80ConstructionError: Error, Equatable, Sendable {
        case fieldExecutionNotAuthorized
    }

    /// Canonical NembraApp construction path for the private first ES80 research artifact.
    ///
    /// Ordinary, Debug, Simulator, and package-test builds remain fail-closed. The package can create
    /// live CoreBluetooth authority only when its process-lifetime field gate resolved the running
    /// physical-iOS Release app as the exact canonical `ES80-FINGERPRINT-v1` Research Field Build.
    /// App preferences, launch arguments, environment variables, imported JSON, and caller Booleans
    /// cannot mint that admission.
    ///
    /// Signed-installable/intended-device acceptance and the final exact runbook remain mandatory
    /// before the operator may actually perform the physical experiment.
    @MainActor
    static func makeAuthorizedES80() throws -> PassiveBluetoothExperimentOneCoordinator {
        guard case .researchBuildAuthorized = PassiveBluetoothExperimentOneFieldExecutionGate.status,
              PassiveBluetoothExperimentOneFieldExecutionGate.currentResearchBuildAdmission != nil,
              PassiveBluetoothExperimentOneFieldExecutionGate.permitsPhysicalProcedure else {
            throw CanonicalES80ConstructionError.fieldExecutionNotAuthorized
        }

        return try makeLiveES80Coordinator()
    }

    /// Release-grade field-authorized construction seam.
    ///
    /// The caller must possess a `VerifiedAdmission` minted only from the package's cryptographically
    /// verified external field authorization AND the package's field-execution policy must permit the
    /// procedure. TODAY's private research path does not mint or weaken this stronger later boundary.
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
