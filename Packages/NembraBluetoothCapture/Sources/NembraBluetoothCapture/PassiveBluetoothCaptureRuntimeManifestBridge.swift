import Foundation

/// Canonical production bridge from one independently matched Nembra field build to schema-v2
/// stationary capture provenance.
///
/// The manifest's build fields remain provenance declarations, not physical ES80 evidence or a
/// cryptographic source-to-binary attestation. The stronger invariant here is mechanical: the
/// canonical field-app path cannot source those declarations from embedded metadata alone. It must
/// first obtain `PassiveBluetoothCaptureRuntimeBuildBinding`, which binds the running executable
/// bytes, build label, source declaration, recipe, and procedure to the trusted build-pipeline
/// record accepted by `PassiveBluetoothCaptureBuildPreflight`.
public extension PassiveBluetoothStationaryCaptureManifestBuilder {
    /// Creates the current stationary manifest only after the running application passes the sealed
    /// trusted-build preflight.
    ///
    /// Missing/malformed runtime metadata, a missing/malformed trusted record, or any exact
    /// label/source/executable mismatch fails before a manifest is produced. The executable digest
    /// and procedure version remain authority of the trusted preflight rather than being invented as
    /// new schema-v2 manifest fields.
    static func makeUsingCurrentApplicationBuild(
        captureJSON: Data,
        experimentID: UUID = UUID(),
        experimentRecipe: PassiveBluetoothExperimentRecipe,
        preparedAt: Date = Date(),
        selectedPeripheralIdentifier: String,
        setup: PassiveBluetoothStationaryCaptureSetup
    ) throws -> PassiveBluetoothStationaryCaptureManifest {
        let runtimeBuildBinding = try PassiveBluetoothCaptureBuildPreflight.currentApplication()
        return try makeUsingRuntimeBuildBinding(
            captureJSON: captureJSON,
            experimentID: experimentID,
            experimentRecipe: experimentRecipe,
            preparedAt: preparedAt,
            runtimeBuildBinding: runtimeBuildBinding,
            selectedPeripheralIdentifier: selectedPeripheralIdentifier,
            setup: setup
        )
    }

    /// Deterministic package seam used by tests and package-owned composition.
    ///
    /// `PassiveBluetoothCaptureRuntimeBuildBinding` cannot be publicly constructed from arbitrary
    /// strings, bytes, or a raw embedded runtime identity. Production must pass the sealed
    /// runtime-vs-trusted-record preflight before this type can exist.
    package static func makeUsingRuntimeBuildBinding(
        captureJSON: Data,
        experimentID: UUID = UUID(),
        experimentRecipe: PassiveBluetoothExperimentRecipe,
        preparedAt: Date = Date(),
        runtimeBuildBinding: PassiveBluetoothCaptureRuntimeBuildBinding,
        selectedPeripheralIdentifier: String,
        setup: PassiveBluetoothStationaryCaptureSetup
    ) throws -> PassiveBluetoothStationaryCaptureManifest {
        guard runtimeBuildBinding.experimentRecipeID == experimentRecipe.id else {
            throw PassiveBluetoothStationaryCaptureManifestError
                .unsupportedExperimentRecipe(experimentRecipe.id)
        }

        return try make(
            captureJSON: captureJSON,
            experimentID: experimentID,
            experimentRecipe: experimentRecipe,
            preparedAt: preparedAt,
            nembraBuildIdentifier: runtimeBuildBinding.buildIdentifier,
            nembraBuildCommitSHA: runtimeBuildBinding.sourceCommitSHA,
            selectedPeripheralIdentifier: selectedPeripheralIdentifier,
            setup: setup
        )
    }
}
