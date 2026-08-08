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
    /// The caller may only possess a `VerifiedAdmission` minted from the package's cryptographically
    /// verified external field authorization. That release/public path remains deliberately NO-GO
    /// until the independent trust root is configured and separately accepted; today's private
    /// research marker must never promote this release seam.
    @MainActor
    static func makeAuthorizedES80(
        verifiedAdmission _: PassiveBluetoothExperimentOneFieldExecutionGate.VerifiedAdmission
    ) throws -> PassiveBluetoothExperimentOneCoordinator {
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
