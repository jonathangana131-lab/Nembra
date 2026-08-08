import NembraCore

public extension PassiveBluetoothExperimentOneCoordinator {
    enum CanonicalES80ConstructionError: Error, Equatable, Sendable {
        case fieldExecutionNotAuthorized
    }

    /// Canonical TODAY research-field construction path used by NembraApp.
    ///
    /// The zero-argument shape does not mean caller-controlled authority. It succeeds only when the
    /// package has already admitted the *running application itself* as the exact build-time research
    /// configuration: canonical `ES80-FINGERPRINT-v1` recipe marker + matching embedded build tuple +
    /// exact runtime executable/Info.plist identity. Ordinary builds, tests, preferences, launch
    /// arguments, environment variables, and imported JSON therefore remain fail-closed.
    ///
    /// This private first-capture path is intentionally narrower than future public release authority.
    /// Signed-installable/intended-device acceptance and the final runbook remain required before the
    /// operator may perform the physical experiment.
    @MainActor
    static func makeAuthorizedES80() throws -> PassiveBluetoothExperimentOneCoordinator {
        guard PassiveBluetoothExperimentOneFieldExecutionGate.currentResearchBuildAdmission != nil,
              PassiveBluetoothExperimentOneFieldExecutionGate.permitsPhysicalProcedure else {
            throw CanonicalES80ConstructionError.fieldExecutionNotAuthorized
        }

        return try makeLiveES80Coordinator()
    }

    /// Release-grade field-authorized construction seam.
    ///
    /// The caller must possess a `VerifiedAdmission` minted only from the package's cryptographically
    /// verified external field authorization AND the package's field-execution policy must permit the
    /// procedure. The admission type has no public initializer, so this remains unavailable to
    /// caller-authored Boolean/settings state. TODAY's build-time research path does not remove or
    /// weaken this stronger later release boundary.
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
