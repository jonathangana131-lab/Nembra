import Foundation

/// Package-owned software evidence for one sealed ES80 Experiment One run.
///
/// This object binds immutable capture bytes, replayable four-window correlation evidence,
/// the sealed recipe, stationary-manifest provenance, and the running build identity. It is
/// deliberately software evidence only: neither successful construction nor verification is
/// physical field authorization, and an independent accepted field-build / GO record remains
/// required before a physical experiment may run.
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
        public let observationSeriesIdentity: UUID
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
    case correlationEvidenceInvalid
    case correlationNotUnique
    case correlationWindowCount(Int)
    case correlationWindowPhaseMismatch(index: Int)
    case correlationWindowSequenceMismatch(index: Int)
    case correlationCandidateCountMismatch(index: Int)
    case experimentEvidenceNotStructurallyCoherent
    case unsupportedSchemaVersion(Int)
    case unsupportedRecipe(PassiveBluetoothExperimentRecipeID)
    case manifestRecipeMismatch
    case manifestBuildMismatch
    case manifestTargetMismatch
    case malformedWireData
    case unexpectedWireField(String)
    case duplicateWireField(String)
}

public enum PassiveBluetoothExperimentOneSoftwareExportCodec {
    public static func make(
        finalizedArtifact: PassiveBluetoothExperimentOneCoordinator.FinalizedArtifact,
        runtimeBuildIdentity: PassiveBluetoothCaptureRuntimeBuildIdentity,
        setup: PassiveBluetoothStationaryCaptureSetup
    ) throws -> PassiveBluetoothExperimentOneSoftwareExport {
        try make(
            captureJSON: finalizedArtifact.captureJSON,
            powerCycleResult: finalizedArtifact.powerCycleResult,
            runtimeBuildIdentity: runtimeBuildIdentity,
            setup: setup
        )
    }

    /// Package-scoped deterministic seam for executable package tests. Production app clients cannot
    /// inject a detached correlation result or arbitrary build identity through this API.
    package static func make(
        captureJSON: Data,
        powerCycleResult: PassiveBluetoothPowerCycleObservationResult,
        runtimeBuildIdentity: PassiveBluetoothCaptureRuntimeBuildIdentity,
        setup: PassiveBluetoothStationaryCaptureSetup
    ) throws -> PassiveBluetoothExperimentOneSoftwareExport {
        guard powerCycleResult.windows.count == 4,
              powerCycleResult.observationSnapshots.count == 4 else {
            throw PassiveBluetoothExperimentOneSoftwareExportError.correlationWindowCount(
                min(powerCycleResult.windows.count, powerCycleResult.observationSnapshots.count)
            )
        }

        let windows = try makeCorrelationWindows(powerCycleResult)
        let replayed = try replayCorrelation(windows)
        let selectedTarget: UUID
        switch replayed.disposition {
        case .invalidObservationAuthority, .invalidObservationWindowOrder:
            throw PassiveBluetoothExperimentOneSoftwareExportError.correlationEvidenceInvalid
        case .noRepeatableCandidate, .ambiguousRepeatableCandidates:
            throw PassiveBluetoothExperimentOneSoftwareExportError.correlationNotUnique
        case let .singleRepeatableCandidate(identifier):
            selectedTarget = identifier
        }
        guard replayed == powerCycleResult.correlation else {
            throw PassiveBluetoothExperimentOneSoftwareExportError.correlationEvidenceInvalid
        }

        let structuralTarget = try structurallyCoherentTarget(
            captureJSON: captureJSON,
            powerCycleResult: powerCycleResult
        )
        guard structuralTarget == selectedTarget else {
            throw PassiveBluetoothExperimentOneSoftwareExportError.correlationEvidenceInvalid
        }

        let manifest = try PassiveBluetoothStationaryCaptureManifestBuilder.make(
            captureJSON: captureJSON,
            experimentRecipe: .es80FingerprintV1,
            nembraBuildIdentifier: runtimeBuildIdentity.buildIdentifier,
            nembraBuildInstanceID: runtimeBuildIdentity.buildInstanceID,
            nembraBuildCommitSHA: runtimeBuildIdentity.sourceCommitSHA,
            selectedPeripheralIdentifier: structuralTarget.uuidString,
            setup: setup
        )
        let manifestJSON = try PassiveBluetoothStationaryCaptureManifestJSON.encode(manifest)

        return .init(
            schemaVersion: PassiveBluetoothExperimentOneSoftwareExport.currentSchemaVersion,
            captureJSON: captureJSON,
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

    public static func makeForCurrentApplication(
        finalizedArtifact: PassiveBluetoothExperimentOneCoordinator.FinalizedArtifact,
        setup: PassiveBluetoothStationaryCaptureSetup
    ) throws -> PassiveBluetoothExperimentOneSoftwareExport {
        try make(
            finalizedArtifact: finalizedArtifact,
            runtimeBuildIdentity: PassiveBluetoothCaptureRuntimeBuildIdentityReader.currentApplication(),
            setup: setup
        )
    }

    public static func encode(
        _ export: PassiveBluetoothExperimentOneSoftwareExport,
        prettyPrinted: Bool = true
    ) throws -> Data {
        let encoder = JSONEncoder()
        if prettyPrinted { encoder.outputFormatting = [.prettyPrinted, .sortedKeys] }
        return try encoder.encode(WireV1(export))
    }

    public static func decodeAndVerify(_ data: Data) throws -> PassiveBluetoothExperimentOneSoftwareExport {
        try validateClosedWorldShape(data)

        let decoder = JSONDecoder()
        let wire: WireV1
        do {
            wire = try decoder.decode(WireV1.self, from: data)
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
        guard wire.correlationWindows.count == 4 else {
            throw PassiveBluetoothExperimentOneSoftwareExportError
                .correlationWindowCount(wire.correlationWindows.count)
        }

        let windows = try wire.correlationWindows.enumerated().map { index, item in
            try decodedWindow(item, index: index)
        }
        let replayed = try replayCorrelation(windows)
        let selectedTarget: UUID
        switch replayed.disposition {
        case let .singleRepeatableCandidate(identifier):
            selectedTarget = identifier
        case .invalidObservationAuthority, .invalidObservationWindowOrder:
            throw PassiveBluetoothExperimentOneSoftwareExportError.correlationEvidenceInvalid
        case .noRepeatableCandidate, .ambiguousRepeatableCandidates:
            throw PassiveBluetoothExperimentOneSoftwareExportError.correlationNotUnique
        }

        let powerCycleResult = try reconstructedPowerCycleResult(
            windows: windows,
            correlation: replayed
        )
        let structuralTarget = try structurallyCoherentTarget(
            captureJSON: captureJSON,
            powerCycleResult: powerCycleResult
        )
        guard structuralTarget == selectedTarget else {
            throw PassiveBluetoothExperimentOneSoftwareExportError.correlationEvidenceInvalid
        }

        let manifest = try PassiveBluetoothStationaryCaptureManifestJSON.verifyCaptureBinding(
            manifestJSON: manifestJSON,
            captureJSON: captureJSON
        )
        guard manifest.experimentRecipeID == recipe else {
            throw PassiveBluetoothExperimentOneSoftwareExportError.manifestRecipeMismatch
        }
        guard manifest.sourceArtifact.selectedPeripheralIdentifier == structuralTarget.uuidString else {
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
            guard receipt.phase.rawValue == index else {
                throw PassiveBluetoothExperimentOneSoftwareExportError
                    .correlationWindowPhaseMismatch(index: index)
            }
            guard receipt.windowSequence == snapshot.windowSequence else {
                throw PassiveBluetoothExperimentOneSoftwareExportError
                    .correlationWindowSequenceMismatch(index: index)
            }
            guard receipt.observedCandidateCount == snapshot.candidates.count else {
                throw PassiveBluetoothExperimentOneSoftwareExportError
                    .correlationCandidateCountMismatch(index: index)
            }
            return .init(
                phase: receipt.phase,
                observationSeriesIdentity: snapshot.observationSeriesIdentity.rawValue,
                windowSequence: receipt.windowSequence.rawValue,
                startedAtUptimeNanoseconds: receipt.startedAtUptimeNanoseconds,
                endedAtUptimeNanoseconds: receipt.endedAtUptimeNanoseconds,
                candidates: snapshot.candidates.map {
                    .init(peripheralIdentifier: $0.id, isConnectable: $0.isConnectable)
                }
            )
        }
    }

    private static func replayCorrelation(
        _ windows: [PassiveBluetoothExperimentOneSoftwareExport.CorrelationWindow]
    ) throws -> PassiveBluetoothPowerCycleTargetCorrelationReport {
        let snapshots = try snapshots(from: windows)
        return PassiveBluetoothPowerCycleTargetCorrelation.assess(
            firstOff: snapshots[0],
            firstOn: snapshots[1],
            secondOff: snapshots[2],
            secondOn: snapshots[3]
        )
    }

    private static func reconstructedPowerCycleResult(
        windows: [PassiveBluetoothExperimentOneSoftwareExport.CorrelationWindow],
        correlation: PassiveBluetoothPowerCycleTargetCorrelationReport
    ) throws -> PassiveBluetoothPowerCycleObservationResult {
        let snapshots = try snapshots(from: windows)
        let receipts = windows.map { window in
            PassiveBluetoothPowerCycleObservationWindowReceipt(
                phase: window.phase,
                windowSequence: .init(rawValue: window.windowSequence),
                startedAtUptimeNanoseconds: window.startedAtUptimeNanoseconds,
                endedAtUptimeNanoseconds: window.endedAtUptimeNanoseconds,
                observedCandidateCount: window.candidates.count
            )
        }
        return PassiveBluetoothPowerCycleObservationResult(
            windows: receipts,
            observationSnapshots: snapshots,
            correlation: correlation
        )
    }

    private static func snapshots(
        from windows: [PassiveBluetoothExperimentOneSoftwareExport.CorrelationWindow]
    ) throws -> [PassiveBluetoothCandidateObservationSnapshot] {
        try windows.enumerated().map { index, window in
            guard window.phase.rawValue == index else {
                throw PassiveBluetoothExperimentOneSoftwareExportError
                    .correlationWindowPhaseMismatch(index: index)
            }
            return try PassiveBluetoothCandidateObservationSnapshot(
                observationSeriesIdentity: .init(rawValue: window.observationSeriesIdentity),
                windowSequence: .init(rawValue: window.windowSequence),
                candidates: window.candidates.map {
                    .init(id: $0.peripheralIdentifier, isConnectable: $0.isConnectable)
                }
            )
        }
    }

    private static func structurallyCoherentTarget(
        captureJSON: Data,
        powerCycleResult: PassiveBluetoothPowerCycleObservationResult
    ) throws -> UUID {
        let captureSession: PassiveBluetoothCaptureSession
        do {
            captureSession = try PassiveBluetoothCaptureJSON.decode(captureJSON)
        } catch {
            throw PassiveBluetoothExperimentOneSoftwareExportError
                .experimentEvidenceNotStructurallyCoherent
        }

        let assessment = PassiveBluetoothExperimentOneStructuralEvidenceAssessment.assess(
            powerCycleResult: powerCycleResult,
            captureSession: captureSession
        )
        guard case let .structurallyCoherent(target) = assessment.status else {
            throw PassiveBluetoothExperimentOneSoftwareExportError
                .experimentEvidenceNotStructurallyCoherent
        }
        return target
    }

    private static func decodedWindow(
        _ wire: WireWindow,
        index: Int
    ) throws -> PassiveBluetoothExperimentOneSoftwareExport.CorrelationWindow {
        guard let phase = PassiveBluetoothPowerCycleObservationPhase(rawValue: wire.phase),
              phase.rawValue == index,
              wire.endedAtUptimeNanoseconds >= wire.startedAtUptimeNanoseconds,
              let authority = canonicalUUID(wire.observationSeriesIdentity) else {
            throw PassiveBluetoothExperimentOneSoftwareExportError
                .correlationWindowPhaseMismatch(index: index)
        }
        let candidates = try wire.candidates.map { candidate in
            guard let id = canonicalUUID(candidate.peripheralIdentifier) else {
                throw PassiveBluetoothExperimentOneSoftwareExportError.malformedWireData
            }
            return PassiveBluetoothExperimentOneSoftwareExport.CorrelationWindow.Candidate(
                peripheralIdentifier: id,
                isConnectable: candidate.isConnectable
            )
        }
        return .init(
            phase: phase,
            observationSeriesIdentity: authority,
            windowSequence: wire.windowSequence,
            startedAtUptimeNanoseconds: wire.startedAtUptimeNanoseconds,
            endedAtUptimeNanoseconds: wire.endedAtUptimeNanoseconds,
            candidates: candidates
        )
    }

    private static func canonicalUUID(_ raw: String) -> UUID? {
        guard let parsed = UUID(uuidString: raw), parsed.uuidString == raw else { return nil }
        return parsed
    }

    private static func validateClosedWorldShape(_ data: Data) throws {
        if let duplicateKey = PassiveBluetoothStrictJSON.duplicateTopLevelObjectKey(in: data) {
            throw PassiveBluetoothExperimentOneSoftwareExportError.duplicateWireField(duplicateKey)
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PassiveBluetoothExperimentOneSoftwareExportError.malformedWireData
        }
        try rejectUnexpectedKeys(
            root,
            allowed: [
                "schemaVersion", "experimentRecipeID", "captureJSONBase64",
                "stationaryManifestJSONBase64", "correlationWindows", "build"
            ],
            path: ""
        )
        if let build = root["build"] as? [String: Any] {
            try rejectUnexpectedKeys(
                build,
                allowed: ["buildIdentifier", "buildInstanceID", "sourceCommitSHA", "executableSHA256"],
                path: "build"
            )
        }
        if let windows = root["correlationWindows"] as? [[String: Any]] {
            for (index, window) in windows.enumerated() {
                try rejectUnexpectedKeys(
                    window,
                    allowed: [
                        "phase", "observationSeriesIdentity", "windowSequence",
                        "startedAtUptimeNanoseconds", "endedAtUptimeNanoseconds", "candidates"
                    ],
                    path: "correlationWindows[\(index)]"
                )
                if let candidates = window["candidates"] as? [[String: Any]] {
                    for (candidateIndex, candidate) in candidates.enumerated() {
                        try rejectUnexpectedKeys(
                            candidate,
                            allowed: ["peripheralIdentifier", "isConnectable"],
                            path: "correlationWindows[\(index)].candidates[\(candidateIndex)]"
                        )
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
        if let unexpected = object.keys.sorted().first(where: { !allowed.contains($0) }) {
            let qualified = path.isEmpty ? unexpected : "\(path).\(unexpected)"
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

        init(_ source: PassiveBluetoothExperimentOneSoftwareExport) {
            schemaVersion = source.schemaVersion
            experimentRecipeID = source.experimentRecipeID.rawValue
            captureJSONBase64 = source.captureJSON.base64EncodedString()
            stationaryManifestJSONBase64 = source.stationaryManifestJSON.base64EncodedString()
            correlationWindows = source.correlationWindows.map(WireWindow.init)
            build = WireBuild(source.build)
        }
    }

    private struct WireWindow: Codable {
        let phase: Int
        let observationSeriesIdentity: String
        let windowSequence: UInt64
        let startedAtUptimeNanoseconds: UInt64
        let endedAtUptimeNanoseconds: UInt64
        let candidates: [WireCandidate]

        init(_ source: PassiveBluetoothExperimentOneSoftwareExport.CorrelationWindow) {
            phase = source.phase.rawValue
            observationSeriesIdentity = source.observationSeriesIdentity.uuidString
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
            guard PassiveBluetoothCaptureRuntimeBuildIdentityReader.normalizedBuildInstanceID(buildInstanceID) == buildInstanceID,
                  PassiveBluetoothCaptureRuntimeBuildIdentityReader.normalizedFullGitCommitSHA(sourceCommitSHA) == sourceCommitSHA,
                  executableSHA256.count == 64,
                  executableSHA256.utf8.allSatisfy({ byte in
                      (48...57).contains(byte) || (97...102).contains(byte)
                  }),
                  !buildIdentifier.isEmpty,
                  buildIdentifier.utf8.count <= 128,
                  buildIdentifier == buildIdentifier.trimmingCharacters(in: .whitespacesAndNewlines),
                  !buildIdentifier.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
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
    /// Available only after immutable Horizon finalization. External field authorization remains
    /// separate; this method cannot unlock a physical experiment.
    func finalizedSoftwareExportForCurrentApplication(
        setup: PassiveBluetoothStationaryCaptureSetup
    ) throws -> PassiveBluetoothExperimentOneSoftwareExport {
        guard let finalizedArtifact else {
            throw PassiveBluetoothExperimentOneSoftwareExportError.artifactNotFinalized
        }
        return try PassiveBluetoothExperimentOneSoftwareExportCodec.makeForCurrentApplication(
            finalizedArtifact: finalizedArtifact,
            setup: setup
        )
    }

    func encodedFinalizedSoftwareExportForCurrentApplication(
        setup: PassiveBluetoothStationaryCaptureSetup,
        prettyPrinted: Bool = true
    ) throws -> Data {
        try PassiveBluetoothExperimentOneSoftwareExportCodec.encode(
            finalizedSoftwareExportForCurrentApplication(setup: setup),
            prettyPrinted: prettyPrinted
        )
    }
}
