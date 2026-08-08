import CryptoKit
import Foundation

/// Self-contained Experiment One evidence for analysis/share.
///
/// The envelope binds exact sealed capture bytes to the complete four-window correlation evidence,
/// stationary manifest, and runtime-produced build identity. Its hashes detect corruption; they are
/// not signatures, physical authorization, ES80 authentication, or protocol proof.
public struct PassiveBluetoothExperimentOneExportEnvelope: Equatable, Sendable {
    public struct RuntimeBuildProvenance: Equatable, Sendable {
        public let buildIdentifier: String
        public let buildInstanceID: String
        public let sourceCommitSHA: String
        public let executableSHA256: String

        fileprivate init(_ wire: PassiveBluetoothExperimentOneExportEnvelopeJSON.RuntimeBuildWire) {
            buildIdentifier = wire.buildIdentifier
            buildInstanceID = wire.buildInstanceID
            sourceCommitSHA = wire.sourceCommitSHA
            executableSHA256 = wire.executableSHA256
        }
    }

    public struct IntegrityHashes: Equatable, Sendable {
        public let captureSHA256: String
        public let stationaryManifestSHA256: String
        public let powerCycleEvidenceSHA256: String

        fileprivate init(_ wire: PassiveBluetoothExperimentOneExportEnvelopeJSON.HashesWire) {
            captureSHA256 = wire.captureSHA256
            stationaryManifestSHA256 = wire.stationaryManifestSHA256
            powerCycleEvidenceSHA256 = wire.powerCycleEvidenceSHA256
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
        wire: PassiveBluetoothExperimentOneExportEnvelopeJSON.WireV1,
        manifest: PassiveBluetoothStationaryCaptureManifest,
        powerCycleResult: PassiveBluetoothPowerCycleObservationResult
    ) {
        schemaVersion = wire.schemaVersion
        experimentRecipeID = wire.experimentRecipeID
        captureJSON = wire.captureJSON
        stationaryManifestJSON = wire.stationaryManifestJSON
        stationaryManifest = manifest
        powerCycleEvidenceJSON = wire.powerCycleEvidenceJSON
        self.powerCycleResult = powerCycleResult
        runtimeBuildProvenance = .init(wire.runtimeBuildIdentity)
        integrityHashes = .init(wire.hashes)
    }
}

public enum PassiveBluetoothExperimentOneExportEnvelopeError: Error, Equatable, Sendable {
    case unsupportedSchemaVersion(Int)
    case unexpectedField(String)
    case unsupportedExperimentRecipe(PassiveBluetoothExperimentRecipeID)
    case invalidRuntimeBuildProvenance
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
/// Production creation accepts the coordinator's `FinalizedArtifact`, never independently supplied
/// capture/correlation inputs, preserving the same-run authority fence. Runtime build identity also
/// comes from the package-owned runtime reader rather than rider-entered strings.
public enum PassiveBluetoothExperimentOneExportEnvelopeJSON {
    public static let currentSchemaVersion = 1

    fileprivate struct RuntimeBuildWire: Codable, Equatable {
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
    }

    fileprivate struct HashesWire: Codable, Equatable {
        let captureSHA256: String
        let stationaryManifestSHA256: String
        let powerCycleEvidenceSHA256: String
    }

    fileprivate struct WireV1: Codable {
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

    /// Replays every authoritative software binding from the bytes being shared.
    /// Correlation disposition is intentionally not serialized as detached authority.
    public static func decodeAndVerify(
        _ data: Data
    ) throws -> PassiveBluetoothExperimentOneExportEnvelope {
        try validateEnvelopeShape(data)
        let wire = try decoder().decode(WireV1.self, from: data)

        guard wire.schemaVersion == currentSchemaVersion else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.unsupportedSchemaVersion(wire.schemaVersion)
        }
        guard wire.experimentRecipeID == .es80FingerprintV1 else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.unsupportedExperimentRecipe(wire.experimentRecipeID)
        }
        try validateRuntimeBuild(wire.runtimeBuildIdentity)
        try verifyHash(wire.hashes.captureSHA256, data: wire.captureJSON, field: "captureSHA256")
        try verifyHash(
            wire.hashes.stationaryManifestSHA256,
            data: wire.stationaryManifestJSON,
            field: "stationaryManifestSHA256"
        )
        try verifyHash(
            wire.hashes.powerCycleEvidenceSHA256,
            data: wire.powerCycleEvidenceJSON,
            field: "powerCycleEvidenceSHA256"
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
            throw PassiveBluetoothExperimentOneExportEnvelopeError.integrityMismatch(
                field: "manifest.sourceArtifact.sha256"
            )
        }

        return .init(wire: wire, manifest: manifest, powerCycleResult: powerCycleResult)
    }

    private static func encodePowerCycleEvidence(
        _ result: PassiveBluetoothPowerCycleObservationResult
    ) throws -> Data {
        _ = try validatePowerCycleResult(result)
        let wire = PowerCycleEvidenceWire(
            windows: result.windows.map { receipt in
                .init(
                    phase: receipt.phase.rawValue,
                    windowSequence: receipt.windowSequence.rawValue,
                    startedAtUptimeNanoseconds: receipt.startedAtUptimeNanoseconds,
                    endedAtUptimeNanoseconds: receipt.endedAtUptimeNanoseconds,
                    observedCandidateCount: receipt.observedCandidateCount
                )
            },
            snapshots: result.observationSnapshots.map { snapshot in
                .init(
                    observationSeriesIdentity: snapshot.observationSeriesIdentity.rawValue,
                    windowSequence: snapshot.windowSequence.rawValue,
                    candidates: snapshot.candidates.map { .init(id: $0.id, isConnectable: $0.isConnectable) }
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

        let windows = try wire.windows.map { value -> PassiveBluetoothPowerCycleObservationWindowReceipt in
            guard let phase = PassiveBluetoothPowerCycleObservationPhase(rawValue: value.phase) else {
                throw PassiveBluetoothExperimentOneExportEnvelopeError.invalidWindowPhaseOrder
            }
            return PassiveBluetoothPowerCycleObservationWindowReceipt(
                phase: phase,
                windowSequence: PassiveBluetoothCandidateObservationWindowSequence(rawValue: value.windowSequence),
                startedAtUptimeNanoseconds: value.startedAtUptimeNanoseconds,
                endedAtUptimeNanoseconds: value.endedAtUptimeNanoseconds,
                observedCandidateCount: value.observedCandidateCount
            )
        }

        let snapshots = try wire.snapshots.map { value -> PassiveBluetoothCandidateObservationSnapshot in
            try PassiveBluetoothCandidateObservationSnapshot(
                observationSeriesIdentity: PassiveBluetoothCandidateObservationSeriesIdentity(
                    rawValue: value.observationSeriesIdentity
                ),
                windowSequence: PassiveBluetoothCandidateObservationWindowSequence(rawValue: value.windowSequence),
                candidates: value.candidates.map {
                    PassiveBluetoothCandidateObservationSnapshot.Candidate(
                        id: $0.id,
                        isConnectable: $0.isConnectable
                    )
                }
            )
        }

        guard snapshots.count == 4 else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.invalidSnapshotCount(snapshots.count)
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
            throw PassiveBluetoothExperimentOneExportEnvelopeError.invalidWindowCount(result.windows.count)
        }
        guard result.observationSnapshots.count == 4 else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.invalidSnapshotCount(
                result.observationSnapshots.count
            )
        }
        let expected: [PassiveBluetoothPowerCycleObservationPhase] = [
            .firstPoweredOff, .firstPoweredOn, .secondPoweredOff, .secondPoweredOn,
        ]
        guard result.windows.map(\.phase) == expected else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.invalidWindowPhaseOrder
        }

        for index in 0..<4 {
            let receipt = result.windows[index]
            let snapshot = result.observationSnapshots[index]
            guard receipt.windowSequence == snapshot.windowSequence else {
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

    private static func validateRuntimeBuild(_ value: RuntimeBuildWire) throws {
        let trimmed = value.buildIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasControl = value.buildIdentifier.unicodeScalars.contains {
            CharacterSet.controlCharacters.contains($0)
        }
        guard !value.buildIdentifier.isEmpty,
              value.buildIdentifier.utf8.count <= 128,
              value.buildIdentifier == trimmed,
              !hasControl,
              PassiveBluetoothCaptureRuntimeBuildIdentityReader.normalizedBuildInstanceID(value.buildInstanceID)
                  == value.buildInstanceID,
              PassiveBluetoothCaptureRuntimeBuildIdentityReader.normalizedFullGitCommitSHA(value.sourceCommitSHA)
                  == value.sourceCommitSHA else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.invalidRuntimeBuildProvenance
        }
        _ = try canonicalSHA256(value.executableSHA256, field: "runtimeBuildIdentity.executableSHA256")
    }

    private static func validateEnvelopeShape(_ data: Data) throws {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        try rejectUnknownKeys(root, allowed: [
            "schemaVersion", "experimentRecipeID", "captureJSON", "stationaryManifestJSON",
            "powerCycleEvidenceJSON", "runtimeBuildIdentity", "hashes",
        ])
        if let runtime = root["runtimeBuildIdentity"] as? [String: Any] {
            try rejectUnknownKeys(runtime, allowed: [
                "buildIdentifier", "buildInstanceID", "sourceCommitSHA", "executableSHA256",
            ])
        }
        if let hashes = root["hashes"] as? [String: Any] {
            try rejectUnknownKeys(hashes, allowed: [
                "captureSHA256", "stationaryManifestSHA256", "powerCycleEvidenceSHA256",
            ])
        }
    }

    private static func validatePowerCycleEvidenceShape(_ data: Data) throws {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        try rejectUnknownKeys(root, allowed: ["windows", "snapshots"])
        for window in root["windows"] as? [[String: Any]] ?? [] {
            try rejectUnknownKeys(window, allowed: [
                "phase", "windowSequence", "startedAtUptimeNanoseconds",
                "endedAtUptimeNanoseconds", "observedCandidateCount",
            ])
        }
        for snapshot in root["snapshots"] as? [[String: Any]] ?? [] {
            try rejectUnknownKeys(snapshot, allowed: [
                "observationSeriesIdentity", "windowSequence", "candidates",
            ])
            for candidate in snapshot["candidates"] as? [[String: Any]] ?? [] {
                try rejectUnknownKeys(candidate, allowed: ["id", "isConnectable"])
            }
        }
    }

    private static func rejectUnknownKeys(
        _ object: [String: Any],
        allowed: Set<String>
    ) throws {
        if let key = Set(object.keys).subtracting(allowed).sorted().first {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.unexpectedField(key)
        }
    }

    private static func verifyHash(_ expected: String, data: Data, field: String) throws {
        let canonical = try canonicalSHA256(expected, field: field)
        guard canonical == sha256Hex(data) else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.integrityMismatch(field: field)
        }
    }

    private static func canonicalSHA256(_ value: String, field: String) throws -> String {
        guard value.utf8.count == 64,
              value.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.invalidSHA256(field: field)
        }
        return value
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func encoder() -> JSONEncoder {
        let value = JSONEncoder()
        value.outputFormatting = [.sortedKeys]
        return value
    }

    private static func decoder() -> JSONDecoder { JSONDecoder() }
}
