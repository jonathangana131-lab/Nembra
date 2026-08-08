import Foundation

public enum PassiveBluetoothExperimentOneExportEnvelopeError: Error, Equatable, Sendable {
    case unsupportedSchemaVersion(Int)
    case invalidPowerCycleEvidence
    case correlationNotSingleTarget
    case invalidRuntimeExecutableSHA256(String)
    case envelopeDoesNotMatchManifest
}

/// Package-owned final export producer. The public creation path only accepts the coordinator's
/// non-publicly-constructible `FinalizedArtifact`, so app/UI code cannot splice detached target,
/// capture, correlation, or build-provenance values into a product artifact.
public enum PassiveBluetoothExperimentOneExportEnvelopeJSON {
    public static func make(
        finalizedArtifact: PassiveBluetoothExperimentOneCoordinator.FinalizedArtifact,
        setup: PassiveBluetoothStationaryCaptureSetup,
        prettyPrinted: Bool = true
    ) throws -> Data {
        try make(
            captureJSON: finalizedArtifact.captureJSON,
            powerCycleResult: finalizedArtifact.powerCycleResult,
            setup: setup,
            runtimeIdentity: PassiveBluetoothCaptureRuntimeBuildIdentity.currentApplication(),
            experimentID: UUID(),
            preparedAt: Date(),
            prettyPrinted: prettyPrinted
        )
    }

    /// Verifies every binding recoverable from the portable software artifact. This does not make
    /// the JSON a signed attestation and does not replace the external accepted-build/field GO gate.
    public static func verify(_ data: Data) throws -> PassiveBluetoothExperimentOneExportEnvelope {
        let envelope = try JSONDecoder().decode(PassiveBluetoothExperimentOneExportEnvelope.self, from: data)
        guard envelope.schemaVersion == PassiveBluetoothExperimentOneExportEnvelope.currentSchemaVersion else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError
                .unsupportedSchemaVersion(envelope.schemaVersion)
        }
        guard envelope.experimentRecipeID == .es80FingerprintV1 else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.envelopeDoesNotMatchManifest
        }
        guard isCanonicalSHA256(envelope.runtimeExecutableSHA256) else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError
                .invalidRuntimeExecutableSHA256(envelope.runtimeExecutableSHA256)
        }

        let manifest = try PassiveBluetoothStationaryCaptureManifestJSON.verifyCaptureBinding(
            manifestJSON: envelope.stationaryManifestJSON,
            captureJSON: envelope.captureJSON
        )
        guard manifest.schemaVersion == PassiveBluetoothStationaryCaptureManifest.currentSchemaVersion,
              manifest.experimentRecipeID == envelope.experimentRecipeID,
              manifest.nembraBuildIdentifier == envelope.nembraBuildIdentifier,
              manifest.nembraBuildInstanceID == envelope.nembraBuildInstanceID,
              manifest.nembraBuildCommitSHA == envelope.nembraBuildCommitSHA,
              manifest.sourceArtifact.selectedPeripheralIdentifier
                == envelope.correlatedPeripheralIdentifier.uuidString else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.envelopeDoesNotMatchManifest
        }

        let result = try domainResult(from: envelope.powerCycleEvidence)
        let correlated = try validatedCorrelatedPeripheral(in: result)
        guard correlated == envelope.correlatedPeripheralIdentifier else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.invalidPowerCycleEvidence
        }
        return envelope
    }

    /// Deterministic package-test seam. Production clients cannot call this overload across the
    /// package boundary and therefore cannot mint final exports from independently supplied pieces.
    static func make(
        captureJSON: Data,
        powerCycleResult: PassiveBluetoothPowerCycleObservationResult,
        setup: PassiveBluetoothStationaryCaptureSetup,
        runtimeIdentity: PassiveBluetoothCaptureRuntimeBuildIdentity,
        experimentID: UUID,
        preparedAt: Date,
        prettyPrinted: Bool
    ) throws -> Data {
        let correlated = try validatedCorrelatedPeripheral(in: powerCycleResult)
        guard isCanonicalSHA256(runtimeIdentity.executableSHA256) else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError
                .invalidRuntimeExecutableSHA256(runtimeIdentity.executableSHA256)
        }

        let manifest = try PassiveBluetoothStationaryCaptureManifestBuilder.make(
            captureJSON: captureJSON,
            experimentID: experimentID,
            experimentRecipe: .es80FingerprintV1,
            preparedAt: preparedAt,
            nembraBuildIdentifier: runtimeIdentity.buildIdentifier,
            nembraBuildInstanceID: runtimeIdentity.buildInstanceID,
            nembraBuildCommitSHA: runtimeIdentity.sourceCommitSHA,
            selectedPeripheralIdentifier: correlated.uuidString,
            setup: setup
        )
        let manifestJSON = try PassiveBluetoothStationaryCaptureManifestJSON.encode(
            manifest,
            prettyPrinted: false
        )
        let envelope = PassiveBluetoothExperimentOneExportEnvelope(
            correlatedPeripheralIdentifier: correlated,
            runtimeIdentity: runtimeIdentity,
            captureJSON: captureJSON,
            stationaryManifestJSON: manifestJSON,
            powerCycleEvidence: .init(powerCycleResult)
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = prettyPrinted ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return try encoder.encode(envelope)
    }

    static func validatedCorrelatedPeripheral(
        in result: PassiveBluetoothPowerCycleObservationResult
    ) throws -> UUID {
        guard result.windows.count == 4, result.observationSnapshots.count == 4 else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.invalidPowerCycleEvidence
        }

        for index in 0..<4 {
            let receipt = result.windows[index]
            let snapshot = result.observationSnapshots[index]
            guard receipt.phase.rawValue == index,
                  receipt.windowSequence == snapshot.windowSequence,
                  receipt.observedCandidateCount == snapshot.candidates.count,
                  receipt.startedAtUptimeNanoseconds <= receipt.endedAtUptimeNanoseconds else {
                throw PassiveBluetoothExperimentOneExportEnvelopeError.invalidPowerCycleEvidence
            }
        }

        let replay = PassiveBluetoothPowerCycleTargetCorrelation.assess(
            firstOff: result.observationSnapshots[0],
            firstOn: result.observationSnapshots[1],
            secondOff: result.observationSnapshots[2],
            secondOn: result.observationSnapshots[3]
        )
        guard replay == result.correlation else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.invalidPowerCycleEvidence
        }
        guard case let .singleRepeatableCandidate(identifier) = replay.disposition else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.correlationNotSingleTarget
        }
        return identifier
    }

    private static func domainResult(
        from evidence: PassiveBluetoothExperimentOneExportEnvelope.PowerCycleEvidence
    ) throws -> PassiveBluetoothPowerCycleObservationResult {
        guard evidence.windows.count == 4, evidence.observationSnapshots.count == 4 else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.invalidPowerCycleEvidence
        }

        let snapshots = try evidence.observationSnapshots.map { snapshot in
            try PassiveBluetoothCandidateObservationSnapshot(
                observationSeriesIdentity: .init(rawValue: snapshot.observationSeriesIdentity),
                windowSequence: .init(rawValue: snapshot.windowSequence),
                candidates: snapshot.candidates.map {
                    .init(id: $0.id, isConnectable: $0.isConnectable)
                }
            )
        }
        let windows = try evidence.windows.map { window in
            guard let phase = PassiveBluetoothPowerCycleObservationPhase(rawValue: window.phaseRawValue) else {
                throw PassiveBluetoothExperimentOneExportEnvelopeError.invalidPowerCycleEvidence
            }
            return PassiveBluetoothPowerCycleObservationWindowReceipt(
                phase: phase,
                windowSequence: .init(rawValue: window.windowSequence),
                startedAtUptimeNanoseconds: window.startedAtUptimeNanoseconds,
                endedAtUptimeNanoseconds: window.endedAtUptimeNanoseconds,
                observedCandidateCount: window.observedCandidateCount
            )
        }

        let replay = PassiveBluetoothPowerCycleTargetCorrelation.assess(
            firstOff: snapshots[0],
            firstOn: snapshots[1],
            secondOff: snapshots[2],
            secondOn: snapshots[3]
        )
        guard PassiveBluetoothExperimentOneExportEnvelope.PowerCycleEvidence.Correlation(replay)
                == evidence.correlation else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.invalidPowerCycleEvidence
        }

        let result = PassiveBluetoothPowerCycleObservationResult(
            windows: windows,
            observationSnapshots: snapshots,
            correlation: replay
        )
        _ = try validatedCorrelatedPeripheral(in: result)
        return result
    }

    private static func isCanonicalSHA256(_ value: String) -> Bool {
        guard value.utf8.count == 64 else { return false }
        return value.utf8.allSatisfy { byte in
            (48...57).contains(byte) || (97...102).contains(byte)
        }
    }
}
