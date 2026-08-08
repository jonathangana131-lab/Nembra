import Foundation

/// One package-owned export envelope for the immutable ES80 Experiment One evidence life.
///
/// The envelope binds the exact sealed controller JSON bytes to the same package-produced
/// four-window correlation result, the stationary manifest, and the runtime build identity.
/// It deliberately carries `fieldAuthorizationStatus == .notAttached` until a separate accepted
/// build/GO authority is mechanically attached by a future schema. Possessing or decoding this
/// envelope therefore never authorizes a physical field procedure by itself.
public struct PassiveBluetoothExperimentOneExportEnvelope: Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public enum FieldAuthorizationStatus: String, Codable, Sendable {
        /// No independent accepted field-build/GO record is attached to this artifact.
        case notAttached = "not-attached"
    }

    public struct RuntimeBuild: Equatable, Sendable {
        public let buildIdentifier: String
        public let buildInstanceID: String
        public let sourceCommitSHA: String
        public let executableSHA256: String
    }

    public let schemaVersion: Int
    public let experimentRecipeID: PassiveBluetoothExperimentRecipeID
    public let fieldAuthorizationStatus: FieldAuthorizationStatus
    public let runtimeBuild: RuntimeBuild
    public let captureJSON: Data
    public let stationaryManifestJSON: Data
    public let selectedPeripheralIdentifier: UUID
    public let observationSeriesIdentity: UUID
    public let observationWindowCount: Int

    fileprivate init(
        schemaVersion: Int,
        experimentRecipeID: PassiveBluetoothExperimentRecipeID,
        fieldAuthorizationStatus: FieldAuthorizationStatus,
        runtimeBuild: RuntimeBuild,
        captureJSON: Data,
        stationaryManifestJSON: Data,
        selectedPeripheralIdentifier: UUID,
        observationSeriesIdentity: UUID,
        observationWindowCount: Int
    ) {
        self.schemaVersion = schemaVersion
        self.experimentRecipeID = experimentRecipeID
        self.fieldAuthorizationStatus = fieldAuthorizationStatus
        self.runtimeBuild = runtimeBuild
        self.captureJSON = captureJSON
        self.stationaryManifestJSON = stationaryManifestJSON
        self.selectedPeripheralIdentifier = selectedPeripheralIdentifier
        self.observationSeriesIdentity = observationSeriesIdentity
        self.observationWindowCount = observationWindowCount
    }
}

public enum PassiveBluetoothExperimentOneExportEnvelopeError: Error, Equatable, Sendable {
    case invalidPowerCycleEvidence
    case correlationNotUnique
    case correlationDoesNotMatchSnapshots
    case unsupportedSchemaVersion(Int)
    case unsupportedRecipe(PassiveBluetoothExperimentRecipeID)
    case fieldAuthorizationUnexpected
    case invalidRuntimeExecutableSHA256(String)
    case manifestBuildMismatch
    case manifestRecipeMismatch
    case manifestTargetMismatch
    case unexpectedEnvelopeField(String)
    case malformedEnvelope
}

/// Package-owned producer for the complete software evidence envelope.
///
/// Public callers cannot supply raw correlation catalogs, a selected UUID, arbitrary build metadata,
/// or mutable recorder state. The only public producer accepts the coordinator's sealed artifact and
/// a runtime identity returned by `PassiveBluetoothCaptureRuntimeBuildIdentityReader`.
public enum PassiveBluetoothExperimentOneExportEnvelopeBuilder {
    public static func make(
        finalizedArtifact: PassiveBluetoothExperimentOneCoordinator.FinalizedArtifact,
        runtimeBuildIdentity: PassiveBluetoothCaptureRuntimeBuildIdentity,
        preparedAt: Date = Date(),
        setup: PassiveBluetoothStationaryCaptureSetup
    ) throws -> Data {
        try make(
            captureJSON: finalizedArtifact.captureJSON,
            powerCycleResult: finalizedArtifact.powerCycleResult,
            runtimeBuildIdentity: runtimeBuildIdentity,
            preparedAt: preparedAt,
            setup: setup
        )
    }

    /// Package-only seam for deterministic tests. App/UI consumers cannot replace coordinator-owned
    /// evidence with caller-constructed snapshots or detached controller bytes.
    package static func make(
        captureJSON: Data,
        powerCycleResult: PassiveBluetoothPowerCycleObservationResult,
        runtimeBuildIdentity: PassiveBluetoothCaptureRuntimeBuildIdentity,
        preparedAt: Date,
        setup: PassiveBluetoothStationaryCaptureSetup
    ) throws -> Data {
        let validated = try validate(powerCycleResult: powerCycleResult)

        let manifest = try PassiveBluetoothStationaryCaptureManifestBuilder.make(
            captureJSON: captureJSON,
            experimentRecipe: .es80FingerprintV1,
            preparedAt: preparedAt,
            nembraBuildIdentifier: runtimeBuildIdentity.buildIdentifier,
            nembraBuildInstanceID: runtimeBuildIdentity.buildInstanceID,
            nembraBuildCommitSHA: runtimeBuildIdentity.sourceCommitSHA,
            selectedPeripheralIdentifier: validated.selectedPeripheralIdentifier.uuidString,
            setup: setup
        )
        let manifestJSON = try PassiveBluetoothStationaryCaptureManifestJSON.encode(
            manifest,
            prettyPrinted: false
        )

        let wire = Wire(
            schemaVersion: PassiveBluetoothExperimentOneExportEnvelope.currentSchemaVersion,
            experimentRecipeID: .es80FingerprintV1,
            fieldAuthorizationStatus: .notAttached,
            runtimeBuild: .init(runtimeBuildIdentity),
            captureJSON: captureJSON,
            stationaryManifestJSON: manifestJSON,
            correlation: .init(
                selectedPeripheralIdentifier: validated.selectedPeripheralIdentifier,
                observationSeriesIdentity: validated.observationSeriesIdentity,
                windows: validated.windows
            )
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(wire)
    }

    private struct ValidatedPowerCycleEvidence {
        let selectedPeripheralIdentifier: UUID
        let observationSeriesIdentity: UUID
        let windows: [WindowWire]
    }

    private static func validate(
        powerCycleResult: PassiveBluetoothPowerCycleObservationResult
    ) throws -> ValidatedPowerCycleEvidence {
        let receipts = powerCycleResult.windows
        let snapshots = powerCycleResult.observationSnapshots
        guard receipts.count == 4, snapshots.count == 4 else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.invalidPowerCycleEvidence
        }

        let recomputed = PassiveBluetoothPowerCycleTargetCorrelation.assess(
            firstOff: snapshots[0],
            firstOn: snapshots[1],
            secondOff: snapshots[2],
            secondOn: snapshots[3]
        )
        guard recomputed == powerCycleResult.correlation else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.correlationDoesNotMatchSnapshots
        }
        guard case let .singleRepeatableCandidate(selectedPeripheralIdentifier) = recomputed.disposition else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.correlationNotUnique
        }

        let seriesIdentity = snapshots[0].observationSeriesIdentity
        guard snapshots.allSatisfy({ $0.observationSeriesIdentity == seriesIdentity }) else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.invalidPowerCycleEvidence
        }

        var windows: [WindowWire] = []
        for index in 0..<4 {
            let receipt = receipts[index]
            let snapshot = snapshots[index]
            guard receipt.phase.rawValue == index,
                  receipt.windowSequence == snapshot.windowSequence,
                  receipt.observedCandidateCount == snapshot.candidates.count,
                  receipt.endedAtUptimeNanoseconds >= receipt.startedAtUptimeNanoseconds else {
                throw PassiveBluetoothExperimentOneExportEnvelopeError.invalidPowerCycleEvidence
            }
            windows.append(.init(receipt: receipt, snapshot: snapshot))
        }

        return .init(
            selectedPeripheralIdentifier: selectedPeripheralIdentifier,
            observationSeriesIdentity: seriesIdentity.rawValue,
            windows: windows
        )
    }
}

/// Closed-world codec and verifier for the package-owned envelope.
///
/// Verification replays the four-window correlation assessor and the stationary-manifest capture
/// binding from the exact embedded bytes. It does not convert software evidence into physical
/// identity, RF completeness, protocol meaning, telemetry, command acknowledgement, or GO authority.
public enum PassiveBluetoothExperimentOneExportEnvelopeJSON {
    public static func verifyAndDecode(
        _ envelopeJSON: Data
    ) throws -> PassiveBluetoothExperimentOneExportEnvelope {
        try validateSchemaShape(envelopeJSON)

        let decoder = JSONDecoder()
        let wire: Wire
        do {
            wire = try decoder.decode(Wire.self, from: envelopeJSON)
        } catch {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.malformedEnvelope
        }

        guard wire.schemaVersion == PassiveBluetoothExperimentOneExportEnvelope.currentSchemaVersion else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError
                .unsupportedSchemaVersion(wire.schemaVersion)
        }
        guard wire.experimentRecipeID == .es80FingerprintV1 else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError
                .unsupportedRecipe(wire.experimentRecipeID)
        }
        guard wire.fieldAuthorizationStatus == .notAttached else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.fieldAuthorizationUnexpected
        }
        guard isCanonicalSHA256(wire.runtimeBuild.executableSHA256) else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError
                .invalidRuntimeExecutableSHA256(wire.runtimeBuild.executableSHA256)
        }

        let manifest = try PassiveBluetoothStationaryCaptureManifestJSON.verifyCaptureBinding(
            manifestJSON: wire.stationaryManifestJSON,
            captureJSON: wire.captureJSON
        )
        guard manifest.experimentRecipeID == wire.experimentRecipeID else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.manifestRecipeMismatch
        }
        guard manifest.nembraBuildIdentifier == wire.runtimeBuild.buildIdentifier,
              manifest.nembraBuildInstanceID == wire.runtimeBuild.buildInstanceID,
              manifest.nembraBuildCommitSHA == wire.runtimeBuild.sourceCommitSHA else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.manifestBuildMismatch
        }

        let correlation = try verifiedCorrelation(wire.correlation)
        guard manifest.sourceArtifact.selectedPeripheralIdentifier ==
                correlation.selectedPeripheralIdentifier.uuidString else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.manifestTargetMismatch
        }

        return PassiveBluetoothExperimentOneExportEnvelope(
            schemaVersion: wire.schemaVersion,
            experimentRecipeID: wire.experimentRecipeID,
            fieldAuthorizationStatus: wire.fieldAuthorizationStatus,
            runtimeBuild: .init(
                buildIdentifier: wire.runtimeBuild.buildIdentifier,
                buildInstanceID: wire.runtimeBuild.buildInstanceID,
                sourceCommitSHA: wire.runtimeBuild.sourceCommitSHA,
                executableSHA256: wire.runtimeBuild.executableSHA256
            ),
            captureJSON: wire.captureJSON,
            stationaryManifestJSON: wire.stationaryManifestJSON,
            selectedPeripheralIdentifier: correlation.selectedPeripheralIdentifier,
            observationSeriesIdentity: wire.correlation.observationSeriesIdentity,
            observationWindowCount: wire.correlation.windows.count
        )
    }

    private struct VerifiedCorrelation {
        let selectedPeripheralIdentifier: UUID
    }

    private static func verifiedCorrelation(
        _ wire: CorrelationWire
    ) throws -> VerifiedCorrelation {
        guard wire.windows.count == 4 else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.invalidPowerCycleEvidence
        }

        let seriesIdentity = PassiveBluetoothCandidateObservationSeriesIdentity(
            rawValue: wire.observationSeriesIdentity
        )
        var snapshots: [PassiveBluetoothCandidateObservationSnapshot] = []

        for index in 0..<4 {
            let window = wire.windows[index]
            guard window.phase == index,
                  window.endedAtUptimeNanoseconds >= window.startedAtUptimeNanoseconds,
                  window.observedCandidateCount == window.candidates.count else {
                throw PassiveBluetoothExperimentOneExportEnvelopeError.invalidPowerCycleEvidence
            }

            let sequence = PassiveBluetoothCandidateObservationWindowSequence(
                rawValue: window.windowSequence
            )
            let candidates = window.candidates.map {
                PassiveBluetoothCandidateObservationSnapshot.Candidate(
                    id: $0.id,
                    isConnectable: $0.isConnectable
                )
            }
            let snapshot: PassiveBluetoothCandidateObservationSnapshot
            do {
                snapshot = try PassiveBluetoothCandidateObservationSnapshot(
                    observationSeriesIdentity: seriesIdentity,
                    windowSequence: sequence,
                    candidates: candidates
                )
            } catch {
                throw PassiveBluetoothExperimentOneExportEnvelopeError.invalidPowerCycleEvidence
            }
            snapshots.append(snapshot)
        }

        let recomputed = PassiveBluetoothPowerCycleTargetCorrelation.assess(
            firstOff: snapshots[0],
            firstOn: snapshots[1],
            secondOff: snapshots[2],
            secondOn: snapshots[3]
        )
        guard case let .singleRepeatableCandidate(selected) = recomputed.disposition,
              selected == wire.selectedPeripheralIdentifier else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.correlationNotUnique
        }

        return .init(selectedPeripheralIdentifier: selected)
    }

    private static func isCanonicalSHA256(_ value: String) -> Bool {
        guard value.utf8.count == 64 else { return false }
        return value.utf8.allSatisfy { byte in
            (48...57).contains(byte) || (97...102).contains(byte)
        }
    }

    private static func validateSchemaShape(_ data: Data) throws {
        let rootObject: Any
        do {
            rootObject = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.malformedEnvelope
        }
        guard let root = rootObject as? [String: Any] else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.malformedEnvelope
        }

        try rejectUnexpectedKeys(
            in: root,
            allowed: [
                "schemaVersion", "experimentRecipeID", "fieldAuthorizationStatus",
                "runtimeBuild", "captureJSON", "stationaryManifestJSON", "correlation",
            ],
            path: ""
        )

        if let runtime = root["runtimeBuild"] as? [String: Any] {
            try rejectUnexpectedKeys(
                in: runtime,
                allowed: ["buildIdentifier", "buildInstanceID", "sourceCommitSHA", "executableSHA256"],
                path: "runtimeBuild"
            )
        }
        if let correlation = root["correlation"] as? [String: Any] {
            try rejectUnexpectedKeys(
                in: correlation,
                allowed: ["selectedPeripheralIdentifier", "observationSeriesIdentity", "windows"],
                path: "correlation"
            )
            if let windows = correlation["windows"] as? [[String: Any]] {
                for (windowIndex, window) in windows.enumerated() {
                    try rejectUnexpectedKeys(
                        in: window,
                        allowed: [
                            "phase", "windowSequence", "startedAtUptimeNanoseconds",
                            "endedAtUptimeNanoseconds", "observedCandidateCount", "candidates",
                        ],
                        path: "correlation.windows[\(windowIndex)]"
                    )
                    if let candidates = window["candidates"] as? [[String: Any]] {
                        for (candidateIndex, candidate) in candidates.enumerated() {
                            try rejectUnexpectedKeys(
                                in: candidate,
                                allowed: ["id", "isConnectable"],
                                path: "correlation.windows[\(windowIndex)].candidates[\(candidateIndex)]"
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
            throw PassiveBluetoothExperimentOneExportEnvelopeError.unexpectedEnvelopeField(qualified)
        }
    }
}

private struct Wire: Codable {
    let schemaVersion: Int
    let experimentRecipeID: PassiveBluetoothExperimentRecipeID
    let fieldAuthorizationStatus: PassiveBluetoothExperimentOneExportEnvelope.FieldAuthorizationStatus
    let runtimeBuild: RuntimeBuildWire
    let captureJSON: Data
    let stationaryManifestJSON: Data
    let correlation: CorrelationWire
}

private struct RuntimeBuildWire: Codable {
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

private struct CorrelationWire: Codable {
    let selectedPeripheralIdentifier: UUID
    let observationSeriesIdentity: UUID
    let windows: [WindowWire]
}

private struct WindowWire: Codable {
    let phase: Int
    let windowSequence: UInt64
    let startedAtUptimeNanoseconds: UInt64
    let endedAtUptimeNanoseconds: UInt64
    let observedCandidateCount: Int
    let candidates: [CandidateWire]

    init(
        receipt: PassiveBluetoothPowerCycleObservationWindowReceipt,
        snapshot: PassiveBluetoothCandidateObservationSnapshot
    ) {
        phase = receipt.phase.rawValue
        windowSequence = receipt.windowSequence.rawValue
        startedAtUptimeNanoseconds = receipt.startedAtUptimeNanoseconds
        endedAtUptimeNanoseconds = receipt.endedAtUptimeNanoseconds
        observedCandidateCount = receipt.observedCandidateCount
        candidates = snapshot.candidates.map(CandidateWire.init)
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
