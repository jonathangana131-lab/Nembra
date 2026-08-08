import Foundation

/// The portable field artifact for one finalized ES80 Experiment One evidence life.
///
/// This envelope preserves the exact sealed controller JSON bytes, the exact manifest bytes that
/// bind that capture, the package-issued four-window correlation inputs, and the runtime build
/// rendezvous/provenance read from the application that produced the file. It deliberately does
/// not claim physical ES80 authentication, protocol semantics, or field-build authorization.
public struct PassiveBluetoothExperimentOneExportArtifact: Equatable, Sendable {
    public let json: Data
    public let experimentID: UUID
    public let selectedPeripheralIdentifier: String
    public let captureByteCount: Int
    public let nembraBuildIdentifier: String
    public let nembraBuildInstanceID: String
    public let nembraBuildCommitSHA: String
    public let executableSHA256: String

    fileprivate init(
        json: Data,
        experimentID: UUID,
        selectedPeripheralIdentifier: String,
        captureByteCount: Int,
        nembraBuildIdentifier: String,
        nembraBuildInstanceID: String,
        nembraBuildCommitSHA: String,
        executableSHA256: String
    ) {
        self.json = json
        self.experimentID = experimentID
        self.selectedPeripheralIdentifier = selectedPeripheralIdentifier
        self.captureByteCount = captureByteCount
        self.nembraBuildIdentifier = nembraBuildIdentifier
        self.nembraBuildInstanceID = nembraBuildInstanceID
        self.nembraBuildCommitSHA = nembraBuildCommitSHA
        self.executableSHA256 = executableSHA256
    }
}

public enum PassiveBluetoothExperimentOneExportArtifactError: Error, Equatable, Sendable {
    case unsupportedSchemaVersion(Int)
    case unexpectedExportField(String)
    case invalidArtifactKind(String)
    case unsupportedExperimentRecipe(PassiveBluetoothExperimentRecipeID)
    case invalidCorrelationEvidence
    case correlationNotUnique
    case correlationResultMismatch
    case manifestTargetMismatch
    case manifestRecipeMismatch
    case manifestBuildProvenanceMismatch
    case invalidExecutableSHA256(String)
}

/// A verified offline projection of a Nembra Experiment One export.
///
/// Verification proves internal byte/correlation/provenance consistency only. It does not turn the
/// runtime build rendezvous into cryptographic authorization and does not authenticate a physical
/// scooter. The independently accepted external build/GO record remains separate authority.
public struct PassiveBluetoothExperimentOneVerifiedExport: Equatable, Sendable {
    public let experimentID: UUID
    public let captureJSON: Data
    public let manifestJSON: Data
    public let manifest: PassiveBluetoothStationaryCaptureManifest
    public let correlationResult: PassiveBluetoothPowerCycleObservationResult
    public let selectedPeripheralIdentifier: String
    public let nembraBuildIdentifier: String
    public let nembraBuildInstanceID: String
    public let nembraBuildCommitSHA: String
    public let executableSHA256: String

    fileprivate init(
        experimentID: UUID,
        captureJSON: Data,
        manifestJSON: Data,
        manifest: PassiveBluetoothStationaryCaptureManifest,
        correlationResult: PassiveBluetoothPowerCycleObservationResult,
        selectedPeripheralIdentifier: String,
        nembraBuildIdentifier: String,
        nembraBuildInstanceID: String,
        nembraBuildCommitSHA: String,
        executableSHA256: String
    ) {
        self.experimentID = experimentID
        self.captureJSON = captureJSON
        self.manifestJSON = manifestJSON
        self.manifest = manifest
        self.correlationResult = correlationResult
        self.selectedPeripheralIdentifier = selectedPeripheralIdentifier
        self.nembraBuildIdentifier = nembraBuildIdentifier
        self.nembraBuildInstanceID = nembraBuildInstanceID
        self.nembraBuildCommitSHA = nembraBuildCommitSHA
        self.executableSHA256 = executableSHA256
    }
}

public enum PassiveBluetoothExperimentOneExportArtifactJSON {
    private static let schemaVersion = 1
    private static let artifactKind = "nembra-es80-experiment-one"

    private enum PhaseWire: String, Codable {
        case firstPoweredOff
        case firstPoweredOn
        case secondPoweredOff
        case secondPoweredOn

        init(_ phase: PassiveBluetoothPowerCycleObservationPhase) {
            switch phase {
            case .firstPoweredOff: self = .firstPoweredOff
            case .firstPoweredOn: self = .firstPoweredOn
            case .secondPoweredOff: self = .secondPoweredOff
            case .secondPoweredOn: self = .secondPoweredOn
            }
        }

        var phase: PassiveBluetoothPowerCycleObservationPhase {
            switch self {
            case .firstPoweredOff: .firstPoweredOff
            case .firstPoweredOn: .firstPoweredOn
            case .secondPoweredOff: .secondPoweredOff
            case .secondPoweredOn: .secondPoweredOn
            }
        }
    }

    private struct BuildWire: Codable {
        let nembraBuildIdentifier: String
        let nembraBuildInstanceID: String
        let nembraBuildCommitSHA: String
        let executableSHA256: String

        init(_ identity: PassiveBluetoothCaptureRuntimeBuildIdentity) {
            nembraBuildIdentifier = identity.buildIdentifier
            nembraBuildInstanceID = identity.buildInstanceID
            nembraBuildCommitSHA = identity.sourceCommitSHA
            executableSHA256 = identity.executableSHA256
        }
    }

    private struct WindowWire: Codable {
        let phase: PhaseWire
        let windowSequence: UInt64
        let startedAtUptimeNanoseconds: UInt64
        let endedAtUptimeNanoseconds: UInt64
        let observedCandidateCount: Int

        init(_ receipt: PassiveBluetoothPowerCycleObservationWindowReceipt) {
            phase = PhaseWire(receipt.phase)
            windowSequence = receipt.windowSequence.rawValue
            startedAtUptimeNanoseconds = receipt.startedAtUptimeNanoseconds
            endedAtUptimeNanoseconds = receipt.endedAtUptimeNanoseconds
            observedCandidateCount = receipt.observedCandidateCount
        }
    }

    private struct CandidateWire: Codable {
        let peripheralIdentifier: UUID
        let isConnectable: Bool?

        init(_ candidate: PassiveBluetoothCandidateObservationSnapshot.Candidate) {
            peripheralIdentifier = candidate.id
            isConnectable = candidate.isConnectable
        }
    }

    private struct SnapshotWire: Codable {
        let observationSeriesID: UUID
        let windowSequence: UInt64
        let candidates: [CandidateWire]

        init(_ snapshot: PassiveBluetoothCandidateObservationSnapshot) {
            observationSeriesID = snapshot.observationSeriesIdentity.rawValue
            windowSequence = snapshot.windowSequence.rawValue
            candidates = snapshot.candidates.map(CandidateWire.init)
        }
    }

    private struct CorrelationEvidenceWire: Codable {
        let windows: [WindowWire]
        let observationSnapshots: [SnapshotWire]

        init(_ result: PassiveBluetoothPowerCycleObservationResult) {
            windows = result.windows.map(WindowWire.init)
            observationSnapshots = result.observationSnapshots.map(SnapshotWire.init)
        }
    }

    private struct Wire: Codable {
        let schemaVersion: Int
        let artifactKind: String
        let experimentID: UUID
        let experimentRecipeID: PassiveBluetoothExperimentRecipeID
        let captureJSON: Data
        let manifestJSON: Data
        let correlationEvidence: CorrelationEvidenceWire
        let runtimeBuild: BuildWire
    }

    /// Creates the only app-facing final Experiment One export from a package-produced finalized
    /// artifact and the runtime identity of the application that is actually executing.
    ///
    /// App/UI code cannot construct `FinalizedArtifact` or `PassiveBluetoothCaptureRuntimeBuildIdentity`,
    /// cannot supply the correlated target UUID, and cannot substitute a different official recipe.
    public static func make(
        finalizedArtifact: PassiveBluetoothExperimentOneCoordinator.FinalizedArtifact,
        runtimeBuildIdentity: PassiveBluetoothCaptureRuntimeBuildIdentity,
        setup: PassiveBluetoothStationaryCaptureSetup,
        preparedAt: Date = Date()
    ) throws -> PassiveBluetoothExperimentOneExportArtifact {
        try make(
            captureJSON: finalizedArtifact.captureJSON,
            powerCycleResult: finalizedArtifact.powerCycleResult,
            runtimeBuildIdentity: runtimeBuildIdentity,
            setup: setup,
            preparedAt: preparedAt
        )
    }

    /// Package test seam. Production app code must use the authority-composed overload above.
    package static func make(
        captureJSON: Data,
        powerCycleResult: PassiveBluetoothPowerCycleObservationResult,
        runtimeBuildIdentity: PassiveBluetoothCaptureRuntimeBuildIdentity,
        setup: PassiveBluetoothStationaryCaptureSetup,
        preparedAt: Date = Date(),
        experimentID: UUID = UUID()
    ) throws -> PassiveBluetoothExperimentOneExportArtifact {
        let selectedTarget = try validatedCorrelationTarget(from: powerCycleResult)
        let manifest = try PassiveBluetoothStationaryCaptureManifestBuilder.make(
            captureJSON: captureJSON,
            experimentID: experimentID,
            experimentRecipe: .es80FingerprintV1,
            preparedAt: preparedAt,
            nembraBuildIdentifier: runtimeBuildIdentity.buildIdentifier,
            nembraBuildInstanceID: runtimeBuildIdentity.buildInstanceID,
            nembraBuildCommitSHA: runtimeBuildIdentity.sourceCommitSHA,
            selectedPeripheralIdentifier: selectedTarget.uuidString,
            setup: setup
        )
        let manifestJSON = try PassiveBluetoothStationaryCaptureManifestJSON.encode(manifest)
        let executableSHA = try validatedSHA256(runtimeBuildIdentity.executableSHA256)

        let wire = Wire(
            schemaVersion: schemaVersion,
            artifactKind: artifactKind,
            experimentID: experimentID,
            experimentRecipeID: .es80FingerprintV1,
            captureJSON: captureJSON,
            manifestJSON: manifestJSON,
            correlationEvidence: CorrelationEvidenceWire(powerCycleResult),
            runtimeBuild: BuildWire(runtimeBuildIdentity)
        )
        let json = try encode(wire)

        // Verify the bytes that will actually be shared instead of trusting the just-constructed
        // in-memory values. This catches wire drift before a field artifact can leave the app.
        let verified = try verify(json)
        return PassiveBluetoothExperimentOneExportArtifact(
            json: json,
            experimentID: verified.experimentID,
            selectedPeripheralIdentifier: verified.selectedPeripheralIdentifier,
            captureByteCount: verified.captureJSON.count,
            nembraBuildIdentifier: verified.nembraBuildIdentifier,
            nembraBuildInstanceID: verified.nembraBuildInstanceID,
            nembraBuildCommitSHA: verified.nembraBuildCommitSHA,
            executableSHA256: executableSHA
        )
    }

    /// Replays every deterministic integrity relationship carried by the envelope.
    ///
    /// The verifier:
    /// - rejects unknown envelope fields instead of silently accepting future claims;
    /// - reconstitutes the exact four package observation snapshots and recomputes correlation;
    /// - verifies the manifest against the exact embedded capture bytes;
    /// - requires the manifest target to equal the recomputed unique repeated candidate;
    /// - requires recipe and runtime build declarations to agree across both layers.
    public static func verify(_ json: Data) throws -> PassiveBluetoothExperimentOneVerifiedExport {
        try validateSchemaShape(json)

        let decoder = JSONDecoder()
        let wire = try decoder.decode(Wire.self, from: json)
        guard wire.schemaVersion == schemaVersion else {
            throw PassiveBluetoothExperimentOneExportArtifactError
                .unsupportedSchemaVersion(wire.schemaVersion)
        }
        guard wire.artifactKind == artifactKind else {
            throw PassiveBluetoothExperimentOneExportArtifactError
                .invalidArtifactKind(wire.artifactKind)
        }
        guard wire.experimentRecipeID == .es80FingerprintV1 else {
            throw PassiveBluetoothExperimentOneExportArtifactError
                .unsupportedExperimentRecipe(wire.experimentRecipeID)
        }

        let correlation = try reconstructCorrelationEvidence(wire.correlationEvidence)
        let selectedTarget = try validatedCorrelationTarget(from: correlation)
        let manifest = try PassiveBluetoothStationaryCaptureManifestJSON.verifyCaptureBinding(
            manifestJSON: wire.manifestJSON,
            captureJSON: wire.captureJSON
        )

        guard manifest.experimentID == wire.experimentID else {
            throw PassiveBluetoothExperimentOneExportArtifactError.manifestRecipeMismatch
        }
        guard manifest.experimentRecipeID == wire.experimentRecipeID else {
            throw PassiveBluetoothExperimentOneExportArtifactError.manifestRecipeMismatch
        }
        guard manifest.sourceArtifact.selectedPeripheralIdentifier == selectedTarget.uuidString else {
            throw PassiveBluetoothExperimentOneExportArtifactError.manifestTargetMismatch
        }
        guard manifest.nembraBuildIdentifier == wire.runtimeBuild.nembraBuildIdentifier,
              manifest.nembraBuildInstanceID == wire.runtimeBuild.nembraBuildInstanceID,
              manifest.nembraBuildCommitSHA == wire.runtimeBuild.nembraBuildCommitSHA else {
            throw PassiveBluetoothExperimentOneExportArtifactError.manifestBuildProvenanceMismatch
        }

        let executableSHA = try validatedSHA256(wire.runtimeBuild.executableSHA256)
        return PassiveBluetoothExperimentOneVerifiedExport(
            experimentID: wire.experimentID,
            captureJSON: wire.captureJSON,
            manifestJSON: wire.manifestJSON,
            manifest: manifest,
            correlationResult: correlation,
            selectedPeripheralIdentifier: selectedTarget.uuidString,
            nembraBuildIdentifier: wire.runtimeBuild.nembraBuildIdentifier,
            nembraBuildInstanceID: wire.runtimeBuild.nembraBuildInstanceID,
            nembraBuildCommitSHA: wire.runtimeBuild.nembraBuildCommitSHA,
            executableSHA256: executableSHA
        )
    }

    private static func validatedCorrelationTarget(
        from result: PassiveBluetoothPowerCycleObservationResult
    ) throws -> UUID {
        guard result.windows.count == PassiveBluetoothPowerCycleObservationPhase.allCases.count,
              result.observationSnapshots.count == PassiveBluetoothPowerCycleObservationPhase.allCases.count else {
            throw PassiveBluetoothExperimentOneExportArtifactError.invalidCorrelationEvidence
        }
        let replayed = PassiveBluetoothPowerCycleTargetCorrelation.assess(
            firstOff: result.observationSnapshots[0],
            firstOn: result.observationSnapshots[1],
            secondOff: result.observationSnapshots[2],
            secondOn: result.observationSnapshots[3]
        )
        guard replayed == result.correlation else {
            throw PassiveBluetoothExperimentOneExportArtifactError.correlationResultMismatch
        }
        switch replayed.disposition {
        case let .singleRepeatableCandidate(identifier):
            return identifier
        case .invalidObservationAuthority,
             .invalidObservationWindowOrder,
             .noRepeatableCandidate,
             .ambiguousRepeatableCandidates:
            throw PassiveBluetoothExperimentOneExportArtifactError.correlationNotUnique
        }
    }

    private static func reconstructCorrelationEvidence(
        _ evidence: CorrelationEvidenceWire
    ) throws -> PassiveBluetoothPowerCycleObservationResult {
        let phases = PassiveBluetoothPowerCycleObservationPhase.allCases
        guard evidence.windows.count == phases.count,
              evidence.observationSnapshots.count == phases.count else {
            throw PassiveBluetoothExperimentOneExportArtifactError.invalidCorrelationEvidence
        }

        var receipts: [PassiveBluetoothPowerCycleObservationWindowReceipt] = []
        var snapshots: [PassiveBluetoothCandidateObservationSnapshot] = []
        receipts.reserveCapacity(phases.count)
        snapshots.reserveCapacity(phases.count)

        for index in phases.indices {
            let expectedPhase = phases[index]
            let window = evidence.windows[index]
            let snapshot = evidence.observationSnapshots[index]
            guard window.phase.phase == expectedPhase,
                  window.windowSequence == snapshot.windowSequence,
                  window.endedAtUptimeNanoseconds >= window.startedAtUptimeNanoseconds,
                  window.observedCandidateCount == snapshot.candidates.count else {
                throw PassiveBluetoothExperimentOneExportArtifactError.invalidCorrelationEvidence
            }

            let sequence = PassiveBluetoothCandidateObservationWindowSequence(
                rawValue: window.windowSequence
            )
            let candidateSnapshot = try PassiveBluetoothCandidateObservationSnapshot(
                observationSeriesIdentity: PassiveBluetoothCandidateObservationSeriesIdentity(
                    rawValue: snapshot.observationSeriesID
                ),
                windowSequence: sequence,
                candidates: snapshot.candidates.map {
                    PassiveBluetoothCandidateObservationSnapshot.Candidate(
                        id: $0.peripheralIdentifier,
                        isConnectable: $0.isConnectable
                    )
                }
            )
            receipts.append(PassiveBluetoothPowerCycleObservationWindowReceipt(
                phase: expectedPhase,
                windowSequence: sequence,
                startedAtUptimeNanoseconds: window.startedAtUptimeNanoseconds,
                endedAtUptimeNanoseconds: window.endedAtUptimeNanoseconds,
                observedCandidateCount: window.observedCandidateCount
            ))
            snapshots.append(candidateSnapshot)
        }

        let report = PassiveBluetoothPowerCycleTargetCorrelation.assess(
            firstOff: snapshots[0],
            firstOn: snapshots[1],
            secondOff: snapshots[2],
            secondOn: snapshots[3]
        )
        return PassiveBluetoothPowerCycleObservationResult(
            windows: receipts,
            observationSnapshots: snapshots,
            correlation: report
        )
    }

    private static func validatedSHA256(_ value: String) throws -> String {
        let normalized = value.lowercased()
        guard normalized.utf8.count == 64,
              normalized.utf8.allSatisfy({ byte in
                  (48...57).contains(byte) || (97...102).contains(byte)
              }) else {
            throw PassiveBluetoothExperimentOneExportArtifactError.invalidExecutableSHA256(value)
        }
        return normalized
    }

    private static func encode(_ wire: Wire) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(wire)
    }

    private static func validateSchemaShape(_ data: Data) throws {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        if let version = root["schemaVersion"] as? Int, version != schemaVersion {
            throw PassiveBluetoothExperimentOneExportArtifactError.unsupportedSchemaVersion(version)
        }
        try rejectUnexpectedKeys(
            in: root,
            allowed: [
                "schemaVersion", "artifactKind", "experimentID", "experimentRecipeID",
                "captureJSON", "manifestJSON", "correlationEvidence", "runtimeBuild",
            ],
            path: ""
        )
        if let build = root["runtimeBuild"] as? [String: Any] {
            try rejectUnexpectedKeys(
                in: build,
                allowed: [
                    "nembraBuildIdentifier", "nembraBuildInstanceID",
                    "nembraBuildCommitSHA", "executableSHA256",
                ],
                path: "runtimeBuild"
            )
        }
        if let evidence = root["correlationEvidence"] as? [String: Any] {
            try rejectUnexpectedKeys(
                in: evidence,
                allowed: ["windows", "observationSnapshots"],
                path: "correlationEvidence"
            )
            if let windows = evidence["windows"] as? [[String: Any]] {
                for (index, window) in windows.enumerated() {
                    try rejectUnexpectedKeys(
                        in: window,
                        allowed: [
                            "phase", "windowSequence", "startedAtUptimeNanoseconds",
                            "endedAtUptimeNanoseconds", "observedCandidateCount",
                        ],
                        path: "correlationEvidence.windows[\(index)]"
                    )
                }
            }
            if let snapshots = evidence["observationSnapshots"] as? [[String: Any]] {
                for (index, snapshot) in snapshots.enumerated() {
                    try rejectUnexpectedKeys(
                        in: snapshot,
                        allowed: ["observationSeriesID", "windowSequence", "candidates"],
                        path: "correlationEvidence.observationSnapshots[\(index)]"
                    )
                    if let candidates = snapshot["candidates"] as? [[String: Any]] {
                        for (candidateIndex, candidate) in candidates.enumerated() {
                            try rejectUnexpectedKeys(
                                in: candidate,
                                allowed: ["peripheralIdentifier", "isConnectable"],
                                path: "correlationEvidence.observationSnapshots[\(index)].candidates[\(candidateIndex)]"
                            )
                        }
                    }
                }
            }
        }
    }

    private static func rejectUnexpectedKeys(
        in object: [String: Any],
        allowed: Set<String>,
        path: String
    ) throws {
        for key in object.keys.sorted() where !allowed.contains(key) {
            let qualified = path.isEmpty ? key : "\(path).\(key)"
            throw PassiveBluetoothExperimentOneExportArtifactError.unexpectedExportField(qualified)
        }
    }
}