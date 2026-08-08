import NembraCore

public extension PassiveBluetoothExperimentOneCoordinator {
    enum CanonicalES80ConstructionError: Error, Equatable, Sendable {
        case fieldExecutionNotAuthorized
    }

    /// Canonical NembraApp construction path for the first private ES80 research artifact.
    ///
    /// This remains fail-closed for ordinary builds. It can construct live CoreBluetooth only when
    /// the package itself derives a `ResearchBuildAdmission` from the running signed iOS Release
    /// bundle's exact dedicated field-build metadata. App preferences, launch arguments, environment
    /// variables, imported JSON, and caller-supplied Booleans cannot reach this path.
    ///
    /// The research exception is deliberately narrower than future public release authority and does
    /// not replace the independently signed `VerifiedAdmission` overload below.
    @MainActor
    static func makeAuthorizedES80() throws -> PassiveBluetoothExperimentOneCoordinator {
        guard PassiveBluetoothExperimentOneFieldExecutionGate.currentResearchBuildAdmission != nil else {
            throw CanonicalES80ConstructionError.fieldExecutionNotAuthorized
        }

        return try makeResearchFieldCoordinator()
    }

#if DEBUG && targetEnvironment(simulator)
    /// Package-owned inert construction path for synthetic Simulator presentation QA.
    ///
    /// Keeping this factory inside the Capture package prevents the app from constructing an
    /// Experiment One coordinator directly. It exists only in DEBUG Simulator builds and does not
    /// create a CoreBluetooth controller, consume field-build authority, or enable physical capture.
    @MainActor
    static func makeSimulatorQA() throws -> PassiveBluetoothExperimentOneCoordinator {
        try PassiveBluetoothExperimentOneCoordinator()
    }
#endif

    /// Future public/release field-authorized construction seam.
    ///
    /// The caller must possess a `VerifiedAdmission` minted only from the package's cryptographically
    /// verified external field authorization AND the package's final field-execution policy must have
    /// deliberately reached GO. Signed evidence is necessary but not sufficient outside a deliberately
    /// authorized private research build: ordinary builds remain fail-closed while the production
    /// status is NO-GO.
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
    private static func makeResearchFieldCoordinator() throws -> PassiveBluetoothExperimentOneCoordinator {
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
