import Foundation

/// Package-owned production boundary for the final Experiment One share artifact.
///
/// App/UI code supplies only the package-finalized Experiment One evidence life plus the explicit
/// stationary setup declaration. The correlated CoreBluetooth target, sealed recipe, and running
/// build provenance are derived inside this package; callers cannot inject a UUID, recipe, build
/// label, build-instance identifier, or source SHA into the production export path.
///
/// This is software evidence composition only. A correlated CoreBluetooth UUID and produced-build
/// rendezvous do not authenticate a physical AOVOPRO ES80 and do not authorize a field run.
public enum PassiveBluetoothExperimentOneFinalExport {
    public static func makeEnvelope(
        finalizedArtifact: PassiveBluetoothExperimentOneCoordinator.FinalizedArtifact,
        setup: PassiveBluetoothStationaryCaptureSetup
    ) throws -> PassiveBluetoothExperimentOneExportEnvelope {
        let buildIdentity = try PassiveBluetoothCaptureRuntimeBuildIdentityReader.currentApplication()
        return try makeValidatedEnvelope(
            captureJSON: finalizedArtifact.captureJSON,
            powerCycleResult: finalizedArtifact.powerCycleResult,
            setup: setup,
            buildIdentity: buildIdentity,
            experimentID: UUID(),
            preparedAt: Date()
        )
    }

    /// Encodes the one package-owned final share object. Raw controller JSON is intentionally not
    /// returned by this API as a final-share product artifact.
    public static func encode(
        finalizedArtifact: PassiveBluetoothExperimentOneCoordinator.FinalizedArtifact,
        setup: PassiveBluetoothStationaryCaptureSetup,
        prettyPrinted: Bool = true
    ) throws -> Data {
        try PassiveBluetoothExperimentOneExportEnvelopeJSON.encode(
            makeEnvelope(finalizedArtifact: finalizedArtifact, setup: setup),
            prettyPrinted: prettyPrinted
        )
    }

    /// Deterministic package test seam. Production app/UI targets cannot call this overload because
    /// it has package access. It preserves the same validation path while allowing tests to use a
    /// package-issued build identity instead of depending on the test runner's Bundle.main.
    package static func makeValidatedEnvelope(
        captureJSON: Data,
        powerCycleResult: PassiveBluetoothPowerCycleObservationResult,
        setup: PassiveBluetoothStationaryCaptureSetup,
        buildIdentity: PassiveBluetoothCaptureRuntimeBuildIdentity,
        experimentID: UUID,
        preparedAt: Date
    ) throws -> PassiveBluetoothExperimentOneExportEnvelope {
        guard case let .singleRepeatableCandidate(correlatedPeripheralIdentifier) =
            powerCycleResult.correlation.disposition
        else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.correlationNotUnique
        }

        let manifest = try PassiveBluetoothStationaryCaptureManifestBuilder.make(
            captureJSON: captureJSON,
            experimentID: experimentID,
            experimentRecipe: .es80FingerprintV1,
            preparedAt: preparedAt,
            nembraBuildIdentifier: buildIdentity.buildIdentifier,
            nembraBuildInstanceID: buildIdentity.buildInstanceID,
            nembraBuildCommitSHA: buildIdentity.sourceCommitSHA,
            selectedPeripheralIdentifier: correlatedPeripheralIdentifier.uuidString,
            setup: setup
        )

        return try PassiveBluetoothExperimentOneExportEnvelopeBuilder.makeValidated(
            captureJSON: captureJSON,
            manifest: manifest,
            powerCycleResult: powerCycleResult
        )
    }
}
