import NembraCore

public extension PassiveBluetoothExperimentOneCoordinator {
    enum CanonicalES80ConstructionError: Error, Equatable, Sendable {
        case fieldExecutionNotAuthorized
    }

    /// Private first-capture construction path.
    ///
    /// The package, not NembraApp, resolves the running signed application's research admission.
    /// A normal launch flag, Settings preference, typed recipe, or imported JSON therefore cannot
    /// turn this zero-argument API into a live CoreBluetooth path. Only the exact build-time research
    /// marker bound to the validated source commit + build instance can pass the gate.
    @MainActor
    static func makeAuthorizedES80() throws -> PassiveBluetoothExperimentOneCoordinator {
        guard PassiveBluetoothExperimentOneFieldExecutionGate.currentResearchAdmission() != nil else {
            throw CanonicalES80ConstructionError.fieldExecutionNotAuthorized
        }
        return try makeLiveES80Coordinator()
    }

    /// Release-grade field-authorized construction seam.
    ///
    /// The caller must possess a `VerifiedAdmission` minted only from the package's cryptographically
    /// verified external field authorization. That release/public path remains deliberately NO-GO
    /// while the independent trust root is unconfigured; it is separate from today's exact signed
    /// private-research build admission.
    @MainActor
    static func makeAuthorizedES80(
        verifiedAdmission _: PassiveBluetoothExperimentOneFieldExecutionGate.VerifiedAdmission
    ) throws -> PassiveBluetoothExperimentOneCoordinator {
        guard case .noGo = PassiveBluetoothExperimentOneFieldExecutionGate.status else {
            return try makeLiveES80Coordinator()
        }
        throw CanonicalES80ConstructionError.fieldExecutionNotAuthorized
    }

    @MainActor
    private static func makeLiveES80Coordinator() throws -> PassiveBluetoothExperimentOneCoordinator {
        let controller = try ForegroundCoreBluetoothCaptureController(
            vehicleIdentity: VehicleProfile.aovoproES80.identity
        )
        return try PassiveBluetoothExperimentOneCoordinator(controller: controller)
    }
}
