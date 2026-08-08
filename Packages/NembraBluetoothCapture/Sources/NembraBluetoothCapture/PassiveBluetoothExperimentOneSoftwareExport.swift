import Foundation

/// A package-owned, self-verifying software evidence envelope for ES80 Experiment One.
///
/// This envelope closes the gap between the coordinator's immutable capture bytes, the exact
/// four-window correlation evidence from that same run, the sealed recipe identifier, and the
/// running application's build provenance. It is deliberately named `SoftwareExport`: successful
/// construction or verification does not authorize a physical experiment and does not substitute
/// for an independently accepted external field-build / GO record.
public struct PassiveBluetoothExperimentOneSoftwareExport: Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let captureJSON: Data
    public let stationaryManifestJSON: Data
    public let experimentRecipeID: PassiveBluetoothExperimentRecipeID
    public let correlationWindows: [CorrelationWindow]
    public let build: Build

    public struct CorrelationWindow: Equatable, Sendable {
        public let phase: PassiveBluetoothPowerCycleObservationPhase
        public let windowSequence: UInt64
        public let startedAtUptimeNanoseconds: UInt64
        public let endedAtUptimeNanoseconds: UInt64
        public let candidates: [Candidate]

        public struct Candidate: Equatable, Sendable {
            public let peripheralIdentifier: UUID
            public let isConnectable: Bool?
        }
    }

    public struct Build: Equatable, Sendable {
        public let buildIdentifier: String
        public let buildInstanceID: String
        public let sourceCommitSHA: String
        public let executableSHA256: String
    }

    fileprivate init(
        schemaVersion: Int,
        captureJSON: Data,
        stationaryManifestJSON: Data,
        experimentRecipeID: PassiveBluetoothExperimentRecipeID,
        correlationWindows: [CorrelationWindow],
        build: Build
    ) {
        self.schemaVersion = schemaVersion
        self.captureJSON = captureJSON
        self.stationaryManifestJSON = stationaryManifestJSON
        self.experimentRecipeID = experimentRecipeID
        self.correlationWindows = correlationWindows
        self.build = build
    }
}

public enum PassiveBluetoothExperimentOneSoftwareExportError: Error, Equatable, Sendable {
    case artifactNotFinalized
    case correlationIncomplete
    case correlationEvidenceInvalid
    case correlationNotUnique
    case correlationWindowCount(Int)
    case correlationWindowPhaseMismatch(index: Int)
    case correlationWindowSequenceMismatch(index: Int)
    case correlationCandidateCountMismatch(index: Int)
    case unsupportedSchemaVersion(Int)
    case unsupportedRecipe(PassiveBluetoothExperimentRecipeID)
    case manifestRecipeMismatch
    case manifestBuildMismatch
    case manifestTargetMismatch
    case malformedWireData
    case unexpectedWireField(String)
}

/// Package-owned construction and verification for the software export envelope.
///
/// Setup values below are declarations of the required Experiment One procedure context. They are
/// not sensor attestations that the charger was physically disconnected or that the stock app was
/// actually closed. The physical run remains independently gated by the field-execution authority.
public enum PassiveBluetoothExperimentOneSoftwareExportCodec {
    public static func make(
        finalizedArtifact: PassiveBluetoothExperimentOneCoordinator.FinalizedArtifact,
        runtimeBuildIdentity: PassiveBluetoothCaptureRuntimeBuildIdentity
    ) throws -> PassiveBluetoothExperimentOneSoftwareExport {
        let result = finalizedArtifact.powerCycleResult
        guard result.windows.count == 4, result.observationSnapshots.count == 4 else {
            throw PassiveBluetoothExperimentOneSoftwareExportError
                .correlationWindowCount(min(result.windows.count, result.observationSnapshots.count))
        }

        let selectedTarget: UUID
        switch result.correlation.disposition {
        case .invalidObservationAuthority, .invalidObservationWindowOrder:
            throw PassiveBluetoothExperimentOneSoftwareExportError.correlationEvidenceInvalid
        case .noRepeatableCandidate, .ambiguousRepeatableCandidates:
            throw PassiveBluetoothExperimentOneSoftwareExportError.correlationNotUnique
        case let .singleRepeatableCandidate(identifier):
            selectedTarget = identifier
        }

        let windows = try makeCorrelationWindows(result)
        try validateCorrelationWindowChronology(windows)

        let manifest = try PassiveBluetoothStationaryCaptureManifestBuilder.make(
            captureJSON: finalizedArtifact.captureJSON,
            experimentRecipe: .es80FingerprintV1,
            nembraBuildIdentifier: runtimeBuildIdentity.buildIdentifier,
            nembraBuildInstanceID: runtimeBuildIdentity.buildInstanceID,
            nembraBuildCommitSHA: runtimeBuildIdentity.sourceCommitSHA,
            selectedPeripheralIdentifier: selectedTarget.uuidString,
            setup: .init(
                chargerState: .disconnected,
                executionContext: .foregroundUnlockedScreenOn,
                stockAppReferenceSetup: .none
            )
        )
        let manifestJSON = try PassiveBluetoothStationaryCaptureManifestJSON.encode(manifest)

        return .init(
            schemaVersion: PassiveBluetoothExperimentOneSoftwareExport.currentSchemaVersion,
            captureJSON: finalizedArtifact.captureJSON,
            stationaryManifestJSON: manifestJSON,
            experimentRecipeID: .es80FingerprintV1,
            correlationWindows: windows,
            build: .init(
                buildIdentifier: runtimeBuildIdentity.buildIdentifier,
                buildInstanceID: runtimeBuildIdentity.buildInstanceID,
                sourceCommitSHA: runtimeBuildIdentity.sourceCommitSHA,
                executableSHA256: runtimeBuildIdentity.executableSHA256
            )
        )
    }

    /// Current-app convenience. Runtime provenance is read mechanically from `Bundle.main`; the
    /// caller cannot type or replace build metadata.
    public static func makeForCurrentApplication(
        finalizedArtifact: PassiveBluetoothExperimentOneCoordinator.FinalizedArtifact
    ) throws -> PassiveBluetoothExperimentOneSoftwareExport {
        try make(
            finalizedArtifact: finalizedArtifact,
            runtimeBuildIdentity: PassiveBluetoothCaptureRuntimeBuildIdentityReader.currentApplication()
        )
    }

    public static func encode(
        _ export: PassiveBluetoothExperimentOneSoftwareExport,
        prettyPrinted: Bool = true
    ) throws -> Data {
        let wire = WireV1(
            schemaVersion: export.schemaVersion,
            experimentRecipeID: export.experimentRecipeID.rawValue,
            captureJSONBase64: export.captureJSON.base64EncodedString(),
            stationaryManifestJSONBase64: export.stationaryManifestJSON.base64EncodedString(),
            correlationWindows: export.correlationWindows.map(WireWindow.init),
            build: .init(export.build)
        )
        let encoder = JSONEncoder()
        if prettyPrinted { encoder.outputFormatting = [.prettyPrinted, .sortedKeys] }
        return try encoder.encode(wire)
    }

    public static func decodeAndVerify(_ data: Data) throws -> PassiveBluetoothExperimentOneSoftwareExport {
        try rejectUnexpectedWireFields(data)

        let wire: WireV1
        do {
            wire = try JSONDecoder().decode(WireV1.self, from: data)
        } catch {
            throw PassiveBluetoothExperimentOneSoftwareExportError.malformedWireData
        }

        guard wire.schemaVersion == PassiveBluetoothExperimentOneSoftwareExport.currentSchemaVersion else {
            throw PassiveBluetoothExperimentOneSoftwareExportError.unsupportedSchemaVersion(wire.schemaVersion)
        }
        guard let recipe = PassiveBluetoothExperimentRecipeID(rawValue: wire.experimentRecipeID) else {
            throw PassiveBluetoothExperimentOneSoftwareExportError.malformedWireData
        }
        guard recipe == .es80FingerprintV1 else {
            throw PassiveBluetoothExperimentOneSoftwareExportError.unsupportedRecipe(recipe)
        }
        guard let captureJSON = Data(base64Encoded: wire.captureJSONBase64),
              let manifestJSON = Data(base64Encoded: wire.stationaryManifestJSONBase64) else {
            throw PassiveBluetoothExperimentOneSoftwareExportError.malformedWireData
        }
        guard wire.correlationWindows.count == PassiveBluetoothPowerCycleObservationPhase.allCases.count else {
            throw PassiveBluetoothExperimentOneSoftwareExportError
                .correlationWindowCount(wire.correlationWindows.count)
        }

        let windows = try wire.correlationWindows.enumerated().map { index, item in
            try decodedWindow(item, index: index)
        }
        try validateCorrelationWindowChronology(windows)

        let snapshots = try makeSnapshots(windows)
        let replayed = PassiveBluetoothPowerCycleTargetCorrelation.assess(
            firstOff: snapshots[0],
            firstOn: snapshots[1],
            secondOff: snapshots[2],
            secondOn: snapshots[3]
        )
        let selectedTarget: UUID
        switch replayed.disposition {
        case let .singleRepeatableCandidate(identifier):
            selectedTarget = identifier
        case .invalidObservationAuthority, .invalidObservationWindowOrder:
            throw PassiveBluetoothExperimentOneSoftwareExportError.correlationEvidenceInvalid
        case .noRepeatableCandidate, .ambiguousRepeatableCandidates:
            throw PassiveBluetoothExperimentOneSoftwareExportError.correlationNotUnique
        }

        let manifest = try PassiveBluetoothStationaryCaptureManifestJSON.verifyCaptureBinding(
            manifestJSON: manifestJSON,
            captureJSON: captureJSON
        )
        guard manifest.experimentRecipeID == recipe else {
            throw PassiveBluetoothExperimentOneSoftwareExportError.manifestRecipeMismatch
        }
        guard manifest.sourceArtifact.selectedPeripheralIdentifier == selectedTarget.uuidString else {
            throw PassiveBluetoothExperimentOneSoftwareExportError.manifestTargetMismatch
        }

        let build = try wire.build.decoded()
        guard manifest.nembraBuildIdentifier == build.buildIdentifier,
              manifest.nembraBuildInstanceID == build.buildInstanceID,
              manifest.nembraBuildCommitSHA == build.sourceCommitSHA else {
            throw PassiveBluetoothExperimentOneSoftwareExportError.manifestBuildMismatch
        }

        return .init(
            schemaVersion: wire.schemaVersion,
            captureJSON: captureJSON,
            stationaryManifestJSON: manifestJSON,
            experimentRecipeID: recipe,
            correlationWindows: windows,
            build: build
        )
    }

    private static func makeCorrelationWindows(
        _ result: PassiveBluetoothPowerCycleObservationResult
    ) throws -> [PassiveBluetoothExperimentOneSoftwareExport.CorrelationWindow] {
        try zip(result.windows, result.observationSnapshots).enumerated().map { index, pair in
            let (receipt, snapshot) = pair
            let expectedPhase = PassiveBluetoothPowerCycleObservationPhase(rawValue: index)
            guard receipt.phase == expectedPhase else {
                throw PassiveBluetoothExperimentOneSoftwareExportError
                    .correlationWindowPhaseMismatch(index: index)
            }
            guard receipt.windowSequence == snapshot.windowSequence,
                  receipt.windowSequence.rawValue == UInt64(index + 1) else {
                throw PassiveBluetoothExperimentOneSoftwareExportError
                    .correlationWindowSequenceMismatch(index: index)
            }
            guard receipt.observedCandidateCount == snapshot.candidates.count else {
                throw PassiveBluetoothExperimentOneSoftwareExportError
                    .correlationCandidateCountMismatch(index: index)
            }
            guard receipt.endedAtUptimeNanoseconds >= receipt.startedAtUptimeNanoseconds,
                  receipt.endedAtUptimeNanoseconds - receipt.startedAtUptimeNanoseconds >=
                    PassiveBluetoothExperimentOneCapturePolicy.minimumPowerCycleWindowDurationNanoseconds else {
                throw PassiveBluetoothExperimentOneSoftwareExportError.correlationEvidenceInvalid
            }
            return .init(
                phase: receipt.phase,
                windowSequence: receipt.windowSequence.rawValue,
                startedAtUptimeNanoseconds: receipt.startedAtUptimeNanoseconds,
                endedAtUptimeNanoseconds: receipt.endedAtUptimeNanoseconds,
                candidates: snapshot.candidates.map {
                    .init(peripheralIdentifier: $0.id, isConnectable: $0.isConnectable)
                }
            )
        }
    }

    private static func makeSnapshots(
        _ windows: [PassiveBluetoothExperimentOneSoftwareExport.CorrelationWindow]
    ) throws -> [PassiveBluetoothCandidateObservationSnapshot] {
        let authority = PassiveBluetoothCandidateObservationSeriesIdentity()
        return try windows.enumerated().map { index, window in
            let expectedPhase = PassiveBluetoothPowerCycleObservationPhase(rawValue: index)
            guard window.phase == expectedPhase else {
                throw PassiveBluetoothExperimentOneSoftwareExportError
                    .correlationWindowPhaseMismatch(index: index)
            }
            return try PassiveBluetoothCandidateObservationSnapshot(
                observationSeriesIdentity: authority,
                windowSequence: PassiveBluetoothCandidateObservationWindowSequence(
                    rawValue: window.windowSequence
                ),
                candidates: window.candidates.map {
                    .init(id: $0.peripheralIdentifier, isConnectable: $0.isConnectable)
                }
            )
        }
    }

    private static func decodedWindow(
        _ wire: WireWindow,
        index: Int
    ) throws -> PassiveBluetoothExperimentOneSoftwareExport.CorrelationWindow {
        guard let phase = PassiveBluetoothPowerCycleObservationPhase(rawValue: wire.phase),
              phase.rawValue == index else {
            throw PassiveBluetoothExperimentOneSoftwareExportError
                .correlationWindowPhaseMismatch(index: index)
        }
        guard wire.windowSequence == UInt64(index + 1) else {
            throw PassiveBluetoothExperimentOneSoftwareExportError
                .correlationWindowSequenceMismatch(index: index)
        }
        guard wire.endedAtUptimeNanoseconds >= wire.startedAtUptimeNanoseconds,
              wire.endedAtUptimeNanoseconds - wire.startedAtUptimeNanoseconds >=
                PassiveBluetoothExperimentOneCapturePolicy.minimumPowerCycleWindowDurationNanoseconds else {
            throw PassiveBluetoothExperimentOneSoftwareExportError.correlationEvidenceInvalid
        }

        let candidates: [PassiveBluetoothExperimentOneSoftwareExport.CorrelationWindow.Candidate]
        do {
            candidates = try wire.candidates.map { candidate in
                guard let id = UUID(uuidString: candidate.peripheralIdentifier),
                      id.uuidString == candidate.peripheralIdentifier else {
                    throw PassiveBluetoothExperimentOneSoftwareExportError.malformedWireData
                }
                return .init(peripheralIdentifier: id, isConnectable: candidate.isConnectable)
            }
        } catch let error as PassiveBluetoothExperimentOneSoftwareExportError {
            throw error
        }

        return .init(
            phase: phase,
            windowSequence: wire.windowSequence,
            startedAtUptimeNanoseconds: wire.startedAtUptimeNanoseconds,
            endedAtUptimeNanoseconds: wire.endedAtUptimeNanoseconds,
            candidates: candidates
        )
    }

    private static func validateCorrelationWindowChronology(
        _ windows: [PassiveBluetoothExperimentOneSoftwareExport.CorrelationWindow]
    ) throws {
        for index in windows.indices.dropFirst() {
            guard windows[index].startedAtUptimeNanoseconds >=
                    windows[index - 1].endedAtUptimeNanoseconds else {
                throw PassiveBluetoothExperimentOneSoftwareExportError.correlationEvidenceInvalid
            }
        }
    }

    /// The envelope is a closed-world evidence format at every object level. Codable otherwise
    /// ignores unknown nested keys, which could allow an injected authority-looking field to survive
    /// verification even though it was never produced or interpreted by Nembra.
    private static func rejectUnexpectedWireFields(_ data: Data) throws {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PassiveBluetoothExperimentOneSoftwareExportError.malformedWireData
        }

        try rejectUnexpectedKeys(
            in: object,
            allowed: [
                "schemaVersion", "experimentRecipeID", "captureJSONBase64",
                "stationaryManifestJSONBase64", "correlationWindows", "build"
            ],
            path: ""
        )

        guard let windows = object["correlationWindows"] as? [[String: Any]],
              let build = object["build"] as? [String: Any] else {
            throw PassiveBluetoothExperimentOneSoftwareExportError.malformedWireData
        }

        try rejectUnexpectedKeys(
            in: build,
            allowed: ["buildIdentifier", "buildInstanceID", "sourceCommitSHA", "executableSHA256"],
            path: "build"
        )

        for (windowIndex, window) in windows.enumerated() {
            let windowPath = "correlationWindows[\(windowIndex)]"
            try rejectUnexpectedKeys(
                in: window,
                allowed: [
                    "phase", "windowSequence", "startedAtUptimeNanoseconds",
                    "endedAtUptimeNanoseconds", "candidates"
                ],
                path: windowPath
            )
            guard let candidates = window["candidates"] as? [[String: Any]] else {
                throw PassiveBluetoothExperimentOneSoftwareExportError.malformedWireData
            }
            for (candidateIndex, candidate) in candidates.enumerated() {
                try rejectUnexpectedKeys(
                    in: candidate,
                    allowed: ["peripheralIdentifier", "isConnectable"],
                    path: "\(windowPath).candidates[\(candidateIndex)]"
                )
            }
        }
    }

    private static func rejectUnexpectedKeys(
        in object: [String: Any],
        allowed: Set<String>,
        path: String
    ) throws {
        if let key = object.keys.sorted().first(where: { !allowed.contains($0) }) {
            let qualified = path.isEmpty ? key : "\(path).\(key)"
            throw PassiveBluetoothExperimentOneSoftwareExportError.unexpectedWireField(qualified)
        }
    }

    private struct WireV1: Codable {
        let schemaVersion: Int
        let experimentRecipeID: String
        let captureJSONBase64: String
        let stationaryManifestJSONBase64: String
        let correlationWindows: [WireWindow]
        let build: WireBuild
    }

    private struct WireWindow: Codable {
        let phase: Int
        let windowSequence: UInt64
        let startedAtUptimeNanoseconds: UInt64
        let endedAtUptimeNanoseconds: UInt64
        let candidates: [WireCandidate]

        init(_ source: PassiveBluetoothExperimentOneSoftwareExport.CorrelationWindow) {
            phase = source.phase.rawValue
            windowSequence = source.windowSequence
            startedAtUptimeNanoseconds = source.startedAtUptimeNanoseconds
            endedAtUptimeNanoseconds = source.endedAtUptimeNanoseconds
            candidates = source.candidates.map(WireCandidate.init)
        }
    }

    private struct WireCandidate: Codable {
        let peripheralIdentifier: String
        let isConnectable: Bool?

        init(_ source: PassiveBluetoothExperimentOneSoftwareExport.CorrelationWindow.Candidate) {
            peripheralIdentifier = source.peripheralIdentifier.uuidString
            isConnectable = source.isConnectable
        }
    }

    private struct WireBuild: Codable {
        let buildIdentifier: String
        let buildInstanceID: String
        let sourceCommitSHA: String
        let executableSHA256: String

        init(_ source: PassiveBluetoothExperimentOneSoftwareExport.Build) {
            buildIdentifier = source.buildIdentifier
            buildInstanceID = source.buildInstanceID
            sourceCommitSHA = source.sourceCommitSHA
            executableSHA256 = source.executableSHA256
        }

        func decoded() throws -> PassiveBluetoothExperimentOneSoftwareExport.Build {
            guard PassiveBluetoothCaptureRuntimeBuildIdentityReader
                    .normalizedBuildInstanceID(buildInstanceID) == buildInstanceID,
                  PassiveBluetoothCaptureRuntimeBuildIdentityReader
                    .normalizedFullGitCommitSHA(sourceCommitSHA) == sourceCommitSHA,
                  executableSHA256.count == 64,
                  executableSHA256.utf8.allSatisfy({ byte in
                      (48...57).contains(byte) || (97...102).contains(byte)
                  }),
                  !buildIdentifier.isEmpty,
                  buildIdentifier == buildIdentifier.trimmingCharacters(in: .whitespacesAndNewlines) else {
                throw PassiveBluetoothExperimentOneSoftwareExportError.malformedWireData
            }
            return .init(
                buildIdentifier: buildIdentifier,
                buildInstanceID: buildInstanceID,
                sourceCommitSHA: sourceCommitSHA,
                executableSHA256: executableSHA256
            )
        }
    }
}

public extension PassiveBluetoothExperimentOneCoordinator {
    /// Produces the complete software-evidence envelope only after immutable Horizon finalization.
    /// This method does not unlock or imply physical GO; external build acceptance remains separate.
    func finalizedSoftwareExportForCurrentApplication()
        throws -> PassiveBluetoothExperimentOneSoftwareExport {
        guard let finalizedArtifact else {
            throw PassiveBluetoothExperimentOneSoftwareExportError.artifactNotFinalized
        }
        return try PassiveBluetoothExperimentOneSoftwareExportCodec.makeForCurrentApplication(
            finalizedArtifact: finalizedArtifact
        )
    }

    func encodedFinalizedSoftwareExportForCurrentApplication(prettyPrinted: Bool = true) throws -> Data {
        try PassiveBluetoothExperimentOneSoftwareExportCodec.encode(
            finalizedSoftwareExportForCurrentApplication(),
            prettyPrinted: prettyPrinted
        )
    }
}
