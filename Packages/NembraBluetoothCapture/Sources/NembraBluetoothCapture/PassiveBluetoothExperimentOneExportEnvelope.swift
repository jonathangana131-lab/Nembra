import CryptoKit
import Foundation

/// Fail-closed errors for the package-owned Experiment One share artifact.
///
/// The export envelope is provenance/evidence plumbing only. Successful verification does not
/// authorize a physical field run, authenticate an ES80, or assign protocol/telemetry meaning.
public enum PassiveBluetoothExperimentOneExportEnvelopeError: Error, Equatable, Sendable {
    case unsupportedSchemaVersion(Int)
    case unexpectedEnvelopeField(String)
    case unsupportedRecipe(PassiveBluetoothExperimentRecipeID)
    case correlationEvidenceInvalid
    case correlationNotUnique
    case powerCycleEvidenceMalformed
    case experimentEvidenceNotStructurallyCoherent
    case captureHashMismatch
    case manifestBuildIdentityMismatch
    case manifestTargetMismatch
    case invalidExecutableSHA256(String)
    case fieldAuthorizationNotSupported
}

/// Verified, immutable contents recovered from one package-owned Experiment One share artifact.
///
/// `captureJSON` is the exact sealed controller byte sequence embedded by the exporter. The
/// manifest is independently rebuilt against those bytes during verification, and the repeated
/// OFF1 -> ON1 -> OFF2 -> ON2 correlation result is replayed from its immutable snapshots.
public struct PassiveBluetoothExperimentOneVerifiedExport: Equatable, Sendable {
    public struct BuildEvidence: Equatable, Sendable {
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

    public let captureJSON: Data
    public let manifest: PassiveBluetoothStationaryCaptureManifest
    public let powerCycleResult: PassiveBluetoothPowerCycleObservationResult
    public let recipeID: PassiveBluetoothExperimentRecipeID
    public let buildEvidence: BuildEvidence

    fileprivate init(
        captureJSON: Data,
        manifest: PassiveBluetoothStationaryCaptureManifest,
        powerCycleResult: PassiveBluetoothPowerCycleObservationResult,
        recipeID: PassiveBluetoothExperimentRecipeID,
        buildEvidence: BuildEvidence
    ) {
        self.captureJSON = captureJSON
        self.manifest = manifest
        self.powerCycleResult = powerCycleResult
        self.recipeID = recipeID
        self.buildEvidence = buildEvidence
    }
}

/// Package-owned final export for ES80 Experiment One.
///
/// This intentionally does not expose an initializer accepting caller-authored build metadata,
/// target UUIDs, correlation summaries, or physical-GO booleans. Production export consumes the
/// coordinator's otherwise non-constructible finalized artifact and reads the running build identity
/// directly. The current schema records no field authorization because V14's physical gate is NO-GO.
public enum PassiveBluetoothExperimentOneExportEnvelopeJSON {
    public static let currentSchemaVersion = 1

    private struct EnvelopeWire: Codable {
        let schemaVersion: Int
        let recipeID: PassiveBluetoothExperimentRecipeID
        let captureJSON: Data
        let captureSHA256: String
        let manifestJSON: Data
        let powerCycleEvidence: PowerCycleEvidenceWire
        let build: BuildWire
        let fieldAuthorizationRecordID: String?
    }

    private struct BuildWire: Codable {
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

    private struct PowerCycleEvidenceWire: Codable {
        let windows: [WindowWire]
        let observationSnapshots: [SnapshotWire]

        init(_ result: PassiveBluetoothPowerCycleObservationResult) {
            windows = result.windows.map(WindowWire.init)
            observationSnapshots = result.observationSnapshots.map(SnapshotWire.init)
        }
    }

    private struct WindowWire: Codable {
        let phaseRawValue: Int
        let windowSequence: UInt64
        let startedAtUptimeNanoseconds: UInt64
        let endedAtUptimeNanoseconds: UInt64
        let observedCandidateCount: Int

        init(_ receipt: PassiveBluetoothPowerCycleObservationWindowReceipt) {
            phaseRawValue = receipt.phase.rawValue
            windowSequence = receipt.windowSequence.rawValue
            startedAtUptimeNanoseconds = receipt.startedAtUptimeNanoseconds
            endedAtUptimeNanoseconds = receipt.endedAtUptimeNanoseconds
            observedCandidateCount = receipt.observedCandidateCount
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
    }

    private struct CandidateWire: Codable {
        let peripheralIdentifier: UUID
        let isConnectable: Bool?

        init(_ candidate: PassiveBluetoothCandidateObservationSnapshot.Candidate) {
            peripheralIdentifier = candidate.id
            isConnectable = candidate.isConnectable
        }
    }

    private static let allowedTopLevelKeys: Set<String> = [
        "schemaVersion",
        "recipeID",
        "captureJSON",
        "captureSHA256",
        "manifestJSON",
        "powerCycleEvidence",
        "build",
        "fieldAuthorizationRecordID",
    ]

    private static let allowedBuildKeys: Set<String> = [
        "buildIdentifier",
        "buildInstanceID",
        "sourceCommitSHA",
        "executableSHA256",
    ]

    private static let allowedPowerCycleKeys: Set<String> = [
        "windows",
        "observationSnapshots",
    ]

    private static let allowedWindowKeys: Set<String> = [
        "phaseRawValue",
        "windowSequence",
        "startedAtUptimeNanoseconds",
        "endedAtUptimeNanoseconds",
        "observedCandidateCount",
    ]

    private static let allowedSnapshotKeys: Set<String> = [
        "observationSeriesIdentity",
        "windowSequence",
        "candidates",
    ]

    private static let allowedCandidateKeys: Set<String> = [
        "peripheralIdentifier",
        "isConnectable",
    ]

    /// Produces the field-share envelope from the exact finalized coordinator artifact and the
    /// identity of the running application. Operator input is limited to declared stationary setup.
    /// Physical execution remains independently locked by `PassiveBluetoothExperimentOneFieldExecutionGate`.
    public static func make(
        finalizedArtifact: PassiveBluetoothExperimentOneCoordinator.FinalizedArtifact,
        setup: PassiveBluetoothStationaryCaptureSetup,
        prettyPrinted: Bool = true
    ) throws -> Data {
        let runtimeIdentity = try PassiveBluetoothCaptureRuntimeBuildIdentityReader.currentApplication()
        return try make(
            captureJSON: finalizedArtifact.captureJSON,
            powerCycleResult: finalizedArtifact.powerCycleResult,
            setup: setup,
            runtimeIdentity: runtimeIdentity,
            experimentID: UUID(),
            preparedAt: Date(),
            prettyPrinted: prettyPrinted
        )
    }

    /// Package-scoped deterministic seam for exact artifact/provenance tests. External app code
    /// cannot use this overload to replace coordinator-issued finalization or runtime build identity.
    package static func make(
        captureJSON: Data,
        powerCycleResult: PassiveBluetoothPowerCycleObservationResult,
        setup: PassiveBluetoothStationaryCaptureSetup,
        runtimeIdentity: PassiveBluetoothCaptureRuntimeBuildIdentity,
        experimentID: UUID,
        preparedAt: Date,
        prettyPrinted: Bool = true
    ) throws -> Data {
        let replayed = try replayPowerCycleEvidence(PowerCycleEvidenceWire(powerCycleResult))
        guard replayed == powerCycleResult else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.correlationEvidenceInvalid
        }

        let correlatedTarget = try uniqueCorrelatedTarget(in: replayed)
        let structuralTarget = try structurallyCoherentTarget(
            captureJSON: captureJSON,
            powerCycleResult: replayed
        )
        guard correlatedTarget == structuralTarget else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.correlationEvidenceInvalid
        }

        let manifest = try PassiveBluetoothStationaryCaptureManifestBuilder.make(
            captureJSON: captureJSON,
            experimentID: experimentID,
            experimentRecipe: .es80FingerprintV1,
            preparedAt: preparedAt,
            nembraBuildIdentifier: runtimeIdentity.buildIdentifier,
            nembraBuildInstanceID: runtimeIdentity.buildInstanceID,
            nembraBuildCommitSHA: runtimeIdentity.sourceCommitSHA,
            selectedPeripheralIdentifier: structuralTarget.uuidString,
            setup: setup
        )
        let manifestJSON = try PassiveBluetoothStationaryCaptureManifestJSON.encode(
            manifest,
            prettyPrinted: false
        )

        let captureHash = sha256Hex(captureJSON)
        guard captureHash == manifest.sourceArtifact.sha256 else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.captureHashMismatch
        }

        let wire = EnvelopeWire(
            schemaVersion: currentSchemaVersion,
            recipeID: .es80FingerprintV1,
            captureJSON: captureJSON,
            captureSHA256: captureHash,
            manifestJSON: manifestJSON,
            powerCycleEvidence: PowerCycleEvidenceWire(replayed),
            build: BuildWire(runtimeIdentity),
            fieldAuthorizationRecordID: nil
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = prettyPrinted ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return try encoder.encode(wire)
    }

    /// Verifies the closed-world envelope and replays every software evidence binding.
    ///
    /// This proves only that the exported bytes are internally consistent with the package evidence
    /// recorded in the envelope. It is not a physical-GO check and deliberately rejects any caller-
    /// supplied field authorization in the current NO-GO schema.
    public static func verify(_ envelopeJSON: Data) throws -> PassiveBluetoothExperimentOneVerifiedExport {
        try validateClosedWorldShape(envelopeJSON)

        let decoder = JSONDecoder()
        let wire = try decoder.decode(EnvelopeWire.self, from: envelopeJSON)
        guard wire.schemaVersion == currentSchemaVersion else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError
                .unsupportedSchemaVersion(wire.schemaVersion)
        }
        guard wire.recipeID == .es80FingerprintV1 else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.unsupportedRecipe(wire.recipeID)
        }
        guard wire.fieldAuthorizationRecordID == nil else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.fieldAuthorizationNotSupported
        }
        guard isCanonicalSHA256(wire.captureSHA256) else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.captureHashMismatch
        }
        guard isCanonicalSHA256(wire.build.executableSHA256) else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError
                .invalidExecutableSHA256(wire.build.executableSHA256)
        }

        let exactCaptureHash = sha256Hex(wire.captureJSON)
        guard exactCaptureHash == wire.captureSHA256 else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.captureHashMismatch
        }

        let manifest = try PassiveBluetoothStationaryCaptureManifestJSON.verifyCaptureBinding(
            manifestJSON: wire.manifestJSON,
            captureJSON: wire.captureJSON
        )
        guard manifest.schemaVersion == PassiveBluetoothStationaryCaptureManifest.currentSchemaVersion,
              manifest.experimentRecipeID == wire.recipeID,
              manifest.nembraBuildIdentifier == wire.build.buildIdentifier,
              manifest.nembraBuildInstanceID == wire.build.buildInstanceID,
              manifest.nembraBuildCommitSHA == wire.build.sourceCommitSHA,
              manifest.sourceArtifact.sha256 == exactCaptureHash else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.manifestBuildIdentityMismatch
        }

        let result = try replayPowerCycleEvidence(wire.powerCycleEvidence)
        let correlatedTarget = try uniqueCorrelatedTarget(in: result)
        let structuralTarget = try structurallyCoherentTarget(
            captureJSON: wire.captureJSON,
            powerCycleResult: result
        )
        guard correlatedTarget == structuralTarget,
              manifest.sourceArtifact.selectedPeripheralIdentifier == structuralTarget.uuidString else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.manifestTargetMismatch
        }

        return PassiveBluetoothExperimentOneVerifiedExport(
            captureJSON: wire.captureJSON,
            manifest: manifest,
            powerCycleResult: result,
            recipeID: wire.recipeID,
            buildEvidence: .init(
                buildIdentifier: wire.build.buildIdentifier,
                buildInstanceID: wire.build.buildInstanceID,
                sourceCommitSHA: wire.build.sourceCommitSHA,
                executableSHA256: wire.build.executableSHA256
            )
        )
    }

    private static func validateClosedWorldShape(_ data: Data) throws {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        try rejectUnexpectedKeys(root, allowed: allowedTopLevelKeys, path: "")

        if let build = root["build"] as? [String: Any] {
            try rejectUnexpectedKeys(build, allowed: allowedBuildKeys, path: "build")
        }

        if let powerCycle = root["powerCycleEvidence"] as? [String: Any] {
            try rejectUnexpectedKeys(
                powerCycle,
                allowed: allowedPowerCycleKeys,
                path: "powerCycleEvidence"
            )

            if let windows = powerCycle["windows"] as? [[String: Any]] {
                for (index, window) in windows.enumerated() {
                    try rejectUnexpectedKeys(
                        window,
                        allowed: allowedWindowKeys,
                        path: "powerCycleEvidence.windows[\(index)]"
                    )
                }
            }

            if let snapshots = powerCycle["observationSnapshots"] as? [[String: Any]] {
                for (snapshotIndex, snapshot) in snapshots.enumerated() {
                    let snapshotPath = "powerCycleEvidence.observationSnapshots[\(snapshotIndex)]"
                    try rejectUnexpectedKeys(
                        snapshot,
                        allowed: allowedSnapshotKeys,
                        path: snapshotPath
                    )
                    if let candidates = snapshot["candidates"] as? [[String: Any]] {
                        for (candidateIndex, candidate) in candidates.enumerated() {
                            try rejectUnexpectedKeys(
                                candidate,
                                allowed: allowedCandidateKeys,
                                path: "\(snapshotPath).candidates[\(candidateIndex)]"
                            )
                        }
                    }
                }
            }
        }
    }

    private static func rejectUnexpectedKeys(
        _ object: [String: Any],
        allowed: Set<String>,
        path: String
    ) throws {
        for key in object.keys.sorted() where !allowed.contains(key) {
            let qualified = path.isEmpty ? key : "\(path).\(key)"
            throw PassiveBluetoothExperimentOneExportEnvelopeError
                .unexpectedEnvelopeField(qualified)
        }
    }

    private static func replayPowerCycleEvidence(
        _ evidence: PowerCycleEvidenceWire
    ) throws -> PassiveBluetoothPowerCycleObservationResult {
        let requiredCount = PassiveBluetoothPowerCycleObservationPhase.allCases.count
        guard evidence.windows.count == requiredCount,
              evidence.observationSnapshots.count == requiredCount else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.powerCycleEvidenceMalformed
        }

        var receipts: [PassiveBluetoothPowerCycleObservationWindowReceipt] = []
        var snapshots: [PassiveBluetoothCandidateObservationSnapshot] = []
        receipts.reserveCapacity(requiredCount)
        snapshots.reserveCapacity(requiredCount)

        for index in 0..<requiredCount {
            let window = evidence.windows[index]
            let snapshotWire = evidence.observationSnapshots[index]
            guard let phase = PassiveBluetoothPowerCycleObservationPhase(rawValue: window.phaseRawValue),
                  phase.rawValue == index,
                  window.endedAtUptimeNanoseconds >= window.startedAtUptimeNanoseconds,
                  window.windowSequence == snapshotWire.windowSequence,
                  window.observedCandidateCount == snapshotWire.candidates.count else {
                throw PassiveBluetoothExperimentOneExportEnvelopeError.powerCycleEvidenceMalformed
            }

            let sequence = PassiveBluetoothCandidateObservationWindowSequence(
                rawValue: window.windowSequence
            )
            let snapshot: PassiveBluetoothCandidateObservationSnapshot
            do {
                snapshot = try PassiveBluetoothCandidateObservationSnapshot(
                    observationSeriesIdentity: .init(rawValue: snapshotWire.observationSeriesIdentity),
                    windowSequence: sequence,
                    candidates: snapshotWire.candidates.map {
                        .init(id: $0.peripheralIdentifier, isConnectable: $0.isConnectable)
                    }
                )
            } catch {
                throw PassiveBluetoothExperimentOneExportEnvelopeError.powerCycleEvidenceMalformed
            }

            receipts.append(
                PassiveBluetoothPowerCycleObservationWindowReceipt(
                    phase: phase,
                    windowSequence: sequence,
                    startedAtUptimeNanoseconds: window.startedAtUptimeNanoseconds,
                    endedAtUptimeNanoseconds: window.endedAtUptimeNanoseconds,
                    observedCandidateCount: window.observedCandidateCount
                )
            )
            snapshots.append(snapshot)
        }

        let correlation = PassiveBluetoothPowerCycleTargetCorrelation.assess(
            firstOff: snapshots[0],
            firstOn: snapshots[1],
            secondOff: snapshots[2],
            secondOn: snapshots[3]
        )
        return PassiveBluetoothPowerCycleObservationResult(
            windows: receipts,
            observationSnapshots: snapshots,
            correlation: correlation
        )
    }

    private static func structurallyCoherentTarget(
        captureJSON: Data,
        powerCycleResult: PassiveBluetoothPowerCycleObservationResult
    ) throws -> UUID {
        let session: PassiveBluetoothCaptureSession
        do {
            session = try PassiveBluetoothCaptureJSON.decode(captureJSON)
        } catch {
            throw PassiveBluetoothExperimentOneExportEnvelopeError
                .experimentEvidenceNotStructurallyCoherent
        }

        let assessment = PassiveBluetoothExperimentOneStructuralEvidenceAssessment.assess(
            powerCycleResult: powerCycleResult,
            captureSession: session
        )
        guard case let .structurallyCoherent(target) = assessment.status else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError
                .experimentEvidenceNotStructurallyCoherent
        }
        return target
    }

    private static func uniqueCorrelatedTarget(
        in result: PassiveBluetoothPowerCycleObservationResult
    ) throws -> UUID {
        switch result.correlation.disposition {
        case .invalidObservationAuthority, .invalidObservationWindowOrder:
            throw PassiveBluetoothExperimentOneExportEnvelopeError.correlationEvidenceInvalid
        case .noRepeatableCandidate, .ambiguousRepeatableCandidates:
            throw PassiveBluetoothExperimentOneExportEnvelopeError.correlationNotUnique
        case let .singleRepeatableCandidate(identifier):
            return identifier
        }
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func isCanonicalSHA256(_ value: String) -> Bool {
        guard value.utf8.count == 64 else { return false }
        return value.utf8.allSatisfy { byte in
            (48...57).contains(byte) || (97...102).contains(byte)
        }
    }
}
