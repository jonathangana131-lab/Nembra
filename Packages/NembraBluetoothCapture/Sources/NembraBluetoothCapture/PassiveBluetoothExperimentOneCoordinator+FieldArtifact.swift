import Foundation

/// Exact bytes the app should retain and share after Experiment One has been immutably sealed.
/// Raw controller JSON remains available inside `artifact` for analysis/details, but is not the
/// product's final field-share object.
public struct PassiveBluetoothExperimentOneFinalizedFieldArtifact: Equatable, Sendable {
    public let exportJSON: Data
    public let artifact: PassiveBluetoothExperimentOneFieldArtifact

    fileprivate init(
        exportJSON: Data,
        artifact: PassiveBluetoothExperimentOneFieldArtifact
    ) {
        self.exportJSON = exportJSON
        self.artifact = artifact
    }
}

public extension PassiveBluetoothExperimentOneCoordinator {
    /// Seals Experiment One if needed, then composes one package-owned final export envelope.
    ///
    /// `setup` is operator-declared experiment context. It cannot choose target identity, recipe,
    /// build identity, build instance, source revision, executable digest, or correlation evidence.
    /// Those values come only from the coordinator-owned result and the running app's package-owned
    /// runtime build-identity reader.
    ///
    /// If immutable Horizon sealing already succeeded before Share staging/provenance composition,
    /// the retained sealed artifact is reused rather than attempting to finalize Horizon twice.
    @MainActor
    func finalizeFieldArtifact(
        setup: PassiveBluetoothStationaryCaptureSetup
    ) async throws -> PassiveBluetoothExperimentOneFinalizedFieldArtifact {
        let sealedArtifact: FinalizedArtifact
        if let finalizedArtifact {
            sealedArtifact = finalizedArtifact
        } else {
            sealedArtifact = try await finalizeObservationHorizon()
        }

        let runtimeBuildIdentity = try PassiveBluetoothCaptureRuntimeBuildIdentityReader
            .currentApplication()
        let fieldArtifact = try PassiveBluetoothExperimentOneFieldArtifactBuilder.make(
            captureJSON: sealedArtifact.captureJSON,
            powerCycleResult: sealedArtifact.powerCycleResult,
            runtimeBuildIdentity: runtimeBuildIdentity,
            setup: setup
        )
        let exportJSON = try PassiveBluetoothExperimentOneFieldArtifactJSON.encode(fieldArtifact)
        let verifiedArtifact = try PassiveBluetoothExperimentOneFieldArtifactJSON
            .verifyInternalConsistency(exportJSON)

        return PassiveBluetoothExperimentOneFinalizedFieldArtifact(
            exportJSON: exportJSON,
            artifact: verifiedArtifact
        )
    }
}
