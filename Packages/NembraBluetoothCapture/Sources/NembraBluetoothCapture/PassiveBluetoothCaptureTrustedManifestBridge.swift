import Foundation

/// Canonical schema-v2 stationary-manifest producer for a field build whose running executable has
/// already earned the package's sealed trusted-build binding.
///
/// This bridge intentionally does not accept a build label, Git SHA, executable digest, recipe ID,
/// or procedure version from the caller. Production obtains all of that software provenance through
/// `PassiveBluetoothCaptureBuildPreflight.currentApplication()` and only then projects the subset
/// represented by stationary-manifest schema v2.
public extension PassiveBluetoothStationaryCaptureManifestBuilder {
    /// Produces a stationary manifest from the exact running application only after its executable,
    /// embedded build declaration, recipe, and V14 procedure match the bundled trusted build record.
    ///
    /// Runtime executable hashing, trusted-record I/O, capture decoding, and capture hashing are kept
    /// off the caller's actor so an app-visible preflight/export path does not need to block MainActor
    /// on file I/O or SHA-256 work. The returned manifest is immutable and `Sendable`.
    ///
    /// The resulting schema-v2 manifest still stores only the fields that schema actually owns:
    /// build identifier, source-commit declaration, recipe identity, exact capture-byte binding, and
    /// experiment context. It does not relabel the source commit as cryptographic attestation and it
    /// does not embed the executable digest. The matched build binding / accepted build record remains
    /// separate software provenance that must travel with final field acceptance evidence.
    static func makeUsingTrustedCurrentApplicationBuild(
        captureJSON: Data,
        experimentID: UUID = UUID(),
        preparedAt: Date = Date(),
        selectedPeripheralIdentifier: String,
        setup: PassiveBluetoothStationaryCaptureSetup
    ) async throws -> PassiveBluetoothStationaryCaptureManifest {
        try await Task.detached(priority: .utility) {
            let trustedBuildBinding = try PassiveBluetoothCaptureBuildPreflight.currentApplication()
            return try makeUsingTrustedBuildBinding(
                captureJSON: captureJSON,
                experimentID: experimentID,
                preparedAt: preparedAt,
                trustedBuildBinding: trustedBuildBinding,
                selectedPeripheralIdentifier: selectedPeripheralIdentifier,
                setup: setup
            )
        }.value
    }

    /// Deterministic package composition seam.
    ///
    /// `PassiveBluetoothCaptureRuntimeBuildBinding` has no public initializer. Production callers can
    /// obtain one only from the sealed preflight producer, while package tests can exercise this
    /// projection without depending on a host application's Bundle resources.
    package static func makeUsingTrustedBuildBinding(
        captureJSON: Data,
        experimentID: UUID = UUID(),
        preparedAt: Date = Date(),
        trustedBuildBinding: PassiveBluetoothCaptureRuntimeBuildBinding,
        selectedPeripheralIdentifier: String,
        setup: PassiveBluetoothStationaryCaptureSetup
    ) throws -> PassiveBluetoothStationaryCaptureManifest {
        // The binding producer already enforces the one accepted V14 recipe. Requiring it again here
        // makes the projection contract explicit and avoids caller-selected recipe drift.
        guard trustedBuildBinding.experimentRecipeID == .es80FingerprintV1 else {
            throw PassiveBluetoothStationaryCaptureManifestError.unsupportedExperimentRecipe(
                trustedBuildBinding.experimentRecipeID
            )
        }

        return try make(
            captureJSON: captureJSON,
            experimentID: experimentID,
            experimentRecipe: .es80FingerprintV1,
            preparedAt: preparedAt,
            nembraBuildIdentifier: trustedBuildBinding.buildIdentifier,
            nembraBuildCommitSHA: trustedBuildBinding.sourceCommitSHA,
            selectedPeripheralIdentifier: selectedPeripheralIdentifier,
            setup: setup
        )
    }
}
