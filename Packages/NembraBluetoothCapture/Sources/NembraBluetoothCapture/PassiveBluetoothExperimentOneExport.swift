import Foundation
import NembraCore

/// External field-execution acceptance is deliberately separate from runtime provenance.
///
/// Schema v1 can record only `.notBound`: a runtime executable hash, build-instance ID,
/// source SHA, or locally verified capture is not an independent authorization to run the
/// physical experiment. A future accepted-build record must evolve this contract explicitly.
public enum PassiveBluetoothExperimentOneExternalFieldAuthorization: String, Codable, Equatable, Sendable {
    case notBound
}

/// Immutable package-owned export ready for the product Share action.
///
/// `data` is one closed-world JSON envelope. It embeds the exact frozen capture bytes,
/// the schema-v3 stationary manifest, and replayable OFF/ON/OFF/ON correlation evidence.
/// Preparing an export never authorizes a physical experiment.
public struct PassiveBluetoothExperimentOnePreparedExport: Equatable, Sendable {
    public let data: Data
    public let suggestedFilename: String
    public let fieldAuthorization: PassiveBluetoothExperimentOneExternalFieldAuthorization

    fileprivate init(
        data: Data,
        suggestedFilename: String,
        fieldAuthorization: PassiveBluetoothExperimentOneExternalFieldAuthorization
    ) {
        self.data = data
        self.suggestedFilename = suggestedFilename
        self.fieldAuthorization = fieldAuthorization
    }
}

/// Verified projection of runtime provenance preserved by the export envelope.
///
/// This is provenance declared by the producing runtime. It is not an accepted-build
/// attestation and does not authorize field execution.
public struct PassiveBluetoothExperimentOneVerifiedBuildIdentity: Equatable, Sendable {
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

/// Result of replaying and re-binding a final Experiment One export.
///
/// A successful verification proves internal software consistency of this immutable export:
/// exact capture-byte binding, manifest-v3 binding, replayable correlation evidence,
/// canonical recipe/setup, target agreement, and the accepted software observation-duration
/// rules. It does not authenticate physical ES80 hardware, prove RF completeness, assign
/// GATT/Tuya semantics, or authorize the field experiment.
public struct PassiveBluetoothExperimentOneVerifiedExport: Equatable, Sendable {
    public let sealedCaptureJSON: Data
    public let manifest: PassiveBluetoothStationaryCaptureManifest
    public let experimentRecipeID: PassiveBluetoothExperimentRecipeID
    public let preparedAt: Date
    public let correlatedPeripheralIdentifier: UUID
    public let runtimeBuildIdentity: PassiveBluetoothExperimentOneVerifiedBuildIdentity
    public let powerCycleResult: PassiveBluetoothPowerCycleObservationResult
    public let fieldAuthorization: PassiveBluetoothExperimentOneExternalFieldAuthorization

    fileprivate init(
        sealedCaptureJSON: Data,
        manifest: PassiveBluetoothStationaryCaptureManifest,
        experimentRecipeID: PassiveBluetoothExperimentRecipeID,
        preparedAt: Date,
        correlatedPeripheralIdentifier: UUID,
        runtimeBuildIdentity: PassiveBluetoothExperimentOneVerifiedBuildIdentity,
        powerCycleResult: PassiveBluetoothPowerCycleObservationResult,
        fieldAuthorization: PassiveBluetoothExperimentOneExternalFieldAuthorization
    ) {
        self.sealedCaptureJSON = sealedCaptureJSON
        self.manifest = manifest
        self.experimentRecipeID = experimentRecipeID
        self.preparedAt = preparedAt
        self.correlatedPeripheralIdentifier = correlatedPeripheralIdentifier
        self.runtimeBuildIdentity = runtimeBuildIdentity
        self.powerCycleResult = powerCycleResult
        self.fieldAuthorization = fieldAuthorization
    }
}

public enum PassiveBluetoothExperimentOneExportError: Error, Equatable, Sendable {
    case invalidEnvelopeJSON
    case unexpectedEnvelopeField(String)
    case unsupportedSchemaVersion(Int)
    case unsupportedRecipe(String)
    case unsupportedFieldAuthorization(String)
    case invalidRuntimeBuildIdentity
    case invalidPowerCycleEvidence
    case captureEvidenceNotStructurallyCoherent
    case correlatedTargetMismatch
    case manifestBindingInvalid
    case manifestMismatch
}

/// Package-owned final artifact composer/verifier for ES80-FINGERPRINT-v1.
///
/// Production preparation accepts only `FinalizedArtifact`, whose initializer is package-private
/// and which is emitted only by the authority-bearing Experiment One coordinator after the
/// accepted Horizon/finalization transaction. UI code therefore cannot mint a final export from
/// arbitrary raw capture JSON, detached correlation data, or caller-supplied build provenance.
public enum PassiveBluetoothExperimentOneExport {
    public static let currentSchemaVersion = 1

    private static let canonicalRecipe = PassiveBluetoothExperimentRecipe.es80FingerprintV1
    private static let canonicalSetup = PassiveBluetoothStationaryCaptureSetup(
        chargerState: .disconnected,
        executionContext: .foregroundUnlockedScreenOn,
        stockAppReferenceSetup: .none
    )

    /// Production Share preparation. Runtime identity is read from the exact running app rather
    /// than accepted from SwiftUI or another caller.
    public static func prepareForCurrentApplication(
        finalizedArtifact: PassiveBluetoothExperimentOneCoordinator.FinalizedArtifact
    ) throws -> PassiveBluetoothExperimentOnePreparedExport {
        let runtimeBuildIdentity = try PassiveBluetoothCaptureRuntimeBuildIdentityReader.currentApplication()
        return try prepare(
            finalizedArtifact: finalizedArtifact,
            runtimeBuildIdentity: runtimeBuildIdentity,
            preparedAt: Date()
        )
    }

    /// Replays every software-consistency boundary that can be checked offline from one envelope.
    /// This intentionally returns `.notBound` field authorization even on success.
    public static func verify(
        _ exportJSON: Data
    ) throws -> PassiveBluetoothExperimentOneVerifiedExport {
        try validateEnvelopeShape(exportJSON)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let wire: WireEnvelope
        do {
            wire = try decoder.decode(WireEnvelope.self, from: exportJSON)
        } catch {
            throw PassiveBluetoothExperimentOneExportError.invalidEnvelopeJSON
        }

        guard wire.schemaVersion == currentSchemaVersion else {
            throw PassiveBluetoothExperimentOneExportError.unsupportedSchemaVersion(wire.schemaVersion)
        }
        guard wire.experimentRecipeID == canonicalRecipe.id.rawValue else {
            throw PassiveBluetoothExperimentOneExportError.unsupportedRecipe(wire.experimentRecipeID)
        }
        guard wire.fieldAuthorization == PassiveBluetoothExperimentOneExternalFieldAuthorization.notBound.rawValue else {
            throw PassiveBluetoothExperimentOneExportError
                .unsupportedFieldAuthorization(wire.fieldAuthorization)
        }
        guard isValidRuntimeBuildIdentity(wire.runtimeBuildIdentity) else {
            throw PassiveBluetoothExperimentOneExportError.invalidRuntimeBuildIdentity
        }

        let captureSession: PassiveBluetoothCaptureSession
        do {
            captureSession = try PassiveBluetoothCaptureJSON.decode(wire.sealedCaptureJSON)
        } catch {
            throw PassiveBluetoothExperimentOneExportError.captureEvidenceNotStructurallyCoherent
        }

        let powerCycleResult: PassiveBluetoothPowerCycleObservationResult
        do {
            powerCycleResult = try reconstructPowerCycleResult(from: wire.powerCycleWindows)
        } catch {
            throw PassiveBluetoothExperimentOneExportError.invalidPowerCycleEvidence
        }

        let structural = PassiveBluetoothExperimentOneStructuralEvidenceAssessment.assess(
            powerCycleResult: powerCycleResult,
            captureSession: captureSession
        )
        guard case let .structurallyCoherent(structuralTarget) = structural.status else {
            throw PassiveBluetoothExperimentOneExportError.captureEvidenceNotStructurallyCoherent
        }
        guard structuralTarget == wire.correlatedPeripheralIdentifier else {
            throw PassiveBluetoothExperimentOneExportError.correlatedTargetMismatch
        }

        let manifest: PassiveBluetoothStationaryCaptureManifest
        do {
            manifest = try PassiveBluetoothStationaryCaptureManifestJSON.verifyCaptureBinding(
                manifestJSON: wire.stationaryManifestJSON,
                captureJSON: wire.sealedCaptureJSON
            )
        } catch {
            throw PassiveBluetoothExperimentOneExportError.manifestBindingInvalid
        }

        guard manifest.schemaVersion == PassiveBluetoothStationaryCaptureManifest.currentSchemaVersion,
              manifest.experimentKind == .stationaryBaseline,
              manifest.experimentID == captureSession.id,
              manifest.experimentRecipeID == canonicalRecipe.id,
              manifest.preparedAt == wire.preparedAt,
              manifest.nembraBuildIdentifier == wire.runtimeBuildIdentity.buildIdentifier,
              manifest.nembraBuildInstanceID == wire.runtimeBuildIdentity.buildInstanceID,
              manifest.nembraBuildCommitSHA == wire.runtimeBuildIdentity.sourceCommitSHA,
              manifest.setup == canonicalSetup,
              manifest.sourceArtifact.captureSessionID == captureSession.id,
              manifest.sourceArtifact.selectedPeripheralIdentifier == structuralTarget.uuidString else {
            throw PassiveBluetoothExperimentOneExportError.manifestMismatch
        }

        return PassiveBluetoothExperimentOneVerifiedExport(
            sealedCaptureJSON: wire.sealedCaptureJSON,
            manifest: manifest,
            experimentRecipeID: canonicalRecipe.id,
            preparedAt: wire.preparedAt,
            correlatedPeripheralIdentifier: structuralTarget,
            runtimeBuildIdentity: .init(
                buildIdentifier: wire.runtimeBuildIdentity.buildIdentifier,
                buildInstanceID: wire.runtimeBuildIdentity.buildInstanceID,
                sourceCommitSHA: wire.runtimeBuildIdentity.sourceCommitSHA,
                executableSHA256: wire.runtimeBuildIdentity.executableSHA256
            ),
            powerCycleResult: powerCycleResult,
            fieldAuthorization: .notBound
        )
    }

    /// Deterministic package seam used by tests and future package-owned composition.
    /// It remains non-public so app/UI clients cannot inject provenance or preparation time.
    package static func prepare(
        finalizedArtifact: PassiveBluetoothExperimentOneCoordinator.FinalizedArtifact,
        runtimeBuildIdentity: PassiveBluetoothCaptureRuntimeBuildIdentity,
        preparedAt: Date
    ) throws -> PassiveBluetoothExperimentOnePreparedExport {
        let captureSession: PassiveBluetoothCaptureSession
        do {
            captureSession = try PassiveBluetoothCaptureJSON.decode(finalizedArtifact.captureJSON)
        } catch {
            throw PassiveBluetoothExperimentOneExportError.captureEvidenceNotStructurallyCoherent
        }

        let structural = PassiveBluetoothExperimentOneStructuralEvidenceAssessment.assess(
            powerCycleResult: finalizedArtifact.powerCycleResult,
            captureSession: captureSession
        )
        guard case let .structurallyCoherent(correlatedTarget) = structural.status else {
            throw PassiveBluetoothExperimentOneExportError.captureEvidenceNotStructurallyCoherent
        }

        let manifest: PassiveBluetoothStationaryCaptureManifest
        let manifestJSON: Data
        do {
            manifest = try PassiveBluetoothStationaryCaptureManifestBuilder.make(
                captureJSON: finalizedArtifact.captureJSON,
                experimentID: captureSession.id,
                experimentRecipe: canonicalRecipe,
                preparedAt: preparedAt,
                nembraBuildIdentifier: runtimeBuildIdentity.buildIdentifier,
                nembraBuildInstanceID: runtimeBuildIdentity.buildInstanceID,
                nembraBuildCommitSHA: runtimeBuildIdentity.sourceCommitSHA,
                selectedPeripheralIdentifier: correlatedTarget.uuidString,
                setup: canonicalSetup
            )
            manifestJSON = try PassiveBluetoothStationaryCaptureManifestJSON.encode(manifest)
            _ = try PassiveBluetoothStationaryCaptureManifestJSON.verifyCaptureBinding(
                manifestJSON: manifestJSON,
                captureJSON: finalizedArtifact.captureJSON
            )
        } catch {
            throw PassiveBluetoothExperimentOneExportError.manifestBindingInvalid
        }

        let wire = WireEnvelope(
            schemaVersion: currentSchemaVersion,
            experimentRecipeID: canonicalRecipe.id.rawValue,
            preparedAt: preparedAt,
            fieldAuthorization: PassiveBluetoothExperimentOneExternalFieldAuthorization.notBound.rawValue,
            correlatedPeripheralIdentifier: correlatedTarget,
            runtimeBuildIdentity: .init(runtimeBuildIdentity),
            powerCycleWindows: makeWireWindows(finalizedArtifact.powerCycleResult),
            stationaryManifestJSON: manifestJSON,
            sealedCaptureJSON: finalizedArtifact.captureJSON
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data: Data
        do {
            data = try encoder.encode(wire)
        } catch {
            throw PassiveBluetoothExperimentOneExportError.invalidEnvelopeJSON
        }

        // Verify the exact bytes we are about to hand to Share. This catches accidental
        // divergence between the production composer and offline verifier immediately.
        _ = try verify(data)

        return PassiveBluetoothExperimentOnePreparedExport(
            data: data,
            suggestedFilename: "Nembra-ES80-Fingerprint-\(captureSession.id.uuidString).json",
            fieldAuthorization: .notBound
        )
    }

    private struct WireEnvelope: Codable {
        let schemaVersion: Int
        let experimentRecipeID: String
        let preparedAt: Date
        let fieldAuthorization: String
        let correlatedPeripheralIdentifier: UUID
        let runtimeBuildIdentity: WireBuildIdentity
        let powerCycleWindows: [WirePowerCycleWindow]
        let stationaryManifestJSON: Data
        let sealedCaptureJSON: Data
    }

    private struct WireBuildIdentity: Codable {
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

    private struct WirePowerCycleWindow: Codable {
        let phase: WirePowerCyclePhase
        let observationSeriesID: UUID
        let windowSequence: UInt64
        let startedAtUptimeNanoseconds: UInt64
        let endedAtUptimeNanoseconds: UInt64
        let observedCandidateCount: Int
        let candidates: [WireCandidate]
    }

    private enum WirePowerCyclePhase: String, Codable {
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

    private struct WireCandidate: Codable {
        let id: UUID
        let isConnectable: Bool?
    }

    private static func makeWireWindows(
        _ result: PassiveBluetoothPowerCycleObservationResult
    ) -> [WirePowerCycleWindow] {
        guard result.windows.count == result.observationSnapshots.count else { return [] }
        return zip(result.windows, result.observationSnapshots).map { receipt, snapshot in
            WirePowerCycleWindow(
                phase: .init(receipt.phase),
                observationSeriesID: snapshot.observationSeriesIdentity.rawValue,
                windowSequence: receipt.windowSequence.rawValue,
                startedAtUptimeNanoseconds: receipt.startedAtUptimeNanoseconds,
                endedAtUptimeNanoseconds: receipt.endedAtUptimeNanoseconds,
                observedCandidateCount: receipt.observedCandidateCount,
                candidates: snapshot.candidates.map {
                    WireCandidate(id: $0.id, isConnectable: $0.isConnectable)
                }
            )
        }
    }

    private static func reconstructPowerCycleResult(
        from windows: [WirePowerCycleWindow]
    ) throws -> PassiveBluetoothPowerCycleObservationResult {
        guard windows.count == PassiveBluetoothPowerCycleObservationPhase.allCases.count else {
            throw PassiveBluetoothExperimentOneExportError.invalidPowerCycleEvidence
        }

        var receipts: [PassiveBluetoothPowerCycleObservationWindowReceipt] = []
        var snapshots: [PassiveBluetoothCandidateObservationSnapshot] = []
        receipts.reserveCapacity(windows.count)
        snapshots.reserveCapacity(windows.count)

        for window in windows {
            let sequence = PassiveBluetoothCandidateObservationWindowSequence(
                rawValue: window.windowSequence
            )
            let candidates = window.candidates.map {
                PassiveBluetoothCandidateObservationSnapshot.Candidate(
                    id: $0.id,
                    isConnectable: $0.isConnectable
                )
            }
            let snapshot = try PassiveBluetoothCandidateObservationSnapshot(
                observationSeriesIdentity: .init(rawValue: window.observationSeriesID),
                windowSequence: sequence,
                candidates: candidates
            )
            let receipt = PassiveBluetoothPowerCycleObservationWindowReceipt(
                phase: window.phase.phase,
                windowSequence: sequence,
                startedAtUptimeNanoseconds: window.startedAtUptimeNanoseconds,
                endedAtUptimeNanoseconds: window.endedAtUptimeNanoseconds,
                observedCandidateCount: window.observedCandidateCount
            )
            receipts.append(receipt)
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

    private static func isValidRuntimeBuildIdentity(_ identity: WireBuildIdentity) -> Bool {
        guard !identity.buildIdentifier.isEmpty,
              identity.buildIdentifier.count <= 128,
              identity.buildIdentifier.unicodeScalars.allSatisfy({
                  CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-")).contains($0)
              }),
              PassiveBluetoothCaptureRuntimeBuildIdentityReader
                  .normalizedBuildInstanceID(identity.buildInstanceID) != nil,
              PassiveBluetoothCaptureRuntimeBuildIdentityReader
                  .normalizedFullGitCommitSHA(identity.sourceCommitSHA) != nil,
              identity.executableSHA256.count == 64,
              identity.executableSHA256.allSatisfy({ $0.isHexDigit }),
              identity.executableSHA256 == identity.executableSHA256.lowercased() else {
            return false
        }
        return true
    }

    private static func validateEnvelopeShape(_ data: Data) throws {
        let rootAny: Any
        do {
            rootAny = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw PassiveBluetoothExperimentOneExportError.invalidEnvelopeJSON
        }
        guard let root = rootAny as? [String: Any] else {
            throw PassiveBluetoothExperimentOneExportError.invalidEnvelopeJSON
        }

        try rejectUnexpectedKeys(
            in: root,
            allowed: [
                "schemaVersion", "experimentRecipeID", "preparedAt", "fieldAuthorization",
                "correlatedPeripheralIdentifier", "runtimeBuildIdentity", "powerCycleWindows",
                "stationaryManifestJSON", "sealedCaptureJSON",
            ],
            path: ""
        )
        if let build = root["runtimeBuildIdentity"] as? [String: Any] {
            try rejectUnexpectedKeys(
                in: build,
                allowed: ["buildIdentifier", "buildInstanceID", "sourceCommitSHA", "executableSHA256"],
                path: "runtimeBuildIdentity"
            )
        }
        if let windows = root["powerCycleWindows"] as? [[String: Any]] {
            for (index, window) in windows.enumerated() {
                let path = "powerCycleWindows[\(index)]"
                try rejectUnexpectedKeys(
                    in: window,
                    allowed: [
                        "phase", "observationSeriesID", "windowSequence",
                        "startedAtUptimeNanoseconds", "endedAtUptimeNanoseconds",
                        "observedCandidateCount", "candidates",
                    ],
                    path: path
                )
                if let candidates = window["candidates"] as? [[String: Any]] {
                    for (candidateIndex, candidate) in candidates.enumerated() {
                        try rejectUnexpectedKeys(
                            in: candidate,
                            allowed: ["id", "isConnectable"],
                            path: "\(path).candidates[\(candidateIndex)]"
                        )
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
            throw PassiveBluetoothExperimentOneExportError.unexpectedEnvelopeField(qualified)
        }
    }
}
