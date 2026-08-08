import CryptoKit
import Foundation

/// Shareable, self-contained Experiment One evidence produced from the package-owned finalized
/// coordinator artifact.
///
/// This envelope binds the exact immutable capture bytes to the complete four-window correlation
/// observations, the stationary manifest, and the runtime-produced build identity. The hashes are
/// integrity checks, not signatures or authorization. In particular, this type does not authorize a
/// physical experiment and does not upgrade correlated Bluetooth identity into verified ES80 identity
/// or protocol meaning.
public struct PassiveBluetoothExperimentOneExportEnvelope: Equatable, Sendable {
    public struct RuntimeBuildProvenance: Equatable, Sendable {
        public let buildIdentifier: String
        public let buildInstanceID: String
        public let sourceCommitSHA: String
        public let executableSHA256: String

        fileprivate init(
            buildIdentifier: String,
            buildInstanceID: String,
            sourceCommitSHA: String,
            executableSHA256: String
        ) {
            self.buildIdentifier = buildIdentifier
            self.buildInstanceID = buildInstanceID
            self.sourceCommitSHA = sourceCommitSHA
            self.executableSHA256 = executableSHA256
        }
    }

    public struct IntegrityHashes: Equatable, Sendable {
        public let captureSHA256: String
        public let stationaryManifestSHA256: String
        public let powerCycleEvidenceSHA256: String

        fileprivate init(
            captureSHA256: String,
            stationaryManifestSHA256: String,
            powerCycleEvidenceSHA256: String
        ) {
            self.captureSHA256 = captureSHA256
            self.stationaryManifestSHA256 = stationaryManifestSHA256
            self.powerCycleEvidenceSHA256 = powerCycleEvidenceSHA256
        }
    }

    public let schemaVersion: Int
    public let experimentRecipeID: PassiveBluetoothExperimentRecipeID
    public let captureJSON: Data
    public let stationaryManifestJSON: Data
    public let stationaryManifest: PassiveBluetoothStationaryCaptureManifest
    public let powerCycleEvidenceJSON: Data
    public let powerCycleResult: PassiveBluetoothPowerCycleObservationResult
    public let runtimeBuildProvenance: RuntimeBuildProvenance
    public let integrityHashes: IntegrityHashes

    fileprivate init(
        schemaVersion: Int,
        experimentRecipeID: PassiveBluetoothExperimentRecipeID,
        captureJSON: Data,
        stationaryManifestJSON: Data,
        stationaryManifest: PassiveBluetoothStationaryCaptureManifest,
        powerCycleEvidenceJSON: Data,
        powerCycleResult: PassiveBluetoothPowerCycleObservationResult,
        runtimeBuildProvenance: RuntimeBuildProvenance,
        integrityHashes: IntegrityHashes
    ) {
        self.schemaVersion = schemaVersion
        self.experimentRecipeID = experimentRecipeID
        self.captureJSON = captureJSON
        self.stationaryManifestJSON = stationaryManifestJSON
        self.stationaryManifest = stationaryManifest
        self.powerCycleEvidenceJSON = powerCycleEvidenceJSON
        self.powerCycleResult = powerCycleResult
        self.runtimeBuildProvenance = runtimeBuildProvenance
        self.integrityHashes = integrityHashes
    }
}

public enum PassiveBluetoothExperimentOneExportEnvelopeError: Error, Equatable, Sendable {
    case unsupportedSchemaVersion(Int)
    case unexpectedField(String)
    case unsupportedExperimentRecipe(PassiveBluetoothExperimentRecipeID)
    case invalidWindowCount(Int)
    case invalidSnapshotCount(Int)
    case invalidWindowPhaseOrder
    case invalidWindowSequence
    case invalidWindowTiming
    case candidateCountMismatch
    case correlationReplayMismatch
    case correlationNotUnique
    case invalidSHA256(field: String)
    case integrityMismatch(field: String)
    case manifestRequiresCurrentSchema
    case manifestProvenanceMismatch
    case selectedPeripheralMismatch
}

/// Canonical JSON producer/verifier for the first physical-research share artifact.
///
/// Production creation intentionally accepts a `FinalizedArtifact`, not independently supplied
/// capture/correlation values. That preserves the coordinator's same-run authority fence. Runtime
/// build identity likewise comes from the package-owned runtime reader rather than rider-entered
/// strings.
public enum PassiveBluetoothExperimentOneExportEnvelopeJSON {
    public static let currentSchemaVersion = 1

    private struct RuntimeBuildWire: Codable, Equatable {
        let buildIdentifier: String
        let buildInstanceID: String
        let sourceCommitSHA: String
        let executableSHA256: String

        init(_ identity: PassiveBluetoothCaptureRuntimeBuildIdentity) {
            buildIdentifier = identity.buildIdentifier
            buildInstanceID = identity.buildInstanceID
            sourceCommitSHA = identity.sourceCommitSHA
            executableSHA256 = identity.executableSHA256
        }

        var publicValue: PassiveBluetoothExperimentOneExportEnvelope.RuntimeBuildProvenance {
            .init(
                buildIdentifier: buildIdentifier,
                buildInstanceID: buildInstanceID,
                sourceCommitSHA: sourceCommitSHA,
                executableSHA256: executableSHA256
            )
        }
    }

    private struct HashesWire: Codable, Equatable {
        let captureSHA256: String
        let stationaryManifestSHA256: String
        let powerCycleEvidenceSHA256: String

        var publicValue: PassiveBluetoothExperimentOneExportEnvelope.IntegrityHashes {
            .init(
                captureSHA256: captureSHA256,
                stationaryManifestSHA256: stationaryManifestSHA256,
                powerCycleEvidenceSHA256: powerCycleEvidenceSHA256
            )
        }
    }

    private struct WireV1: Codable {
        let schemaVersion: Int
        let experimentRecipeID: PassiveBluetoothExperimentRecipeID
        let captureJSON: Data
        let stationaryManifestJSON: Data
        let powerCycleEvidenceJSON: Data
        let runtimeBuildIdentity: RuntimeBuildWire
        let hashes: HashesWire
    }

    private struct PowerCycleEvidenceWire: Codable {
        struct Window: Codable {
            let phase: Int
            let windowSequence: UInt64
            let startedAtUptimeNanoseconds: UInt64
            let endedAtUptimeNanoseconds: UInt64
            let observedCandidateCount: Int
        }

        struct Snapshot: Codable {
            struct Candidate: Codable {
                let id: UUID
                let isConnectable: Bool?
            }

            let observationSeriesIdentity: UUID
            let windowSequence: UInt64
            let candidates: [Candidate]
        }

        let windows: [Window]
        let snapshots: [Snapshot]
    }

    /// Produces the share artifact from one immutable coordinator finalization and the exact runtime
    /// build that is executing the app. `setup` is explicit operator-declared provenance; it is not
    /// continuous attestation of those conditions.
    public static func make(
        finalizedArtifact: PassiveBluetoothExperimentOneCoordinator.FinalizedArtifact,
        runtimeBuildIdentity: PassiveBluetoothCaptureRuntimeBuildIdentity,
        preparedAt: Date = Date(),
        setup: PassiveBluetoothStationaryCaptureSetup
    ) throws -> Data {
        let uniqueTarget = try validatePowerCycleResult(finalizedArtifact.powerCycleResult)
        let powerCycleEvidenceJSON = try encodePowerCycleEvidence(finalizedArtifact.powerCycleResult)

        let manifest = try PassiveBluetoothStationaryCaptureManifestBuilder.make(
            captureJSON: finalizedArtifact.captureJSON,
            experimentRecipe: .es80FingerprintV1,
            preparedAt: preparedAt,
            nembraBuildIdentifier: runtimeBuildIdentity.buildIdentifier,
            nembraBuildInstanceID: runtimeBuildIdentity.buildInstanceID,
            nembraBuildCommitSHA: runtimeBuildIdentity.sourceCommitSHA,
            selectedPeripheralIdentifier: uniqueTarget.uuidString,
            setup: setup
        )
        let stationaryManifestJSON = try PassiveBluetoothStationaryCaptureManifestJSON.encode(manifest)

        let wire = WireV1(
            schemaVersion: currentSchemaVersion,
            experimentRecipeID: .es80FingerprintV1,
            captureJSON: finalizedArtifact.captureJSON,
            stationaryManifestJSON: stationaryManifestJSON,
            powerCycleEvidenceJSON: powerCycleEvidenceJSON,
            runtimeBuildIdentity: .init(runtimeBuildIdentity),
            hashes: .init(
                captureSHA256: sha256Hex(finalizedArtifact.captureJSON),
                stationaryManifestSHA256: sha256Hex(stationaryManifestJSON),
                powerCycleEvidenceSHA256: sha256Hex(powerCycleEvidenceJSON)
            )
        )

        return try encoder().encode(wire)
    }

    /// Decodes and re-verifies all bindings from the bytes being shared.
    ///
    /// Correlation disposition is deliberately not serialized as detached authority. It is replayed
    /// from the exact four observation snapshots, then required to remain uniquely correlated to the
    /// same full peripheral identifier bound by the stationary manifest.
    public static func decodeAndVerify(
        _ data: Data
    ) throws -> PassiveBluetoothExperimentOneExportEnvelope {
        try validateEnvelopeShape(data)
        let wire = try decoder().decode(WireV1.self, from: data)

        guard wire.schemaVersion == currentSchemaVersion else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError
                .unsupportedSchemaVersion(wire.schemaVersion)
        }
        guard wire.experimentRecipeID == .es80FingerprintV1 else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError
                .unsupportedExperimentRecipe(wire.experimentRecipeID)
        }

        try verifyHash(
            wire.hashes.captureSHA256,
            actualData: wire.captureJSON,
            field: "captureSHA256"
        )
        try verifyHash(
            wire.hashes.stationaryManifestSHA256,
            actualData: wire.stationaryManifestJSON,
            field: "stationaryManifestSHA256"
        )
        try verifyHash(
            wire.hashes.powerCycleEvidenceSHA256,
            actualData: wire.powerCycleEvidenceJSON,
            field: "powerCycleEvidenceSHA256"
        )
        _ = try canonicalSHA256(
            wire.runtimeBuildIdentity.executableSHA256,
            field: "runtimeBuildIdentity.executableSHA256"
        )

        let powerCycleResult = try decodePowerCycleEvidence(wire.powerCycleEvidenceJSON)
        let uniqueTarget = try validatePowerCycleResult(powerCycleResult)
        let manifest = try PassiveBluetoothStationaryCaptureManifestJSON.verifyCaptureBinding(
            manifestJSON: wire.stationaryManifestJSON,
            captureJSON: wire.captureJSON
        )

        guard manifest.schemaVersion == PassiveBluetoothStationaryCaptureManifest.currentSchemaVersion,
              manifest.experimentRecipeID == wire.experimentRecipeID else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.manifestRequiresCurrentSchema
        }
        guard manifest.nembraBuildIdentifier == wire.runtimeBuildIdentity.buildIdentifier,
              manifest.nembraBuildInstanceID == wire.runtimeBuildIdentity.buildInstanceID,
              manifest.nembraBuildCommitSHA == wire.runtimeBuildIdentity.sourceCommitSHA else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.manifestProvenanceMismatch
        }
        guard manifest.sourceArtifact.selectedPeripheralIdentifier == uniqueTarget.uuidString else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.selectedPeripheralMismatch
        }
        guard manifest.sourceArtifact.sha256 == wire.hashes.captureSHA256 else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError
                .integrityMismatch(field: "manifest.sourceArtifact.sha256")
        }

        return PassiveBluetoothExperimentOneExportEnvelope(
            schemaVersion: wire.schemaVersion,
            experimentRecipeID: wire.experimentRecipeID,
            captureJSON: wire.captureJSON,
            stationaryManifestJSON: wire.stationaryManifestJSON,
            stationaryManifest: manifest,
            powerCycleEvidenceJSON: wire.powerCycleEvidenceJSON,
            powerCycleResult: powerCycleResult,
            runtimeBuildProvenance: wire.runtimeBuildIdentity.publicValue,
            integrityHashes: wire.hashes.publicValue
        )
    }

    private static func encodePowerCycleEvidence(
        _ result: PassiveBluetoothPowerCycleObservationResult
    ) throws -> Data {
        _ = try validatePowerCycleResult(result)
        let wire = PowerCycleEvidenceWire(
            windows: result.windows.map { receipt in
                .init(
                    phase: receipt.phase.rawValue,
                    windowSequence: receipt.windowSequence,
                    startedAtUptimeNanoseconds: receipt.startedAtUptimeNanoseconds,
                    endedAtUptimeNanoseconds: receipt.endedAtUptimeNanoseconds,
                    observedCandidateCount: receipt.observedCandidateCount
                )
            },
            snapshots: result.observationSnapshots.map { snapshot in
                .init(
                    observationSeriesIdentity: snapshot.observationSeriesIdentity.rawValue,
                    windowSequence: snapshot.windowSequence.rawValue,
                    candidates: snapshot.candidates.map { candidate in
                        .init(id: candidate.id, isConnectable: candidate.isConnectable)
                    }
                )
            }
        )
        return try encoder().encode(wire)
    }

    private static func decodePowerCycleEvidence(
        _ data: Data
    ) throws -> PassiveBluetoothPowerCycleObservationResult {
        try validatePowerCycleEvidenceShape(data)
        let wire = try decoder().decode(PowerCycleEvidenceWire.self, from: data)

        let windows: [PassiveBluetoothPowerCycleObservationWindowReceipt] = try wire.windows.map { value in
            guard let phase = PassiveBluetoothPowerCycleObservationPhase(rawValue: value.phase) else {
                throw PassiveBluetoothExperimentOneExportEnvelopeError.invalidWindowPhaseOrder
            }
            return PassiveBluetoothPowerCycleObservationWindowReceipt(
                phase: phase,
                windowSequence: value.windowSequence,
                startedAtUptimeNanoseconds: value.startedAtUptimeNanoseconds,
                endedAtUptimeNanoseconds: value.endedAtUptimeNanoseconds,
                observedCandidateCount: value.observedCandidateCount
            )
        }

        let snapshots: [PassiveBluetoothCandidateObservationSnapshot] = try wire.snapshots.map { value in
            try PassiveBluetoothCandidateObservationSnapshot(
                observationSeriesIdentity: PassiveBluetoothCandidateObservationSeriesIdentity(
                    rawValue: value.observationSeriesIdentity
                ),
                windowSequence: PassiveBluetoothCandidateObservationWindowSequence(
                    rawValue: value.windowSequence
                ),
                candidates: value.candidates.map {
                    PassiveBluetoothCandidateObservationSnapshot.Candidate(
                        id: $0.id,
                        isConnectable: $0.isConnectable
                    )
                }
            )
        }

        guard snapshots.count == 4 else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError
                .invalidSnapshotCount(snapshots.count)
        }
        let replayed = PassiveBluetoothPowerCycleTargetCorrelation.assess(
            firstOff: snapshots[0],
            firstOn: snapshots[1],
            secondOff: snapshots[2],
            secondOn: snapshots[3]
        )
        let result = PassiveBluetoothPowerCycleObservationResult(
            windows: windows,
            observationSnapshots: snapshots,
            correlation: replayed
        )
        _ = try validatePowerCycleResult(result)
        return result
    }

    private static func validatePowerCycleResult(
        _ result: PassiveBluetoothPowerCycleObservationResult
    ) throws -> UUID {
        guard result.windows.count == 4 else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError
                .invalidWindowCount(result.windows.count)
        }
        guard result.observationSnapshots.count == 4 else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError
                .invalidSnapshotCount(result.observationSnapshots.count)
        }

        let expectedPhases: [PassiveBluetoothPowerCycleObservationPhase] = [
            .firstPoweredOff,
            .firstPoweredOn,
            .secondPoweredOff,
            .secondPoweredOn,
        ]
        guard Array(result.windows.map(\.phase)) == expectedPhases else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.invalidWindowPhaseOrder
        }

        for index in 0..<4 {
            let receipt = result.windows[index]
            let snapshot = result.observationSnapshots[index]
            guard receipt.windowSequence == snapshot.windowSequence.rawValue else {
                throw PassiveBluetoothExperimentOneExportEnvelopeError.invalidWindowSequence
            }
            guard receipt.endedAtUptimeNanoseconds >= receipt.startedAtUptimeNanoseconds else {
                throw PassiveBluetoothExperimentOneExportEnvelopeError.invalidWindowTiming
            }
            guard receipt.observedCandidateCount == snapshot.candidates.count else {
                throw PassiveBluetoothExperimentOneExportEnvelopeError.candidateCountMismatch
            }
        }

        let snapshots = result.observationSnapshots
        let replayed = PassiveBluetoothPowerCycleTargetCorrelation.assess(
            firstOff: snapshots[0],
            firstOn: snapshots[1],
            secondOff: snapshots[2],
            secondOn: snapshots[3]
        )
        guard replayed == result.correlation else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.correlationReplayMismatch
        }
        guard case let .singleRepeatableCandidate(identifier) = replayed.disposition else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.correlationNotUnique
        }
        return identifier
    }

    private static func validateEnvelopeShape(_ data: Data) throws {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        try requireExactKeys(
            root,
            allowed: [
                "schemaVersion", "experimentRecipeID", "captureJSON", "stationaryManifestJSON",
                "powerCycleEvidenceJSON", "runtimeBuildIdentity", "hashes",
            ]
        )
        if let runtime = root["runtimeBuildIdentity"] as? [String: Any] {
            try requireExactKeys(
                runtime,
                allowed: ["buildIdentifier", "buildInstanceID", "sourceCommitSHA", "executableSHA256"]
            )
        }
        if let hashes = root["hashes"] as? [String: Any] {
            try requireExactKeys(
                hashes,
                allowed: ["captureSHA256", "stationaryManifestSHA256", "powerCycleEvidenceSHA256"]
            )
        }
    }

    private static func validatePowerCycleEvidenceShape(_ data: Data) throws {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        try requireExactKeys(root, allowed: ["windows", "snapshots"])

        if let windows = root["windows"] as? [[String: Any]] {
            for window in windows {
                try requireExactKeys(
                    window,
                    allowed: [
                        "phase", "windowSequence", "startedAtUptimeNanoseconds",
                        "endedAtUptimeNanoseconds", "observedCandidateCount",
                    ]
                )
            }
        }
        if let snapshots = root["snapshots"] as? [[String: Any]] {
            for snapshot in snapshots {
                try requireExactKeys(
                    snapshot,
                    allowed: ["observationSeriesIdentity", "windowSequence", "candidates"]
                )
                if let candidates = snapshot["candidates"] as? [[String: Any]] {
                    for candidate in candidates {
                        try requireExactKeys(candidate, allowed: ["id", "isConnectable"])
                    }
                }
            }
        }
    }

    private static func requireExactKeys(
        _ object: [String: Any],
        allowed: Set<String>
    ) throws {
        if let unexpected = Set(object.keys).subtracting(allowed).sorted().first {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.unexpectedField(unexpected)
        }
    }

    private static func verifyHash(
        _ expected: String,
        actualData: Data,
        field: String
    ) throws {
        let canonical = try canonicalSHA256(expected, field: field)
        guard canonical == sha256Hex(actualData) else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.integrityMismatch(field: field)
        }
    }

    private static func canonicalSHA256(
        _ value: String,
        field: String
    ) throws -> String {
        guard value.count == 64,
              value.unicodeScalars.allSatisfy({ scalar in
                  switch scalar.value {
                  case 48...57, 97...102:
                      true
                  default:
                      false
                  }
              }) else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.invalidSHA256(field: field)
        }
        return value
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
