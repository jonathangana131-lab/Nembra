import Foundation

/// Durable, package-owned export for the first ES80 fingerprint experiment.
///
/// The envelope binds the exact sealed controller JSON bytes to the immutable four-window
/// correlation evidence, the stationary-capture manifest, and runtime build provenance. It does
/// not authorize field execution, authenticate a physical scooter, or promote correlation into
/// protocol/telemetry meaning.
public struct PassiveBluetoothExperimentOneExportEnvelope: Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public enum FieldAuthorization: String, Codable, Sendable {
        /// Physical GO/NO-GO authority intentionally lives outside the artifact. A capture export
        /// must never self-authorize the build that produced it.
        case notContained = "not-contained"
    }

    public struct RuntimeBuild: Equatable, Codable, Sendable {
        public let buildIdentifier: String
        public let buildInstanceID: String
        public let sourceCommitSHA: String
        public let executableSHA256: String

        fileprivate init(_ identity: PassiveBluetoothCaptureRuntimeBuildIdentity) {
            buildIdentifier = identity.buildIdentifier
            buildInstanceID = identity.buildInstanceID
            sourceCommitSHA = identity.sourceCommitSHA
            executableSHA256 = identity.executableSHA256
        }
    }

    public struct PowerCycleEvidence: Equatable, Codable, Sendable {
        public struct Window: Equatable, Codable, Sendable {
            public enum Phase: String, Codable, Sendable {
                case firstPoweredOff
                case firstPoweredOn
                case secondPoweredOff
                case secondPoweredOn

                fileprivate init(_ phase: PassiveBluetoothPowerCycleObservationPhase) {
                    switch phase {
                    case .firstPoweredOff: self = .firstPoweredOff
                    case .firstPoweredOn: self = .firstPoweredOn
                    case .secondPoweredOff: self = .secondPoweredOff
                    case .secondPoweredOn: self = .secondPoweredOn
                    }
                }
            }

            public let phase: Phase
            public let windowSequence: UInt64
            public let startedAtUptimeNanoseconds: UInt64
            public let endedAtUptimeNanoseconds: UInt64
            public let observedCandidateCount: Int

            fileprivate init(_ receipt: PassiveBluetoothPowerCycleObservationWindowReceipt) {
                phase = .init(receipt.phase)
                windowSequence = receipt.windowSequence.rawValue
                startedAtUptimeNanoseconds = receipt.startedAtUptimeNanoseconds
                endedAtUptimeNanoseconds = receipt.endedAtUptimeNanoseconds
                observedCandidateCount = receipt.observedCandidateCount
            }
        }

        public struct Snapshot: Equatable, Codable, Sendable {
            public struct Candidate: Equatable, Codable, Sendable {
                public let identifier: UUID
                public let isConnectable: Bool?

                fileprivate init(_ candidate: PassiveBluetoothCandidateObservationSnapshot.Candidate) {
                    identifier = candidate.id
                    isConnectable = candidate.isConnectable
                }
            }

            public let observationSeriesIdentity: UUID
            public let windowSequence: UInt64
            public let candidates: [Candidate]

            fileprivate init(_ snapshot: PassiveBluetoothCandidateObservationSnapshot) {
                observationSeriesIdentity = snapshot.observationSeriesIdentity.rawValue
                windowSequence = snapshot.windowSequence.rawValue
                candidates = snapshot.candidates.map(Candidate.init)
            }

            fileprivate func sourceSnapshot() throws -> PassiveBluetoothCandidateObservationSnapshot {
                try PassiveBluetoothCandidateObservationSnapshot(
                    observationSeriesIdentity: .init(rawValue: observationSeriesIdentity),
                    windowSequence: .init(rawValue: windowSequence),
                    candidates: candidates.map {
                        .init(id: $0.identifier, isConnectable: $0.isConnectable)
                    }
                )
            }
        }

        public struct Correlation: Equatable, Codable, Sendable {
            public enum DispositionKind: String, Codable, Sendable {
                case invalidObservationAuthority
                case invalidObservationWindowOrder
                case noRepeatableCandidate
                case ambiguousRepeatableCandidates
                case singleRepeatableCandidate
            }

            public let observationSeriesIdentities: [UUID]
            public let windowSequences: [UInt64]
            public let firstOffObservedIdentifiers: [UUID]
            public let secondOffObservedIdentifiers: [UUID]
            public let firstOnSelectableIdentifiers: [UUID]
            public let secondOnSelectableIdentifiers: [UUID]
            public let firstCycleNewSelectableIdentifiers: [UUID]
            public let secondCycleNewSelectableIdentifiers: [UUID]
            public let repeatableCandidateIdentifiers: [UUID]
            public let disposition: DispositionKind
            public let dispositionCandidateIdentifiers: [UUID]

            fileprivate init(_ report: PassiveBluetoothPowerCycleTargetCorrelationReport) {
                observationSeriesIdentities = report.observationSeriesIdentities.map(\.rawValue)
                windowSequences = [
                    report.firstOffWindowSequence.rawValue,
                    report.firstOnWindowSequence.rawValue,
                    report.secondOffWindowSequence.rawValue,
                    report.secondOnWindowSequence.rawValue,
                ]
                firstOffObservedIdentifiers = report.firstOffObservedIdentifiers
                secondOffObservedIdentifiers = report.secondOffObservedIdentifiers
                firstOnSelectableIdentifiers = report.firstOnSelectableIdentifiers
                secondOnSelectableIdentifiers = report.secondOnSelectableIdentifiers
                firstCycleNewSelectableIdentifiers = report.firstCycleNewSelectableIdentifiers
                secondCycleNewSelectableIdentifiers = report.secondCycleNewSelectableIdentifiers
                repeatableCandidateIdentifiers = report.repeatableCandidateIdentifiers

                switch report.disposition {
                case .invalidObservationAuthority:
                    disposition = .invalidObservationAuthority
                    dispositionCandidateIdentifiers = []
                case .invalidObservationWindowOrder:
                    disposition = .invalidObservationWindowOrder
                    dispositionCandidateIdentifiers = []
                case .noRepeatableCandidate:
                    disposition = .noRepeatableCandidate
                    dispositionCandidateIdentifiers = []
                case let .ambiguousRepeatableCandidates(identifiers):
                    disposition = .ambiguousRepeatableCandidates
                    dispositionCandidateIdentifiers = identifiers
                case let .singleRepeatableCandidate(identifier):
                    disposition = .singleRepeatableCandidate
                    dispositionCandidateIdentifiers = [identifier]
                }
            }
        }

        public let windows: [Window]
        public let observationSnapshots: [Snapshot]
        public let correlation: Correlation

        fileprivate init(_ result: PassiveBluetoothPowerCycleObservationResult) {
            windows = result.windows.map(Window.init)
            observationSnapshots = result.observationSnapshots.map(Snapshot.init)
            correlation = .init(result.correlation)
        }
    }

    public let schemaVersion: Int
    public let recipeID: PassiveBluetoothExperimentRecipeID
    public let fieldAuthorization: FieldAuthorization
    public let runtimeBuild: RuntimeBuild
    /// Exact bytes emitted by the immutable observation-horizon seal.
    public let sealedCaptureJSON: Data
    /// Exact encoded v3 stationary manifest bound to `sealedCaptureJSON`.
    public let stationaryManifestJSON: Data
    public let powerCycleEvidence: PowerCycleEvidence

    fileprivate init(
        runtimeBuildIdentity: PassiveBluetoothCaptureRuntimeBuildIdentity,
        sealedCaptureJSON: Data,
        stationaryManifestJSON: Data,
        powerCycleEvidence: PowerCycleEvidence
    ) {
        schemaVersion = Self.currentSchemaVersion
        recipeID = .es80FingerprintV1
        fieldAuthorization = .notContained
        runtimeBuild = .init(runtimeBuildIdentity)
        self.sealedCaptureJSON = sealedCaptureJSON
        self.stationaryManifestJSON = stationaryManifestJSON
        self.powerCycleEvidence = powerCycleEvidence
    }
}

public enum PassiveBluetoothExperimentOneExportEnvelopeError: Error, Equatable, Sendable {
    case unsupportedSchemaVersion(Int)
    case unsupportedRecipe(PassiveBluetoothExperimentRecipeID)
    case fieldAuthorizationMustRemainExternal
    case correlationNotSingleCandidate
    case correlationCandidateDoesNotMatchManifest(correlation: String, manifest: String)
    case invalidWindowEvidence
    case invalidExecutableSHA256(String)
    case runtimeBuildDoesNotMatchManifest
    case envelopeDoesNotMatchCorrelation
}

public enum PassiveBluetoothExperimentOneExportEnvelopeBuilder {
    /// Package-owned construction boundary used by the coordinator-issued finalized artifact.
    /// Tests can exercise the same boundary with deterministic package evidence; app/UI code cannot
    /// construct a `FinalizedArtifact` or runtime identity from arbitrary bytes/metadata.
    package static func make(
        captureJSON: Data,
        powerCycleResult: PassiveBluetoothPowerCycleObservationResult,
        runtimeBuildIdentity: PassiveBluetoothCaptureRuntimeBuildIdentity,
        experimentID: UUID = UUID(),
        preparedAt: Date = Date(),
        setup: PassiveBluetoothStationaryCaptureSetup
    ) throws -> PassiveBluetoothExperimentOneExportEnvelope {
        guard case let .singleRepeatableCandidate(selectedPeripheral) = powerCycleResult.correlation.disposition else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.correlationNotSingleCandidate
        }
        guard isLowercaseHex(runtimeBuildIdentity.executableSHA256, length: 64) else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError
                .invalidExecutableSHA256(runtimeBuildIdentity.executableSHA256)
        }

        let manifest = try PassiveBluetoothStationaryCaptureManifestBuilder.make(
            captureJSON: captureJSON,
            experimentID: experimentID,
            experimentRecipe: .es80FingerprintV1,
            preparedAt: preparedAt,
            nembraBuildIdentifier: runtimeBuildIdentity.buildIdentifier,
            nembraBuildInstanceID: runtimeBuildIdentity.buildInstanceID,
            nembraBuildCommitSHA: runtimeBuildIdentity.sourceCommitSHA,
            selectedPeripheralIdentifier: selectedPeripheral.uuidString,
            setup: setup
        )
        let manifestJSON = try PassiveBluetoothStationaryCaptureManifestJSON.encode(manifest)

        return PassiveBluetoothExperimentOneExportEnvelope(
            runtimeBuildIdentity: runtimeBuildIdentity,
            sealedCaptureJSON: captureJSON,
            stationaryManifestJSON: manifestJSON,
            powerCycleEvidence: .init(powerCycleResult)
        )
    }

    private static func isLowercaseHex(_ value: String, length: Int) -> Bool {
        guard value.utf8.count == length else { return false }
        return value.utf8.allSatisfy { byte in
            (48...57).contains(byte) || (97...102).contains(byte)
        }
    }
}

public enum PassiveBluetoothExperimentOneExportEnvelopeJSON {
    public static func encode(
        _ envelope: PassiveBluetoothExperimentOneExportEnvelope,
        prettyPrinted: Bool = true
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = prettyPrinted ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return try encoder.encode(Wire(envelope))
    }

    /// Decodes and replays the package-owned bindings that can be verified from the artifact alone.
    ///
    /// This verifies byte/hash binding, manifest/runtime agreement, four-window chronology, and the
    /// correlation calculation. It deliberately does not claim independent build acceptance or
    /// physical field authorization; those remain external exact-build gates.
    public static func decodeAndVerify(
        _ data: Data
    ) throws -> PassiveBluetoothExperimentOneExportEnvelope {
        let decoder = JSONDecoder()
        let wire = try decoder.decode(Wire.self, from: data)

        guard wire.schemaVersion == PassiveBluetoothExperimentOneExportEnvelope.currentSchemaVersion else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError
                .unsupportedSchemaVersion(wire.schemaVersion)
        }
        guard wire.recipeID == .es80FingerprintV1 else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.unsupportedRecipe(wire.recipeID)
        }
        guard wire.fieldAuthorization == .notContained else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.fieldAuthorizationMustRemainExternal
        }
        guard isLowercaseHex(wire.runtimeBuild.executableSHA256, length: 64) else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError
                .invalidExecutableSHA256(wire.runtimeBuild.executableSHA256)
        }

        let manifest = try PassiveBluetoothStationaryCaptureManifestJSON.verifyCaptureBinding(
            manifestJSON: wire.stationaryManifestJSON,
            captureJSON: wire.sealedCaptureJSON
        )
        guard manifest.schemaVersion == PassiveBluetoothStationaryCaptureManifest.currentSchemaVersion,
              manifest.experimentRecipeID == wire.recipeID,
              manifest.nembraBuildIdentifier == wire.runtimeBuild.buildIdentifier,
              manifest.nembraBuildInstanceID == wire.runtimeBuild.buildInstanceID,
              manifest.nembraBuildCommitSHA == wire.runtimeBuild.sourceCommitSHA else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.runtimeBuildDoesNotMatchManifest
        }

        let sourceSnapshots = try wire.powerCycleEvidence.observationSnapshots.map {
            try $0.sourceSnapshot()
        }
        guard sourceSnapshots.count == 4,
              wire.powerCycleEvidence.windows.count == 4 else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.invalidWindowEvidence
        }
        let expectedPhases: [PassiveBluetoothExperimentOneExportEnvelope.PowerCycleEvidence.Window.Phase] = [
            .firstPoweredOff, .firstPoweredOn, .secondPoweredOff, .secondPoweredOn,
        ]
        for index in 0..<4 {
            let window = wire.powerCycleEvidence.windows[index]
            let snapshot = sourceSnapshots[index]
            guard window.phase == expectedPhases[index],
                  window.windowSequence == snapshot.windowSequence.rawValue,
                  window.observedCandidateCount == snapshot.candidates.count,
                  window.endedAtUptimeNanoseconds >= window.startedAtUptimeNanoseconds else {
                throw PassiveBluetoothExperimentOneExportEnvelopeError.invalidWindowEvidence
            }
        }

        let replayed = PassiveBluetoothPowerCycleTargetCorrelation.assess(
            firstOff: sourceSnapshots[0],
            firstOn: sourceSnapshots[1],
            secondOff: sourceSnapshots[2],
            secondOn: sourceSnapshots[3]
        )
        let replayedProjection = PassiveBluetoothExperimentOneExportEnvelope.PowerCycleEvidence.Correlation(replayed)
        guard replayedProjection == wire.powerCycleEvidence.correlation else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.envelopeDoesNotMatchCorrelation
        }
        guard case let .singleRepeatableCandidate(correlationCandidate) = replayed.disposition else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.correlationNotSingleCandidate
        }
        let manifestCandidate = manifest.sourceArtifact.selectedPeripheralIdentifier
        guard correlationCandidate.uuidString == manifestCandidate else {
            throw PassiveBluetoothExperimentOneExportEnvelopeError.correlationCandidateDoesNotMatchManifest(
                correlation: correlationCandidate.uuidString,
                manifest: manifestCandidate
            )
        }

        return PassiveBluetoothExperimentOneExportEnvelope(
            runtimeBuildIdentity: try runtimeIdentity(from: wire.runtimeBuild),
            sealedCaptureJSON: wire.sealedCaptureJSON,
            stationaryManifestJSON: wire.stationaryManifestJSON,
            powerCycleEvidence: wire.powerCycleEvidence
        )
    }

    private static func runtimeIdentity(
        from runtimeBuild: PassiveBluetoothExperimentOneExportEnvelope.RuntimeBuild
    ) throws -> PassiveBluetoothCaptureRuntimeBuildIdentity {
        // Reuse the package's fail-closed grammar without allowing callers to supply a runtime
        // identity directly. The executable digest is reattached only after its wire grammar has
        // been checked above; artifact verification is not a substitute for live executable hashing.
        let placeholderExecutable = Data("nembra-export-verification".utf8)
        let resolved = try PassiveBluetoothCaptureRuntimeBuildIdentityReader.resolveEmbeddedMetadata(
            infoDictionary: [
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildIdentifierInfoDictionaryKey:
                    runtimeBuild.buildIdentifier,
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildInstanceIDInfoDictionaryKey:
                    runtimeBuild.buildInstanceID,
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.sourceCommitSHAInfoDictionaryKey:
                    runtimeBuild.sourceCommitSHA,
            ],
            executableData: placeholderExecutable
        )
        return PassiveBluetoothCaptureRuntimeBuildIdentity(
            buildIdentifier: resolved.buildIdentifier,
            buildInstanceID: resolved.buildInstanceID,
            sourceCommitSHA: resolved.sourceCommitSHA,
            executableSHA256: runtimeBuild.executableSHA256
        )
    }

    private static func isLowercaseHex(_ value: String, length: Int) -> Bool {
        guard value.utf8.count == length else { return false }
        return value.utf8.allSatisfy { byte in
            (48...57).contains(byte) || (97...102).contains(byte)
        }
    }

    private struct Wire: Codable {
        let schemaVersion: Int
        let recipeID: PassiveBluetoothExperimentRecipeID
        let fieldAuthorization: PassiveBluetoothExperimentOneExportEnvelope.FieldAuthorization
        let runtimeBuild: PassiveBluetoothExperimentOneExportEnvelope.RuntimeBuild
        let sealedCaptureJSON: Data
        let stationaryManifestJSON: Data
        let powerCycleEvidence: PassiveBluetoothExperimentOneExportEnvelope.PowerCycleEvidence

        init(_ envelope: PassiveBluetoothExperimentOneExportEnvelope) {
            schemaVersion = envelope.schemaVersion
            recipeID = envelope.recipeID
            fieldAuthorization = envelope.fieldAuthorization
            runtimeBuild = envelope.runtimeBuild
            sealedCaptureJSON = envelope.sealedCaptureJSON
            stationaryManifestJSON = envelope.stationaryManifestJSON
            powerCycleEvidence = envelope.powerCycleEvidence
        }
    }
}

public extension PassiveBluetoothExperimentOneCoordinator.FinalizedArtifact {
    /// Creates the product share artifact from the exact coordinator-issued finalized evidence.
    /// Runtime build provenance is read from the running app and cannot be supplied by UI state.
    func encodedFieldExport(
        setup: PassiveBluetoothStationaryCaptureSetup,
        prettyPrinted: Bool = true
    ) throws -> Data {
        let runtimeIdentity = try PassiveBluetoothCaptureRuntimeBuildIdentityReader.currentApplication()
        let envelope = try PassiveBluetoothExperimentOneExportEnvelopeBuilder.make(
            captureJSON: captureJSON,
            powerCycleResult: powerCycleResult,
            runtimeBuildIdentity: runtimeIdentity,
            setup: setup
        )
        return try PassiveBluetoothExperimentOneExportEnvelopeJSON.encode(
            envelope,
            prettyPrinted: prettyPrinted
        )
    }
}
