import Foundation
import NembraCore

/// One package-owned, self-consistent export object for ES80 Experiment One.
///
/// This binds the exact immutable controller JSON bytes to the exact four-window correlation
/// evidence from the same Experiment One run, the stationary manifest, and runtime build
/// provenance. Internal consistency is deliberately narrower than authenticity: a valid envelope
/// is not an externally attested field build, physical scooter authentication, RF completeness, or
/// protocol/telemetry truth.
public struct PassiveBluetoothExperimentOneFieldArtifact: Equatable, Sendable {
    public static let currentSchemaVersion = 1

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

    public let schemaVersion: Int
    public let captureJSON: Data
    public let stationaryManifestJSON: Data
    public let stationaryManifest: PassiveBluetoothStationaryCaptureManifest
    public let powerCycleResult: PassiveBluetoothPowerCycleObservationResult
    public let runtimeBuildProvenance: RuntimeBuildProvenance

    fileprivate init(
        schemaVersion: Int,
        captureJSON: Data,
        stationaryManifestJSON: Data,
        stationaryManifest: PassiveBluetoothStationaryCaptureManifest,
        powerCycleResult: PassiveBluetoothPowerCycleObservationResult,
        runtimeBuildProvenance: RuntimeBuildProvenance
    ) {
        self.schemaVersion = schemaVersion
        self.captureJSON = captureJSON
        self.stationaryManifestJSON = stationaryManifestJSON
        self.stationaryManifest = stationaryManifest
        self.powerCycleResult = powerCycleResult
        self.runtimeBuildProvenance = runtimeBuildProvenance
    }
}

public enum PassiveBluetoothExperimentOneFieldArtifactError: Error, Equatable, Sendable {
    case unsupportedSchemaVersion(Int)
    case invalidJSONShape(String)
    case unexpectedField(String)
    case invalidPowerCycleEvidence
    case correlationNotUnique
    case manifestSchemaMismatch(expected: Int, actual: Int)
    case manifestRecipeMismatch
    case manifestExperimentMismatch
    case manifestTargetMismatch(expected: String, actual: String)
    case runtimeBuildProvenanceMismatch(String)
    case invalidRuntimeExecutableSHA256(String)
}

/// Package-internal producer. App/UI code cannot supply a target UUID, recipe, build label,
/// build-instance ID, source SHA, executable digest, or experiment ID.
enum PassiveBluetoothExperimentOneFieldArtifactBuilder {
    static func make(
        captureJSON: Data,
        powerCycleResult: PassiveBluetoothPowerCycleObservationResult,
        runtimeBuildIdentity: PassiveBluetoothCaptureRuntimeBuildIdentity,
        setup: PassiveBluetoothStationaryCaptureSetup,
        preparedAt: Date = Date()
    ) throws -> PassiveBluetoothExperimentOneFieldArtifact {
        let validatedCorrelation = try PassiveBluetoothExperimentOneFieldArtifactEvidence.validate(
            powerCycleResult
        )
        let experimentID = validatedCorrelation.observationSeriesIdentity.rawValue

        let manifest = try PassiveBluetoothStationaryCaptureManifestBuilder.make(
            captureJSON: captureJSON,
            experimentID: experimentID,
            experimentRecipe: .es80FingerprintV1,
            preparedAt: preparedAt,
            nembraBuildIdentifier: runtimeBuildIdentity.buildIdentifier,
            nembraBuildInstanceID: runtimeBuildIdentity.buildInstanceID,
            nembraBuildCommitSHA: runtimeBuildIdentity.sourceCommitSHA,
            selectedPeripheralIdentifier: validatedCorrelation.targetIdentifier.uuidString,
            setup: setup
        )
        let manifestJSON = try PassiveBluetoothStationaryCaptureManifestJSON.encode(manifest)
        let runtime = PassiveBluetoothExperimentOneFieldArtifact.RuntimeBuildProvenance(
            buildIdentifier: runtimeBuildIdentity.buildIdentifier,
            buildInstanceID: runtimeBuildIdentity.buildInstanceID,
            sourceCommitSHA: runtimeBuildIdentity.sourceCommitSHA,
            executableSHA256: runtimeBuildIdentity.executableSHA256
        )

        return PassiveBluetoothExperimentOneFieldArtifact(
            schemaVersion: PassiveBluetoothExperimentOneFieldArtifact.currentSchemaVersion,
            captureJSON: captureJSON,
            stationaryManifestJSON: manifestJSON,
            stationaryManifest: manifest,
            powerCycleResult: powerCycleResult,
            runtimeBuildProvenance: runtime
        )
    }
}

public enum PassiveBluetoothExperimentOneFieldArtifactJSON {
    private struct Wire: Codable {
        let schemaVersion: Int
        let captureJSON: Data
        let stationaryManifestJSON: Data
        let powerCycle: PowerCycleWire
        let runtimeBuild: RuntimeBuildWire

        init(_ artifact: PassiveBluetoothExperimentOneFieldArtifact) {
            schemaVersion = artifact.schemaVersion
            captureJSON = artifact.captureJSON
            stationaryManifestJSON = artifact.stationaryManifestJSON
            powerCycle = PowerCycleWire(artifact.powerCycleResult)
            runtimeBuild = RuntimeBuildWire(artifact.runtimeBuildProvenance)
        }
    }

    private struct PowerCycleWire: Codable {
        let windows: [WindowWire]
        let observationSnapshots: [SnapshotWire]

        init(_ result: PassiveBluetoothPowerCycleObservationResult) {
            windows = result.windows.map(WindowWire.init)
            observationSnapshots = result.observationSnapshots.map(SnapshotWire.init)
        }

        func result() throws -> PassiveBluetoothPowerCycleObservationResult {
            guard windows.count == 4, observationSnapshots.count == 4 else {
                throw PassiveBluetoothExperimentOneFieldArtifactError.invalidPowerCycleEvidence
            }

            let decodedWindows = try windows.map { try $0.receipt() }
            let decodedSnapshots = try observationSnapshots.map { try $0.snapshot() }
            let correlation = PassiveBluetoothPowerCycleTargetCorrelation.assess(
                firstOff: decodedSnapshots[0],
                firstOn: decodedSnapshots[1],
                secondOff: decodedSnapshots[2],
                secondOn: decodedSnapshots[3]
            )
            return PassiveBluetoothPowerCycleObservationResult(
                windows: decodedWindows,
                observationSnapshots: decodedSnapshots,
                correlation: correlation
            )
        }
    }

    private struct WindowWire: Codable {
        let phase: Int
        let windowSequence: UInt64
        let startedAtUptimeNanoseconds: UInt64
        let endedAtUptimeNanoseconds: UInt64
        let observedCandidateCount: Int

        init(_ receipt: PassiveBluetoothPowerCycleObservationWindowReceipt) {
            phase = receipt.phase.rawValue
            windowSequence = receipt.windowSequence.rawValue
            startedAtUptimeNanoseconds = receipt.startedAtUptimeNanoseconds
            endedAtUptimeNanoseconds = receipt.endedAtUptimeNanoseconds
            observedCandidateCount = receipt.observedCandidateCount
        }

        func receipt() throws -> PassiveBluetoothPowerCycleObservationWindowReceipt {
            guard let decodedPhase = PassiveBluetoothPowerCycleObservationPhase(rawValue: phase) else {
                throw PassiveBluetoothExperimentOneFieldArtifactError.invalidPowerCycleEvidence
            }
            return PassiveBluetoothPowerCycleObservationWindowReceipt(
                phase: decodedPhase,
                windowSequence: PassiveBluetoothCandidateObservationWindowSequence(rawValue: windowSequence),
                startedAtUptimeNanoseconds: startedAtUptimeNanoseconds,
                endedAtUptimeNanoseconds: endedAtUptimeNanoseconds,
                observedCandidateCount: observedCandidateCount
            )
        }
    }

    private struct SnapshotWire: Codable {
        let observationSeriesIdentity: UUID
        let windowSequence: UInt64
        let candidates: [CandidateWire]

        init(_ snapshot: PassiveBluetoothCandidateObservationSnapshot) {
            observationSeriesIdentity = snapshot.observationSeriesIdentity.rawValue
            windowSequence = snapshot.windowSequence.rawValue
            candidates = snapshot.candidates.map(CandidateWire.init)
        }

        func snapshot() throws -> PassiveBluetoothCandidateObservationSnapshot {
            do {
                return try PassiveBluetoothCandidateObservationSnapshot(
                    observationSeriesIdentity: PassiveBluetoothCandidateObservationSeriesIdentity(
                        rawValue: observationSeriesIdentity
                    ),
                    windowSequence: PassiveBluetoothCandidateObservationWindowSequence(
                        rawValue: windowSequence
                    ),
                    candidates: candidates.map { candidate in
                        PassiveBluetoothCandidateObservationSnapshot.Candidate(
                            id: candidate.id,
                            isConnectable: candidate.isConnectable
                        )
                    }
                )
            } catch {
                throw PassiveBluetoothExperimentOneFieldArtifactError.invalidPowerCycleEvidence
            }
        }
    }

    private struct CandidateWire: Codable {
        let id: UUID
        let isConnectable: Bool?

        init(_ candidate: PassiveBluetoothCandidateObservationSnapshot.Candidate) {
            id = candidate.id
            isConnectable = candidate.isConnectable
        }
    }

    private struct RuntimeBuildWire: Codable {
        let buildIdentifier: String
        let buildInstanceID: String
        let sourceCommitSHA: String
        let executableSHA256: String

        init(_ provenance: PassiveBluetoothExperimentOneFieldArtifact.RuntimeBuildProvenance) {
            buildIdentifier = provenance.buildIdentifier
            buildInstanceID = provenance.buildInstanceID
            sourceCommitSHA = provenance.sourceCommitSHA
            executableSHA256 = provenance.executableSHA256
        }

        var provenance: PassiveBluetoothExperimentOneFieldArtifact.RuntimeBuildProvenance {
            .init(
                buildIdentifier: buildIdentifier,
                buildInstanceID: buildInstanceID,
                sourceCommitSHA: sourceCommitSHA,
                executableSHA256: executableSHA256
            )
        }
    }

    public static func encode(
        _ artifact: PassiveBluetoothExperimentOneFieldArtifact,
        prettyPrinted: Bool = true
    ) throws -> Data {
        guard artifact.schemaVersion == PassiveBluetoothExperimentOneFieldArtifact.currentSchemaVersion else {
            throw PassiveBluetoothExperimentOneFieldArtifactError
                .unsupportedSchemaVersion(artifact.schemaVersion)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = prettyPrinted ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return try encoder.encode(Wire(artifact))
    }

    /// Verifies only the envelope's closed-world shape and internal evidence/provenance consistency.
    /// It does not authenticate the producing build or authorize a physical experiment.
    public static func verifyInternalConsistency(
        _ artifactJSON: Data
    ) throws -> PassiveBluetoothExperimentOneFieldArtifact {
        try validateSchemaShape(artifactJSON)

        let wire = try JSONDecoder().decode(Wire.self, from: artifactJSON)
        guard wire.schemaVersion == PassiveBluetoothExperimentOneFieldArtifact.currentSchemaVersion else {
            throw PassiveBluetoothExperimentOneFieldArtifactError
                .unsupportedSchemaVersion(wire.schemaVersion)
        }

        let powerCycleResult = try wire.powerCycle.result()
        let validatedCorrelation = try PassiveBluetoothExperimentOneFieldArtifactEvidence.validate(
            powerCycleResult
        )
        let manifest = try PassiveBluetoothStationaryCaptureManifestJSON.verifyCaptureBinding(
            manifestJSON: wire.stationaryManifestJSON,
            captureJSON: wire.captureJSON
        )

        guard manifest.schemaVersion == PassiveBluetoothStationaryCaptureManifest.currentSchemaVersion else {
            throw PassiveBluetoothExperimentOneFieldArtifactError.manifestSchemaMismatch(
                expected: PassiveBluetoothStationaryCaptureManifest.currentSchemaVersion,
                actual: manifest.schemaVersion
            )
        }
        guard manifest.experimentRecipeID == .es80FingerprintV1 else {
            throw PassiveBluetoothExperimentOneFieldArtifactError.manifestRecipeMismatch
        }
        guard manifest.experimentID == validatedCorrelation.observationSeriesIdentity.rawValue else {
            throw PassiveBluetoothExperimentOneFieldArtifactError.manifestExperimentMismatch
        }

        let expectedTarget = validatedCorrelation.targetIdentifier.uuidString
        let actualTarget = manifest.sourceArtifact.selectedPeripheralIdentifier
        guard actualTarget == expectedTarget else {
            throw PassiveBluetoothExperimentOneFieldArtifactError.manifestTargetMismatch(
                expected: expectedTarget,
                actual: actualTarget
            )
        }

        try validateRuntimeBuild(wire.runtimeBuild, manifest: manifest)

        return PassiveBluetoothExperimentOneFieldArtifact(
            schemaVersion: wire.schemaVersion,
            captureJSON: wire.captureJSON,
            stationaryManifestJSON: wire.stationaryManifestJSON,
            stationaryManifest: manifest,
            powerCycleResult: powerCycleResult,
            runtimeBuildProvenance: wire.runtimeBuild.provenance
        )
    }

    private static func validateRuntimeBuild(
        _ runtime: RuntimeBuildWire,
        manifest: PassiveBluetoothStationaryCaptureManifest
    ) throws {
        guard manifest.nembraBuildIdentifier == runtime.buildIdentifier else {
            throw PassiveBluetoothExperimentOneFieldArtifactError
                .runtimeBuildProvenanceMismatch("buildIdentifier")
        }
        guard manifest.nembraBuildInstanceID == runtime.buildInstanceID else {
            throw PassiveBluetoothExperimentOneFieldArtifactError
                .runtimeBuildProvenanceMismatch("buildInstanceID")
        }
        guard manifest.nembraBuildCommitSHA == runtime.sourceCommitSHA else {
            throw PassiveBluetoothExperimentOneFieldArtifactError
                .runtimeBuildProvenanceMismatch("sourceCommitSHA")
        }

        let digest = runtime.executableSHA256
        guard digest.utf8.count == 64,
              digest == digest.lowercased(),
              digest.utf8.allSatisfy({ byte in
                  (48...57).contains(byte) || (97...102).contains(byte)
              }) else {
            throw PassiveBluetoothExperimentOneFieldArtifactError
                .invalidRuntimeExecutableSHA256(digest)
        }
    }

    private static func validateSchemaShape(_ data: Data) throws {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PassiveBluetoothExperimentOneFieldArtifactError.invalidJSONShape("root")
        }
        try rejectUnexpectedKeys(
            in: root,
            allowed: ["schemaVersion", "captureJSON", "stationaryManifestJSON", "powerCycle", "runtimeBuild"],
            path: ""
        )

        if let powerCycle = root["powerCycle"] as? [String: Any] {
            try rejectUnexpectedKeys(
                in: powerCycle,
                allowed: ["windows", "observationSnapshots"],
                path: "powerCycle"
            )
            if let windows = powerCycle["windows"] as? [[String: Any]] {
                for (index, window) in windows.enumerated() {
                    try rejectUnexpectedKeys(
                        in: window,
                        allowed: [
                            "phase", "windowSequence", "startedAtUptimeNanoseconds",
                            "endedAtUptimeNanoseconds", "observedCandidateCount",
                        ],
                        path: "powerCycle.windows[\(index)]"
                    )
                }
            }
            if let snapshots = powerCycle["observationSnapshots"] as? [[String: Any]] {
                for (index, snapshot) in snapshots.enumerated() {
                    try rejectUnexpectedKeys(
                        in: snapshot,
                        allowed: ["observationSeriesIdentity", "windowSequence", "candidates"],
                        path: "powerCycle.observationSnapshots[\(index)]"
                    )
                    if let candidates = snapshot["candidates"] as? [[String: Any]] {
                        for (candidateIndex, candidate) in candidates.enumerated() {
                            try rejectUnexpectedKeys(
                                in: candidate,
                                allowed: ["id", "isConnectable"],
                                path: "powerCycle.observationSnapshots[\(index)].candidates[\(candidateIndex)]"
                            )
                        }
                    }
                }
            }
        }

        if let runtimeBuild = root["runtimeBuild"] as? [String: Any] {
            try rejectUnexpectedKeys(
                in: runtimeBuild,
                allowed: ["buildIdentifier", "buildInstanceID", "sourceCommitSHA", "executableSHA256"],
                path: "runtimeBuild"
            )
        }
    }

    private static func rejectUnexpectedKeys(
        in object: [String: Any],
        allowed: Set<String>,
        path: String
    ) throws {
        for key in object.keys.sorted() where !allowed.contains(key) {
            let qualified = path.isEmpty ? key : "\(path).\(key)"
            throw PassiveBluetoothExperimentOneFieldArtifactError.unexpectedField(qualified)
        }
    }
}

private enum PassiveBluetoothExperimentOneFieldArtifactEvidence {
    struct ValidatedCorrelation {
        let targetIdentifier: UUID
        let observationSeriesIdentity: PassiveBluetoothCandidateObservationSeriesIdentity
    }

    static func validate(
        _ result: PassiveBluetoothPowerCycleObservationResult
    ) throws -> ValidatedCorrelation {
        guard result.windows.count == 4, result.observationSnapshots.count == 4 else {
            throw PassiveBluetoothExperimentOneFieldArtifactError.invalidPowerCycleEvidence
        }

        let expectedPhases = PassiveBluetoothPowerCycleObservationPhase.allCases
        for index in 0..<4 {
            let window = result.windows[index]
            let snapshot = result.observationSnapshots[index]
            guard window.phase == expectedPhases[index],
                  window.windowSequence == snapshot.windowSequence,
                  window.windowSequence.rawValue > 0,
                  window.endedAtUptimeNanoseconds >= window.startedAtUptimeNanoseconds,
                  window.observedCandidateCount == snapshot.candidates.count else {
                throw PassiveBluetoothExperimentOneFieldArtifactError.invalidPowerCycleEvidence
            }
        }

        let recomputed = PassiveBluetoothPowerCycleTargetCorrelation.assess(
            firstOff: result.observationSnapshots[0],
            firstOn: result.observationSnapshots[1],
            secondOff: result.observationSnapshots[2],
            secondOn: result.observationSnapshots[3]
        )
        guard recomputed == result.correlation else {
            throw PassiveBluetoothExperimentOneFieldArtifactError.invalidPowerCycleEvidence
        }
        guard case let .singleRepeatableCandidate(targetIdentifier) = recomputed.disposition else {
            throw PassiveBluetoothExperimentOneFieldArtifactError.correlationNotUnique
        }
        guard let observationSeriesIdentity = recomputed.observationSeriesIdentities.first,
              recomputed.observationSeriesIdentities.allSatisfy({ $0 == observationSeriesIdentity }) else {
            throw PassiveBluetoothExperimentOneFieldArtifactError.invalidPowerCycleEvidence
        }

        return ValidatedCorrelation(
            targetIdentifier: targetIdentifier,
            observationSeriesIdentity: observationSeriesIdentity
        )
    }
}
