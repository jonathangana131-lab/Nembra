import NembraCore

public extension PassiveBluetoothExperimentOneCoordinator {
    enum CanonicalES80ConstructionError: Error, Equatable, Sendable {
        case fieldExecutionNotAuthorized
    }

    /// Canonical NembraApp construction path for the private Experiment One field build.
    ///
    /// Ordinary/debug/release builds remain fail-closed because
    /// `PassiveBluetoothExperimentOneFieldExecutionGate.status` is NO-GO unless the running app has
    /// the complete exact-runtime metadata shape emitted by the signed field-candidate producer for
    /// `ES80-FINGERPRINT-v1`. A Settings toggle, launch argument, environment variable, or imported
    /// unsigned JSON cannot make this factory live.
    ///
    /// This temporary research-build path exists only to unlock the first stationary, charger-
    /// disconnected, read-only ES80 artifact under CAPTURE_TODAY_FIELD_READY_DIRECTIVE.md. The
    /// future public/release path remains the admission-bearing overload below.
    @MainActor
    static func makeAuthorizedES80() throws -> PassiveBluetoothExperimentOneCoordinator {
        guard case .researchBuildAuthorized = PassiveBluetoothExperimentOneFieldExecutionGate.status,
              PassiveBluetoothExperimentOneFieldExecutionGate.permitsPhysicalProcedure else {
            throw CanonicalES80ConstructionError.fieldExecutionNotAuthorized
        }

        return try makeLiveES80Coordinator()
    }

    /// Release-grade field-authorized construction seam.
    ///
    /// The caller must possess a `VerifiedAdmission` minted only from the package's cryptographically
    /// verified external field authorization AND the package's final field-execution policy must have
    /// deliberately reached a permissive state. The private TODAY research-build path above does not
    /// mint this capability and does not weaken the independent-signature verifier.
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
