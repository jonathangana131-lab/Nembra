import Foundation

/// Final package-owned share artifact for ES80 Experiment One.
///
/// The envelope preserves the exact immutable controller JSON bytes alongside replayable four-window
/// correlation evidence, the schema-v3 stationary manifest, and runtime build provenance. None of
/// these fields authorize a physical experiment by themselves; physical GO remains an independent
/// repository/build acceptance decision.
public struct PassiveBluetoothExperimentOneVerifiedExport: Equatable, Sendable {
    public let captureJSON: Data
    public let stationaryManifest: PassiveBluetoothStationaryCaptureManifest
    public let powerCycleResult: PassiveBluetoothPowerCycleObservationResult
    public let recipeID: PassiveBluetoothExperimentRecipeID
    public let buildIdentifier: String
    public let buildInstanceID: String
    public let sourceCommitSHA: String
    public let executableSHA256: String
}

public enum PassiveBluetoothExperimentOneExportEnvelopeError: Error, Equatable, Sendable {
    case unsupportedSchemaVersion(Int)
    case unexpectedField(String)
    case malformedCorrelationEvidence
    case correlationNotUnique
    case correlationDoesNotMatchManifest
    case manifestProvenanceMismatch
    case invalidExecutableSHA256(String)
}

/// Closed-world JSON codec/verifier for the primary Experiment One share artifact.
public enum PassiveBluetoothExperimentOneExportEnvelopeJSON {
    public static let currentSchemaVersion = 1

    private struct BuildWire: Codable {
        let buildIdentifier: String
        let buildInstanceID: String
        let sourceCommitSHA: String
        let executableSHA256: String
    }

    private struct CandidateWire: Codable {
        let identifier: UUID
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

    private struct CorrelationWire: Codable {
        let windows: [WindowWire]
        let observationSnapshots: [SnapshotWire]
    }

    private struct EnvelopeWire: Codable {
        let schemaVersion: Int
        let recipeID: PassiveBluetoothExperimentRecipeID
        /// Exact sealed bytes, encoded by JSONEncoder as base64. Never parsed/reformatted on export.
        let captureJSON: Data
        /// Exact canonical manifest JSON bytes, encoded by JSONEncoder as base64.
        let stationaryManifestJSON: Data
        let runtimeBuild: BuildWire
        let correlationEvidence: CorrelationWire
    }

    /// Verifies all cross-bindings and returns the immutable evidence values for offline analysis.
    public static func verifyAndDecode(
        _ envelopeJSON: Data
    ) throws -> PassiveBluetoothExperimentOneVerifiedExport {
        try validateSchemaShape(envelopeJSON)

        let decoder = JSONDecoder()
        let wire = try decoder.decode(EnvelopeWire.self, from: envelopeJSON)
        guard wire.schemaVersion == currentSchemaVersion else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError
                .unsupportedSchemaVersion(wire.schemaVersion)
        }
        guard isLowercaseSHA256(wire.runtimeBuild.executableSHA256) else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError
                .invalidExecutableSHA256(wire.runtimeBuild.executableSHA256)
        }

        let manifest = try PassiveBluetoothStationaryCaptureManifestJSON.verifyCaptureBinding(
            manifestJSON: wire.stationaryManifestJSON,
            captureJSON: wire.captureJSON
        )
        guard manifest.schemaVersion == PassiveBluetoothStationaryCaptureManifest.currentSchemaVersion,
              manifest.experimentRecipeID == wire.recipeID,
              manifest.nembraBuildIdentifier == wire.runtimeBuild.buildIdentifier,
              manifest.nembraBuildInstanceID == wire.runtimeBuild.buildInstanceID,
              manifest.nembraBuildCommitSHA == wire.runtimeBuild.sourceCommitSHA else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.manifestProvenanceMismatch
        }

        let result = try replayCorrelation(wire.correlationEvidence)
        guard case let .singleRepeatableCandidate(target) = result.correlation.disposition else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.correlationNotUnique
        }
        guard manifest.sourceArtifact.selectedPeripheralIdentifier == target.uuidString else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.correlationDoesNotMatchManifest
        }
        guard let series = result.observationSnapshots.first?.observationSeriesIdentity.rawValue,
              result.observationSnapshots.allSatisfy({
                  $0.observationSeriesIdentity.rawValue == series
              }),
              manifest.experimentID == series else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.correlationDoesNotMatchManifest
        }

        return PassiveBluetoothExperimentOneVerifiedExport(
            captureJSON: wire.captureJSON,
            stationaryManifest: manifest,
            powerCycleResult: result,
            recipeID: wire.recipeID,
            buildIdentifier: wire.runtimeBuild.buildIdentifier,
            buildInstanceID: wire.runtimeBuild.buildInstanceID,
            sourceCommitSHA: wire.runtimeBuild.sourceCommitSHA,
            executableSHA256: wire.runtimeBuild.executableSHA256
        )
    }

    package static func make(
        captureJSON: Data,
        powerCycleResult: PassiveBluetoothPowerCycleObservationResult,
        setup: PassiveBluetoothStationaryCaptureSetup,
        buildIdentity: PassiveBluetoothCaptureRuntimeBuildIdentity,
        preparedAt: Date = Date()
    ) throws -> Data {
        guard case let .singleRepeatableCandidate(target) = powerCycleResult.correlation.disposition,
              let series = powerCycleResult.observationSnapshots.first?.observationSeriesIdentity.rawValue,
              powerCycleResult.observationSnapshots.allSatisfy({
                  $0.observationSeriesIdentity.rawValue == series
              }) else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.correlationNotUnique
        }

        let manifest = try PassiveBluetoothStationaryCaptureManifestBuilder.make(
            captureJSON: captureJSON,
            experimentID: series,
            experimentRecipe: .es80FingerprintV1,
            preparedAt: preparedAt,
            nembraBuildIdentifier: buildIdentity.buildIdentifier,
            nembraBuildInstanceID: buildIdentity.buildInstanceID,
            nembraBuildCommitSHA: buildIdentity.sourceCommitSHA,
            selectedPeripheralIdentifier: target.uuidString,
            setup: setup
        )
        let manifestJSON = try PassiveBluetoothStationaryCaptureManifestJSON.encode(
            manifest,
            prettyPrinted: false
        )
        let correlation = CorrelationWire(powerCycleResult)
        let wire = EnvelopeWire(
            schemaVersion: currentSchemaVersion,
            recipeID: .es80FingerprintV1,
            captureJSON: captureJSON,
            stationaryManifestJSON: manifestJSON,
            runtimeBuild: .init(buildIdentity),
            correlationEvidence: correlation
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encoded = try encoder.encode(wire)

        // Do not emit a primary share artifact that this package cannot replay and cross-bind.
        let verified = try verifyAndDecode(encoded)
        guard verified.captureJSON == captureJSON,
              verified.powerCycleResult == powerCycleResult,
              verified.stationaryManifest == manifest else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.malformedCorrelationEvidence
        }
        return encoded
    }

    private static func replayCorrelation(
        _ wire: CorrelationWire
    ) throws -> PassiveBluetoothPowerCycleObservationResult {
        guard wire.windows.count == PassiveBluetoothPowerCycleObservationPhase.allCases.count,
              wire.observationSnapshots.count == PassiveBluetoothPowerCycleObservationPhase.allCases.count else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.malformedCorrelationEvidence
        }

        var receipts: [PassiveBluetoothPowerCycleObservationWindowReceipt] = []
        var snapshots: [PassiveBluetoothCandidateObservationSnapshot] = []
        for index in wire.windows.indices {
            let window = wire.windows[index]
            let snapshot = wire.observationSnapshots[index]
            guard let phase = PassiveBluetoothPowerCycleObservationPhase(rawValue: window.phaseRawValue),
                  phase.rawValue == index,
                  window.windowSequence == snapshot.windowSequence,
                  window.startedAtUptimeNanoseconds <= window.endedAtUptimeNanoseconds,
                  window.observedCandidateCount == snapshot.candidates.count else {
                throw PassiveBluetoothExperimentOneExportEnvelopeError.malformedCorrelationEvidence
            }

            let seriesIdentity = PassiveBluetoothCandidateObservationSeriesIdentity(
                rawValue: snapshot.observationSeriesIdentity
            )
            let sequence = PassiveBluetoothCandidateObservationWindowSequence(
                rawValue: snapshot.windowSequence
            )
            let candidates = snapshot.candidates.map {
                PassiveBluetoothCandidateObservationSnapshot.Candidate(
                    id: $0.identifier,
                    isConnectable: $0.isConnectable
                )
            }
            let reconstructed = try PassiveBluetoothCandidateObservationSnapshot(
                observationSeriesIdentity: seriesIdentity,
                windowSequence: sequence,
                candidates: candidates
            )
            receipts.append(
                PassiveBluetoothPowerCycleObservationWindowReceipt(
                    phase: phase,
                    windowSequence: sequence,
                    startedAtUptimeNanoseconds: window.startedAtUptimeNanoseconds,
                    endedAtUptimeNanoseconds: window.endedAtUptimeNanoseconds,
                    observedCandidateCount: window.observedCandidateCount
                )
            )
            snapshots.append(reconstructed)
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

    private static func validateSchemaShape(_ data: Data) throws {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        try rejectUnexpectedKeys(
            in: root,
            allowed: [
                "schemaVersion", "recipeID", "captureJSON", "stationaryManifestJSON",
                "runtimeBuild", "correlationEvidence",
            ],
            path: ""
        )
        if let build = root["runtimeBuild"] as? [String: Any] {
            try rejectUnexpectedKeys(
                in: build,
                allowed: [
                    "buildIdentifier", "buildInstanceID", "sourceCommitSHA", "executableSHA256",
                ],
                path: "runtimeBuild"
            )
        }
        if let correlation = root["correlationEvidence"] as? [String: Any] {
            try rejectUnexpectedKeys(
                in: correlation,
                allowed: ["windows", "observationSnapshots"],
                path: "correlationEvidence"
            )
            if let windows = correlation["windows"] as? [[String: Any]] {
                for (index, window) in windows.enumerated() {
                    try rejectUnexpectedKeys(
                        in: window,
                        allowed: [
                            "phaseRawValue", "windowSequence", "startedAtUptimeNanoseconds",
                            "endedAtUptimeNanoseconds", "observedCandidateCount",
                        ],
                        path: "correlationEvidence.windows[\(index)]"
                    )
                }
            }
            if let snapshots = correlation["observationSnapshots"] as? [[String: Any]] {
                for (index, snapshot) in snapshots.enumerated() {
                    try rejectUnexpectedKeys(
                        in: snapshot,
                        allowed: ["observationSeriesIdentity", "windowSequence", "candidates"],
                        path: "correlationEvidence.observationSnapshots[\(index)]"
                    )
                    if let candidates = snapshot["candidates"] as? [[String: Any]] {
                        for (candidateIndex, candidate) in candidates.enumerated() {
                            try rejectUnexpectedKeys(
                                in: candidate,
                                allowed: ["identifier", "isConnectable"],
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
            throw PassiveBluetoothExperimentOneExportEnvelopeError.unexpectedField(qualified)
        }
    }

    private static func isLowercaseSHA256(_ value: String) -> Bool {
        guard value.utf8.count == 64 else { return false }
        return value.utf8.allSatisfy { byte in
            (48...57).contains(byte) || (97...102).contains(byte)
        }
    }
}

private extension PassiveBluetoothExperimentOneExportEnvelopeJSON.BuildWire {
    init(_ identity: PassiveBluetoothCaptureRuntimeBuildIdentity) {
        buildIdentifier = identity.buildIdentifier
        buildInstanceID = identity.buildInstanceID
        sourceCommitSHA = identity.sourceCommitSHA
        executableSHA256 = identity.executableSHA256
    }
}

private extension PassiveBluetoothExperimentOneExportEnvelopeJSON.CorrelationWire {
    init(_ result: PassiveBluetoothPowerCycleObservationResult) {
        windows = result.windows.map {
            .init(
                phaseRawValue: $0.phase.rawValue,
                windowSequence: $0.windowSequence.rawValue,
                startedAtUptimeNanoseconds: $0.startedAtUptimeNanoseconds,
                endedAtUptimeNanoseconds: $0.endedAtUptimeNanoseconds,
                observedCandidateCount: $0.observedCandidateCount
            )
        }
        observationSnapshots = result.observationSnapshots.map { snapshot in
            .init(
                observationSeriesIdentity: snapshot.observationSeriesIdentity.rawValue,
                windowSequence: snapshot.windowSequence.rawValue,
                candidates: snapshot.candidates.map {
                    .init(identifier: $0.id, isConnectable: $0.isConnectable)
                }
            )
        }
    }
}