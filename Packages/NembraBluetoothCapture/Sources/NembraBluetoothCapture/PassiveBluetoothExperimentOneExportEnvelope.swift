import Foundation

/// Durable package-owned export for one finalized ES80 Experiment One evidence life.
///
/// The envelope binds the exact immutable controller bytes to the verified stationary manifest and
/// the four package-issued OFF1 -> ON1 -> OFF2 -> ON2 catalogs that earned target correlation.
/// It is an evidence container, not physical authentication or field-GO authorization.
public struct PassiveBluetoothExperimentOneExportEnvelope: Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let captureJSON: Data
    public let manifest: PassiveBluetoothStationaryCaptureManifest
    public let powerCycleResult: PassiveBluetoothPowerCycleObservationResult

    fileprivate init(
        schemaVersion: Int,
        captureJSON: Data,
        manifest: PassiveBluetoothStationaryCaptureManifest,
        powerCycleResult: PassiveBluetoothPowerCycleObservationResult
    ) {
        self.schemaVersion = schemaVersion
        self.captureJSON = captureJSON
        self.manifest = manifest
        self.powerCycleResult = powerCycleResult
    }
}

public enum PassiveBluetoothExperimentOneExportEnvelopeError: Error, Equatable, Sendable {
    case unsupportedSchemaVersion(Int)
    case unexpectedEnvelopeField(String)
    case currentManifestRequired(Int)
    case incompletePowerCycleEvidence(windowCount: Int, snapshotCount: Int)
    case powerCycleEvidenceDoesNotReplay
    case powerCycleReceiptDoesNotMatchSnapshot(index: Int)
    case correlationNotUnique
    case selectedPeripheralDoesNotMatchCorrelation(selected: String, correlated: String)
}

public enum PassiveBluetoothExperimentOneExportEnvelopeBuilder {
    /// Creates the current export only from one package-finalized coordinator artifact and one
    /// capture-bound current manifest. The correlation result is replayed from its immutable
    /// snapshots before the selected target is allowed into the export boundary.
    public static func make(
        finalizedArtifact: PassiveBluetoothExperimentOneCoordinator.FinalizedArtifact,
        manifest: PassiveBluetoothStationaryCaptureManifest
    ) throws -> PassiveBluetoothExperimentOneExportEnvelope {
        try makeValidated(
            captureJSON: finalizedArtifact.captureJSON,
            manifest: manifest,
            powerCycleResult: finalizedArtifact.powerCycleResult
        )
    }

    package static func makeValidated(
        captureJSON: Data,
        manifest: PassiveBluetoothStationaryCaptureManifest,
        powerCycleResult: PassiveBluetoothPowerCycleObservationResult
    ) throws -> PassiveBluetoothExperimentOneExportEnvelope {
        guard manifest.schemaVersion == PassiveBluetoothStationaryCaptureManifest.currentSchemaVersion else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.currentManifestRequired(manifest.schemaVersion)
        }

        let manifestJSON = try PassiveBluetoothStationaryCaptureManifestJSON.encode(manifest, prettyPrinted: false)
        let rebound = try PassiveBluetoothStationaryCaptureManifestJSON.verifyCaptureBinding(
            manifestJSON: manifestJSON,
            captureJSON: captureJSON
        )
        guard rebound == manifest else {
            throw PassiveBluetoothStationaryCaptureManifestError.manifestDoesNotMatchCapture
        }

        try validatePowerCycleEvidence(powerCycleResult, selectedPeripheralIdentifier: manifest.sourceArtifact.selectedPeripheralIdentifier)

        return .init(
            schemaVersion: PassiveBluetoothExperimentOneExportEnvelope.currentSchemaVersion,
            captureJSON: captureJSON,
            manifest: manifest,
            powerCycleResult: powerCycleResult
        )
    }

    fileprivate static func validatePowerCycleEvidence(
        _ result: PassiveBluetoothPowerCycleObservationResult,
        selectedPeripheralIdentifier: String
    ) throws {
        guard result.windows.count == 4, result.observationSnapshots.count == 4 else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.incompletePowerCycleEvidence(
                windowCount: result.windows.count,
                snapshotCount: result.observationSnapshots.count
            )
        }

        for index in 0..<4 {
            let receipt = result.windows[index]
            let snapshot = result.observationSnapshots[index]
            guard receipt.phase.rawValue == index,
                  receipt.windowSequence == snapshot.windowSequence,
                  receipt.observedCandidateCount == snapshot.candidates.count,
                  receipt.endedAtUptimeNanoseconds >= receipt.startedAtUptimeNanoseconds else {
                throw PassiveBluetoothExperimentOneExportEnvelopeError
                    .powerCycleReceiptDoesNotMatchSnapshot(index: index)
            }
        }

        let replayed = PassiveBluetoothPowerCycleTargetCorrelation.assess(
            firstOff: result.observationSnapshots[0],
            firstOn: result.observationSnapshots[1],
            secondOff: result.observationSnapshots[2],
            secondOn: result.observationSnapshots[3]
        )
        guard replayed == result.correlation else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.powerCycleEvidenceDoesNotReplay
        }

        guard case let .singleRepeatableCandidate(correlatedIdentifier) = replayed.disposition else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.correlationNotUnique
        }
        let selected = selectedPeripheralIdentifier.uppercased()
        let correlated = correlatedIdentifier.uuidString
        guard selected == correlated else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.selectedPeripheralDoesNotMatchCorrelation(
                selected: selectedPeripheralIdentifier,
                correlated: correlated
            )
        }
    }
}

public enum PassiveBluetoothExperimentOneExportEnvelopeJSON {
    private struct CandidateWire: Codable {
        let id: UUID
        let isConnectable: Bool?
    }

    private struct SnapshotWire: Codable {
        let observationSeriesIdentity: UUID
        let windowSequence: UInt64
        let candidates: [CandidateWire]
    }

    private struct WindowWire: Codable {
        let phaseRawValue: Int
        let windowSequence: UInt64
        let startedAtUptimeNanoseconds: UInt64
        let endedAtUptimeNanoseconds: UInt64
        let observedCandidateCount: Int
    }

    private struct WireV1: Codable {
        let schemaVersion: Int
        let captureJSON: Data
        let manifestJSON: Data
        let windows: [WindowWire]
        let observationSnapshots: [SnapshotWire]
    }

    private struct VersionProbe: Decodable {
        let schemaVersion: Int
    }

    public static func encode(
        _ envelope: PassiveBluetoothExperimentOneExportEnvelope,
        prettyPrinted: Bool = true
    ) throws -> Data {
        guard envelope.schemaVersion == PassiveBluetoothExperimentOneExportEnvelope.currentSchemaVersion else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.unsupportedSchemaVersion(envelope.schemaVersion)
        }

        let manifestJSON = try PassiveBluetoothStationaryCaptureManifestJSON.encode(
            envelope.manifest,
            prettyPrinted: false
        )
        let wire = WireV1(
            schemaVersion: envelope.schemaVersion,
            captureJSON: envelope.captureJSON,
            manifestJSON: manifestJSON,
            windows: envelope.powerCycleResult.windows.map {
                .init(
                    phaseRawValue: $0.phase.rawValue,
                    windowSequence: $0.windowSequence.rawValue,
                    startedAtUptimeNanoseconds: $0.startedAtUptimeNanoseconds,
                    endedAtUptimeNanoseconds: $0.endedAtUptimeNanoseconds,
                    observedCandidateCount: $0.observedCandidateCount
                )
            },
            observationSnapshots: envelope.powerCycleResult.observationSnapshots.map { snapshot in
                .init(
                    observationSeriesIdentity: snapshot.observationSeriesIdentity.rawValue,
                    windowSequence: snapshot.windowSequence.rawValue,
                    candidates: snapshot.candidates.map { .init(id: $0.id, isConnectable: $0.isConnectable) }
                )
            }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = prettyPrinted ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return try encoder.encode(wire)
    }

    public static func decodeAndVerify(_ data: Data) throws -> PassiveBluetoothExperimentOneExportEnvelope {
        try validateSchemaShape(data)

        let decoder = JSONDecoder()
        let version = try decoder.decode(VersionProbe.self, from: data).schemaVersion
        guard version == PassiveBluetoothExperimentOneExportEnvelope.currentSchemaVersion else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.unsupportedSchemaVersion(version)
        }
        let wire = try decoder.decode(WireV1.self, from: data)

        let manifest = try PassiveBluetoothStationaryCaptureManifestJSON.verifyCaptureBinding(
            manifestJSON: wire.manifestJSON,
            captureJSON: wire.captureJSON
        )
        let result = try rebuildPowerCycleResult(windows: wire.windows, snapshots: wire.observationSnapshots)
        return try PassiveBluetoothExperimentOneExportEnvelopeBuilder.makeValidated(
            captureJSON: wire.captureJSON,
            manifest: manifest,
            powerCycleResult: result
        )
    }

    private static func rebuildPowerCycleResult(
        windows: [WindowWire],
        snapshots: [SnapshotWire]
    ) throws -> PassiveBluetoothPowerCycleObservationResult {
        guard windows.count == 4, snapshots.count == 4 else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.incompletePowerCycleEvidence(
                windowCount: windows.count,
                snapshotCount: snapshots.count
            )
        }

        let rebuiltSnapshots = try snapshots.map { wire in
            try PassiveBluetoothCandidateObservationSnapshot(
                observationSeriesIdentity: .init(rawValue: wire.observationSeriesIdentity),
                windowSequence: .init(rawValue: wire.windowSequence),
                candidates: wire.candidates.map { .init(id: $0.id, isConnectable: $0.isConnectable) }
            )
        }
        let rebuiltWindows = try windows.map { wire -> PassiveBluetoothPowerCycleObservationWindowReceipt in
            guard let phase = PassiveBluetoothPowerCycleObservationPhase(rawValue: wire.phaseRawValue) else {
                throw PassiveBluetoothExperimentOneExportEnvelopeError.powerCycleEvidenceDoesNotReplay
            }
            return .init(
                phase: phase,
                windowSequence: .init(rawValue: wire.windowSequence),
                startedAtUptimeNanoseconds: wire.startedAtUptimeNanoseconds,
                endedAtUptimeNanoseconds: wire.endedAtUptimeNanoseconds,
                observedCandidateCount: wire.observedCandidateCount
            )
        }
        let correlation = PassiveBluetoothPowerCycleTargetCorrelation.assess(
            firstOff: rebuiltSnapshots[0],
            firstOn: rebuiltSnapshots[1],
            secondOff: rebuiltSnapshots[2],
            secondOn: rebuiltSnapshots[3]
        )
        return .init(
            windows: rebuiltWindows,
            observationSnapshots: rebuiltSnapshots,
            correlation: correlation
        )
    }

    private static func validateSchemaShape(_ data: Data) throws {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        let allowed: Set<String> = [
            "schemaVersion", "captureJSON", "manifestJSON", "windows", "observationSnapshots",
        ]
        for key in root.keys.sorted() where !allowed.contains(key) {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.unexpectedEnvelopeField(key)
        }
    }
}
