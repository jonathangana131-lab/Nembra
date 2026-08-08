import Foundation

/// Canonical production bridge from the running Nembra binary to schema-v2 stationary capture
/// provenance.
///
/// The existing manifest fields remain declarations: this bridge does not turn an embedded Git SHA
/// into cryptographic source-to-binary attestation. Its purpose is narrower and mechanical: field
/// app code no longer needs to accept, type, or invent a build label/commit pair when producing the
/// manifest. Both values must come from `PassiveBluetoothCaptureRuntimeBuildIdentityReader`, whose
/// public production path reads `Bundle.main` and hashes the executable bytes actually running.
public extension PassiveBluetoothStationaryCaptureManifestBuilder {
    /// Creates the current stationary manifest using build identity from the application that is
    /// actually running.
    ///
    /// This is the canonical field-app entry point. Missing/malformed embedded build metadata or an
    /// unreadable executable fails before a manifest is produced. The runtime executable digest is
    /// intentionally not written into schema v2 because that schema currently has no such field;
    /// trusted source-to-binary acceptance remains a separate preflight requirement rather than an
    /// invented manifest claim.
    static func makeUsingCurrentApplicationBuild(
        captureJSON: Data,
        experimentID: UUID = UUID(),
        experimentRecipe: PassiveBluetoothExperimentRecipe,
        preparedAt: Date = Date(),
        selectedPeripheralIdentifier: String,
        setup: PassiveBluetoothStationaryCaptureSetup
    ) throws -> PassiveBluetoothStationaryCaptureManifest {
        let runtimeBuildIdentity = try PassiveBluetoothCaptureRuntimeBuildIdentityReader.currentApplication()
        return try makeUsingRuntimeBuildIdentity(
            captureJSON: captureJSON,
            experimentID: experimentID,
            experimentRecipe: experimentRecipe,
            preparedAt: preparedAt,
            runtimeBuildIdentity: runtimeBuildIdentity,
            selectedPeripheralIdentifier: selectedPeripheralIdentifier,
            setup: setup
        )
    }

    /// Deterministic package seam used by tests and package-owned composition.
    ///
    /// `PassiveBluetoothCaptureRuntimeBuildIdentity` cannot be publicly constructed from arbitrary
    /// strings or bytes, so this overload preserves the reader's producer boundary while allowing
    /// the bridge itself to be tested without depending on a test host bundle.
    package static func makeUsingRuntimeBuildIdentity(
        captureJSON: Data,
        experimentID: UUID = UUID(),
        experimentRecipe: PassiveBluetoothExperimentRecipe,
        preparedAt: Date = Date(),
        runtimeBuildIdentity: PassiveBluetoothCaptureRuntimeBuildIdentity,
        selectedPeripheralIdentifier: String,
        setup: PassiveBluetoothStationaryCaptureSetup
    ) throws -> PassiveBluetoothStationaryCaptureManifest {
        try make(
            captureJSON: captureJSON,
            experimentID: experimentID,
            experimentRecipe: experimentRecipe,
            preparedAt: preparedAt,
            nembraBuildIdentifier: runtimeBuildIdentity.buildIdentifier,
            nembraBuildCommitSHA: runtimeBuildIdentity.sourceCommitSHA,
            selectedPeripheralIdentifier: selectedPeripheralIdentifier,
            setup: setup
        )
    }
}
