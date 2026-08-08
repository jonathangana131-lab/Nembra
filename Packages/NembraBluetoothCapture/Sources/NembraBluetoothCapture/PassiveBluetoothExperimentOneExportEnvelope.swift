import Foundation

/// Verification and construction failures for the package-owned Experiment One export envelope.
///
/// These errors describe software evidence/provenance consistency only. None of them authenticates
/// a physical AOVOPRO ES80 or grants permission to perform the physical procedure.
public enum PassiveBluetoothExperimentOneExportEnvelopeError: Error, Equatable, Sendable {
    case unsupportedSchemaVersion(Int)
    case unexpectedEnvelopeField(String)
    case invalidPowerCycleWindowCount(Int)
    case invalidPowerCycleSnapshotCount(Int)
    case invalidPowerCycleWindowPhase(index: Int)
    case invalidPowerCycleWindowSequence(index: Int)
    case invalidPowerCycleObservedCandidateCount(index: Int)
    case invalidPowerCycleWindowClock(index: Int)
    case powerCycleWindowTooShort(index: Int)
    case overlappingPowerCycleWindows(index: Int)
    case invalidPowerCycleSnapshot(index: Int)
    case correlationDoesNotMatchSnapshots
    case correlationNotUnique
    case manifestRecipeMismatch
    case manifestTargetDoesNotMatchCorrelation
    case manifestBuildIdentityMismatch
    case invalidRuntimeBuildIdentifier
    case invalidRuntimeBuildInstanceID
    case invalidRuntimeSourceCommitSHA
    case invalidRuntimeExecutableSHA256
}

/// Software build evidence retained inside one verified export envelope.
///
/// `buildInstanceID` is an opaque rendezvous identifier and `sourceCommitSHA` is a build declaration.
/// `executableSHA256` identifies the executable bytes measured by the runtime producer. These fields
/// let an external accepted build/GO record correlate to the artifact later; they are not field GO
/// authority by themselves.
public struct PassiveBluetoothExperimentOneExportRuntimeBuildEvidence: Equatable, Sendable {
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

/// A fully verified software export envelope for one sealed Experiment One evidence life.
///
/// Verification replays the four-window target correlation and independently rebuilds the stationary
/// manifest from the exact embedded capture bytes. It never promotes the repeated CoreBluetooth UUID
/// into authenticated scooter identity and never embeds a self-declared physical-GO Boolean.
public struct PassiveBluetoothExperimentOneExportEnvelope: Equatable, Sendable {
    public let schemaVersion: Int
    public let experimentRecipeID: PassiveBluetoothExperimentRecipeID
    public let captureJSON: Data
    public let stationaryManifest: PassiveBluetoothStationaryCaptureManifest
    public let powerCycleResult: PassiveBluetoothPowerCycleObservationResult
    public let runtimeBuild: PassiveBluetoothExperimentOneExportRuntimeBuildEvidence

    fileprivate init(
        schemaVersion: Int,
        experimentRecipeID: PassiveBluetoothExperimentRecipeID,
        captureJSON: Data,
        stationaryManifest: PassiveBluetoothStationaryCaptureManifest,
        powerCycleResult: PassiveBluetoothPowerCycleObservationResult,
        runtimeBuild: PassiveBluetoothExperimentOneExportRuntimeBuildEvidence
    ) {
        self.schemaVersion = schemaVersion
        self.experimentRecipeID = experimentRecipeID
        self.captureJSON = captureJSON
        self.stationaryManifest = stationaryManifest
        self.powerCycleResult = powerCycleResult
        self.runtimeBuild = runtimeBuild
    }
}

/// Closed-world JSON producer/verifier for the artifact Nembra should eventually expose as the
/// primary Experiment One Share payload.
///
/// The only public production producer accepts the coordinator's non-forgeable `FinalizedArtifact`
/// plus build identity read by the accepted runtime producer. A caller cannot provide a target UUID,
/// detached power-cycle result, recipe ID, build strings, capture bytes, or manifest.
///
/// Schema v1 intentionally does not contain a physical authorization flag or external attestation.
/// The exact build-instance rendezvous is retained so a future independently accepted signed-device
/// GO/build record can be correlated without placing that authority inside this self-produced file.
public enum PassiveBluetoothExperimentOneExportEnvelopeJSON {
    public static let currentSchemaVersion = 1

    private static let minimumPowerCycleWindowDurationNanoseconds: UInt64 = 10_000_000_000

    /// Creates the current package-owned export envelope from one already-sealed coordinator artifact.
    ///
    /// `setup` remains declared experiment context. The app must obtain those declarations through a
    /// truthful preflight UX; this producer does not infer charger state or stock-app state.
    public static func encode(
        finalizedArtifact: PassiveBluetoothExperimentOneCoordinator.FinalizedArtifact,
        runtimeBuildIdentity: PassiveBluetoothCaptureRuntimeBuildIdentity,
        setup: PassiveBluetoothStationaryCaptureSetup,
        preparedAt: Date = Date(),
        prettyPrinted: Bool = true
    ) throws -> Data {
        try encodeValidated(
            captureJSON: finalizedArtifact.captureJSON,
            powerCycleResult: finalizedArtifact.powerCycleResult,
            runtimeBuildIdentity: runtimeBuildIdentity,
            setup: setup,
            preparedAt: preparedAt,
            prettyPrinted: prettyPrinted
        )
    }

    /// Verifies the closed-world envelope, replays four-window correlation, and rebuilds the
    /// stationary manifest from the exact embedded capture bytes.
    public static func verify(
        _ envelopeJSON: Data
    ) throws -> PassiveBluetoothExperimentOneExportEnvelope {
        try validateSchemaShape(envelopeJSON)

        let decoder = JSONDecoder()
        let probe = try decoder.decode(VersionProbe.self, from: envelopeJSON)
        guard probe.schemaVersion == currentSchemaVersion else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError
                .unsupportedSchemaVersion(probe.schemaVersion)
        }

        let wire = try decoder.decode(WireV1.self, from: envelopeJSON)
        guard wire.schemaVersion == currentSchemaVersion else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError
                .unsupportedSchemaVersion(wire.schemaVersion)
        }
        guard wire.experimentRecipeID == .es80FingerprintV1 else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.manifestRecipeMismatch
        }

        let runtimeBuild = try validatedRuntimeBuildEvidence(wire.runtimeBuild)
        let powerCycleResult = try wire.powerCycleObservation.makeResult()
        let correlatedTarget = try validatePowerCycleResult(powerCycleResult)

        let manifest = try PassiveBluetoothStationaryCaptureManifestJSON.verifyCaptureBinding(
            manifestJSON: wire.stationaryManifestJSON,
            captureJSON: wire.captureJSON
        )

        guard manifest.experimentRecipeID == wire.experimentRecipeID else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.manifestRecipeMismatch
        }
        guard manifest.sourceArtifact.selectedPeripheralIdentifier == correlatedTarget.uuidString else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.manifestTargetDoesNotMatchCorrelation
        }
        guard manifest.nembraBuildIdentifier == runtimeBuild.buildIdentifier,
              manifest.nembraBuildInstanceID == runtimeBuild.buildInstanceID,
              manifest.nembraBuildCommitSHA == runtimeBuild.sourceCommitSHA else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.manifestBuildIdentityMismatch
        }

        return PassiveBluetoothExperimentOneExportEnvelope(
            schemaVersion: wire.schemaVersion,
            experimentRecipeID: wire.experimentRecipeID,
            captureJSON: wire.captureJSON,
            stationaryManifest: manifest,
            powerCycleResult: powerCycleResult,
            runtimeBuild: runtimeBuild
        )
    }

    /// Internal deterministic seam used by package tests. Production app clients cannot call this
    /// raw-pieces path; the public producer above requires the coordinator-issued finalized artifact.
    static func _testingEncode(
        captureJSON: Data,
        powerCycleResult: PassiveBluetoothPowerCycleObservationResult,
        runtimeBuildIdentity: PassiveBluetoothCaptureRuntimeBuildIdentity,
        setup: PassiveBluetoothStationaryCaptureSetup,
        preparedAt: Date,
        prettyPrinted: Bool = true
    ) throws -> Data {
        try encodeValidated(
            captureJSON: captureJSON,
            powerCycleResult: powerCycleResult,
            runtimeBuildIdentity: runtimeBuildIdentity,
            setup: setup,
            preparedAt: preparedAt,
            prettyPrinted: prettyPrinted
        )
    }

    private static func encodeValidated(
        captureJSON: Data,
        powerCycleResult: PassiveBluetoothPowerCycleObservationResult,
        runtimeBuildIdentity: PassiveBluetoothCaptureRuntimeBuildIdentity,
        setup: PassiveBluetoothStationaryCaptureSetup,
        preparedAt: Date,
        prettyPrinted: Bool
    ) throws -> Data {
        let correlatedTarget = try validatePowerCycleResult(powerCycleResult)
        let runtimeBuildWire = RuntimeBuildWire(runtimeBuildIdentity)
        _ = try validatedRuntimeBuildEvidence(runtimeBuildWire)

        let manifest = try PassiveBluetoothStationaryCaptureManifestBuilder.make(
            captureJSON: captureJSON,
            experimentRecipe: .es80FingerprintV1,
            preparedAt: preparedAt,
            nembraBuildIdentifier: runtimeBuildIdentity.buildIdentifier,
            nembraBuildInstanceID: runtimeBuildIdentity.buildInstanceID,
            nembraBuildCommitSHA: runtimeBuildIdentity.sourceCommitSHA,
            selectedPeripheralIdentifier: correlatedTarget.uuidString,
            setup: setup
        )
        let manifestJSON = try PassiveBluetoothStationaryCaptureManifestJSON.encode(
            manifest,
            prettyPrinted: false
        )

        let wire = WireV1(
            schemaVersion: currentSchemaVersion,
            experimentRecipeID: .es80FingerprintV1,
            captureJSON: captureJSON,
            stationaryManifestJSON: manifestJSON,
            powerCycleObservation: PowerCycleObservationWire(powerCycleResult),
            runtimeBuild: runtimeBuildWire
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = prettyPrinted ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        let encoded = try encoder.encode(wire)

        // Self-verify before the bytes leave the package so construction and import share one contract.
        _ = try verify(encoded)
        return encoded
    }

    private static func validatePowerCycleResult(
        _ result: PassiveBluetoothPowerCycleObservationResult
    ) throws -> UUID {
        let expectedPhases = PassiveBluetoothPowerCycleObservationPhase.allCases
        guard result.windows.count == expectedPhases.count else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError
                .invalidPowerCycleWindowCount(result.windows.count)
        }
        guard result.observationSnapshots.count == expectedPhases.count else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError
                .invalidPowerCycleSnapshotCount(result.observationSnapshots.count)
        }

        for index in expectedPhases.indices {
            let receipt = result.windows[index]
            let snapshot = result.observationSnapshots[index]

            guard receipt.phase == expectedPhases[index] else {
                throw PassiveBluetoothExperimentOneExportEnvelopeError
                    .invalidPowerCycleWindowPhase(index: index)
            }
            guard receipt.windowSequence == snapshot.windowSequence else {
                throw PassiveBluetoothExperimentOneExportEnvelopeError
                    .invalidPowerCycleWindowSequence(index: index)
            }
            guard receipt.observedCandidateCount == snapshot.candidates.count else {
                throw PassiveBluetoothExperimentOneExportEnvelopeError
                    .invalidPowerCycleObservedCandidateCount(index: index)
            }
            guard receipt.endedAtUptimeNanoseconds >= receipt.startedAtUptimeNanoseconds else {
                throw PassiveBluetoothExperimentOneExportEnvelopeError
                    .invalidPowerCycleWindowClock(index: index)
            }
            guard receipt.endedAtUptimeNanoseconds - receipt.startedAtUptimeNanoseconds
                    >= minimumPowerCycleWindowDurationNanoseconds else {
                throw PassiveBluetoothExperimentOneExportEnvelopeError
                    .powerCycleWindowTooShort(index: index)
            }
            if index > expectedPhases.startIndex {
                let previous = result.windows[index - 1]
                guard receipt.startedAtUptimeNanoseconds >= previous.endedAtUptimeNanoseconds else {
                    throw PassiveBluetoothExperimentOneExportEnvelopeError
                        .overlappingPowerCycleWindows(index: index)
                }
            }
        }

        let snapshots = result.observationSnapshots
        let recomputed = PassiveBluetoothPowerCycleTargetCorrelation.assess(
            firstOff: snapshots[0],
            firstOn: snapshots[1],
            secondOff: snapshots[2],
            secondOn: snapshots[3]
        )
        guard recomputed == result.correlation else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.correlationDoesNotMatchSnapshots
        }
        guard case let .singleRepeatableCandidate(identifier) = recomputed.disposition else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.correlationNotUnique
        }
        return identifier
    }

    private static func validatedRuntimeBuildEvidence(
        _ wire: RuntimeBuildWire
    ) throws -> PassiveBluetoothExperimentOneExportRuntimeBuildEvidence {
        guard !wire.buildIdentifier.isEmpty,
              wire.buildIdentifier.utf8.count <= 128,
              wire.buildIdentifier == wire.buildIdentifier.trimmingCharacters(in: .whitespacesAndNewlines),
              !wire.buildIdentifier.unicodeScalars.contains(where: {
                  CharacterSet.controlCharacters.contains($0)
              }) else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.invalidRuntimeBuildIdentifier
        }

        guard let normalizedInstance = PassiveBluetoothCaptureRuntimeBuildIdentityReader
                .normalizedBuildInstanceID(wire.buildInstanceID),
              normalizedInstance == wire.buildInstanceID else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.invalidRuntimeBuildInstanceID
        }
        guard let normalizedCommit = PassiveBluetoothCaptureRuntimeBuildIdentityReader
                .normalizedFullGitCommitSHA(wire.sourceCommitSHA),
              normalizedCommit == wire.sourceCommitSHA else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.invalidRuntimeSourceCommitSHA
        }
        guard isLowercaseHex(wire.executableSHA256, exactCount: 64) else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.invalidRuntimeExecutableSHA256
        }

        return PassiveBluetoothExperimentOneExportRuntimeBuildEvidence(
            buildIdentifier: wire.buildIdentifier,
            buildInstanceID: wire.buildInstanceID,
            sourceCommitSHA: wire.sourceCommitSHA,
            executableSHA256: wire.executableSHA256
        )
    }

    private static func isLowercaseHex(_ value: String, exactCount: Int) -> Bool {
        guard value.utf8.count == exactCount else { return false }
        return value.utf8.allSatisfy { byte in
            (48...57).contains(byte) || (97...102).contains(byte)
        }
    }

    private static func validateSchemaShape(_ data: Data) throws {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        guard let schemaVersion = root["schemaVersion"] as? Int else {
            return
        }
        guard schemaVersion == currentSchemaVersion else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError
                .unsupportedSchemaVersion(schemaVersion)
        }

        try rejectUnexpectedKeys(
            in: root,
            allowed: [
                "schemaVersion", "experimentRecipeID", "captureJSON", "stationaryManifestJSON",
                "powerCycleObservation", "runtimeBuild",
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
        if let powerCycle = root["powerCycleObservation"] as? [String: Any] {
            try rejectUnexpectedKeys(
                in: powerCycle,
                allowed: ["windows", "snapshots"],
                path: "powerCycleObservation"
            )
            if let windows = powerCycle["windows"] as? [[String: Any]] {
                for (index, window) in windows.enumerated() {
                    try rejectUnexpectedKeys(
                        in: window,
                        allowed: [
                            "phase", "windowSequence", "startedAtUptimeNanoseconds",
                            "endedAtUptimeNanoseconds", "observedCandidateCount",
                        ],
                        path: "powerCycleObservation.windows[\(index)]"
                    )
                }
            }
            if let snapshots = powerCycle["snapshots"] as? [[String: Any]] {
                for (index, snapshot) in snapshots.enumerated() {
                    try rejectUnexpectedKeys(
                        in: snapshot,
                        allowed: ["observationSeriesIdentity", "windowSequence", "candidates"],
                        path: "powerCycleObservation.snapshots[\(index)]"
                    )
                    if let candidates = snapshot["candidates"] as? [[String: Any]] {
                        for (candidateIndex, candidate) in candidates.enumerated() {
                            try rejectUnexpectedKeys(
                                in: candidate,
                                allowed: ["id", "isConnectable"],
                                path: "powerCycleObservation.snapshots[\(index)].candidates[\(candidateIndex)]"
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

    private struct VersionProbe: Decodable {
        let schemaVersion: Int
    }

    private struct WireV1: Codable {
        let schemaVersion: Int
        let experimentRecipeID: PassiveBluetoothExperimentRecipeID
        let captureJSON: Data
        let stationaryManifestJSON: Data
        let powerCycleObservation: PowerCycleObservationWire
        let runtimeBuild: RuntimeBuildWire
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

    private struct PowerCycleObservationWire: Codable {
        let windows: [WindowWire]
        let snapshots: [SnapshotWire]

        init(_ result: PassiveBluetoothPowerCycleObservationResult) {
            windows = result.windows.map(WindowWire.init)
            snapshots = result.observationSnapshots.map(SnapshotWire.init)
        }

        func makeResult() throws -> PassiveBluetoothPowerCycleObservationResult {
            guard windows.count == PassiveBluetoothPowerCycleObservationPhase.allCases.count else {
                throw PassiveBluetoothExperimentOneExportEnvelopeError
                    .invalidPowerCycleWindowCount(windows.count)
            }
            guard snapshots.count == PassiveBluetoothPowerCycleObservationPhase.allCases.count else {
                throw PassiveBluetoothExperimentOneExportEnvelopeError
                    .invalidPowerCycleSnapshotCount(snapshots.count)
            }

            let rebuiltWindows = windows.map { $0.makeReceipt() }
            var rebuiltSnapshots: [PassiveBluetoothCandidateObservationSnapshot] = []
            rebuiltSnapshots.reserveCapacity(snapshots.count)
            for (index, snapshot) in snapshots.enumerated() {
                do {
                    rebuiltSnapshots.append(try snapshot.makeSnapshot())
                } catch {
                    throw PassiveBluetoothExperimentOneExportEnvelopeError
                        .invalidPowerCycleSnapshot(index: index)
                }
            }

            let correlation = PassiveBluetoothPowerCycleTargetCorrelation.assess(
                firstOff: rebuiltSnapshots[0],
                firstOn: rebuiltSnapshots[1],
                secondOff: rebuiltSnapshots[2],
                secondOn: rebuiltSnapshots[3]
            )
            return PassiveBluetoothPowerCycleObservationResult(
                windows: rebuiltWindows,
                observationSnapshots: rebuiltSnapshots,
                correlation: correlation
            )
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

        func makeReceipt() -> PassiveBluetoothPowerCycleObservationWindowReceipt {
            PassiveBluetoothPowerCycleObservationWindowReceipt(
                phase: phase.value,
                windowSequence: PassiveBluetoothCandidateObservationWindowSequence(rawValue: windowSequence),
                startedAtUptimeNanoseconds: startedAtUptimeNanoseconds,
                endedAtUptimeNanoseconds: endedAtUptimeNanoseconds,
                observedCandidateCount: observedCandidateCount
            )
        }
    }

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

        var value: PassiveBluetoothPowerCycleObservationPhase {
            switch self {
            case .firstPoweredOff: .firstPoweredOff
            case .firstPoweredOn: .firstPoweredOn
            case .secondPoweredOff: .secondPoweredOff
            case .secondPoweredOn: .secondPoweredOn
            }
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

        func makeSnapshot() throws -> PassiveBluetoothCandidateObservationSnapshot {
            try PassiveBluetoothCandidateObservationSnapshot(
                observationSeriesIdentity: PassiveBluetoothCandidateObservationSeriesIdentity(
                    rawValue: observationSeriesIdentity
                ),
                windowSequence: PassiveBluetoothCandidateObservationWindowSequence(rawValue: windowSequence),
                candidates: candidates.map { $0.value }
            )
        }
    }

    private struct CandidateWire: Codable {
        let id: UUID
        let isConnectable: Bool?

        init(_ candidate: PassiveBluetoothCandidateObservationSnapshot.Candidate) {
            id = candidate.id
            isConnectable = candidate.isConnectable
        }

        var value: PassiveBluetoothCandidateObservationSnapshot.Candidate {
            .init(id: id, isConnectable: isConnectable)
        }
    }
}