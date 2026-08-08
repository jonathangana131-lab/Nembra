import CryptoKit
import Foundation
import NembraCore

/// Declared experiment-context binding for the first stationary physical ES80 capture.
///
/// The manifest never changes the raw capture JSON. Capture-derived fields are rebuilt from the
/// exact bound bytes during verification. Build/procedure fields are provenance declarations,
/// not scooter telemetry, OS attestation, or proof that an operator completed a recipe step.
public enum PassiveBluetoothStationaryCaptureManifestError: Error, Equatable, Sendable {
    case invalidBuildCommitSHA(String)
    case invalidBuildIdentifier(String)
    case invalidBuildInstanceID(String)
    case invalidPreparedAt
    case invalidSelectedPeripheralIdentifier(String)
    case invalidCapturedPeripheralIdentifier(String)
    case noTargetGATTEvidence
    case selectedPeripheralNotPresent(requested: String, available: [String])
    case ambiguousTargetGATTEvidence([String])
    case stockAppMarkersWithoutDeclaredReference(markerCount: Int)
    case stockAppReferenceDeclaredWithoutMarkers
    case unsupportedExperimentRecipe(PassiveBluetoothExperimentRecipeID)
    case unsupportedSchemaVersion(Int)
    case unexpectedManifestField(String)
    case duplicateManifestField(String)
    case manifestDoesNotMatchCapture
}

public enum PassiveBluetoothStationaryCaptureExperimentKind: String, Codable, Sendable {
    case stationaryBaseline
}

public enum PassiveBluetoothStationaryCaptureReferenceSetup: String, Codable, Sendable {
    case none
    case sameDeviceBeforeCapture
    case sameDeviceAfterCapture
    case sameDeviceBeforeAndAfterCapture
    case separateObserverDevice
}

public enum PassiveBluetoothStationaryCaptureChargerState: String, Codable, Sendable {
    case disconnected
    case connected
}

/// Operator-declared execution conditions. These values are setup provenance, not attestation that
/// the condition held continuously throughout the capture.
public enum PassiveBluetoothStationaryCaptureExecutionContext: String, Codable, Sendable {
    case foregroundUnlockedScreenOn
}

public struct PassiveBluetoothStationaryCaptureSetup: Equatable, Codable, Sendable {
    public let chargerState: PassiveBluetoothStationaryCaptureChargerState
    public let executionContext: PassiveBluetoothStationaryCaptureExecutionContext
    public let stockAppReferenceSetup: PassiveBluetoothStationaryCaptureReferenceSetup

    public init(
        chargerState: PassiveBluetoothStationaryCaptureChargerState,
        executionContext: PassiveBluetoothStationaryCaptureExecutionContext,
        stockAppReferenceSetup: PassiveBluetoothStationaryCaptureReferenceSetup
    ) {
        self.chargerState = chargerState
        self.executionContext = executionContext
        self.stockAppReferenceSetup = stockAppReferenceSetup
    }
}

/// A capture-consistent sidecar projection for one stationary physical-capture artifact.
///
/// Schema v2 added the stable experiment recipe ID and human-readable field-build identifier while
/// retaining the exact build commit SHA. Schema v3 additionally records the opaque per-produced-build
/// rendezvous identifier emitted by the accepted build pipeline. v1/v2 remain readable so previously
/// collected evidence is never relabeled with provenance that was not recorded at capture time.
public struct PassiveBluetoothStationaryCaptureManifest: Equatable, Sendable {
    public static let currentSchemaVersion = 3

    public struct SourceArtifact: Equatable, Sendable {
        public let sha256: String
        public let byteCount: Int
        public let captureSessionID: UUID
        public let selectedPeripheralIdentifier: String

        fileprivate init(
            sha256: String,
            byteCount: Int,
            captureSessionID: UUID,
            selectedPeripheralIdentifier: String
        ) {
            self.sha256 = sha256
            self.byteCount = byteCount
            self.captureSessionID = captureSessionID
            self.selectedPeripheralIdentifier = selectedPeripheralIdentifier
        }
    }

    public struct EvidenceSummary: Equatable, Sendable {
        public let targetGATTRecordCount: Int
        public let targetValueRecordCount: Int
        public let stockAppMarkerCount: Int
        public let continuityBreakCount: Int

        fileprivate init(
            targetGATTRecordCount: Int,
            targetValueRecordCount: Int,
            stockAppMarkerCount: Int,
            continuityBreakCount: Int
        ) {
            self.targetGATTRecordCount = targetGATTRecordCount
            self.targetValueRecordCount = targetValueRecordCount
            self.stockAppMarkerCount = stockAppMarkerCount
            self.continuityBreakCount = continuityBreakCount
        }
    }

    public let schemaVersion: Int
    public let experimentKind: PassiveBluetoothStationaryCaptureExperimentKind
    public let experimentID: UUID
    /// Stable recipe/version identity recorded by schema v2+. `nil` only for verified legacy v1 data.
    public let experimentRecipeID: PassiveBluetoothExperimentRecipeID?
    public let preparedAt: Date
    /// Human-readable field build. `nil` only for verified legacy v1 data.
    public let nembraBuildIdentifier: String?
    /// Opaque exact-produced-build rendezvous. Present only in schema v3+; never authorization alone.
    public let nembraBuildInstanceID: String?
    /// Exact Git commit declared by the producing build.
    public let nembraBuildCommitSHA: String
    public let setup: PassiveBluetoothStationaryCaptureSetup
    public let sourceArtifact: SourceArtifact
    public let evidenceSummary: EvidenceSummary

    fileprivate init(
        schemaVersion: Int,
        experimentKind: PassiveBluetoothStationaryCaptureExperimentKind,
        experimentID: UUID,
        experimentRecipeID: PassiveBluetoothExperimentRecipeID?,
        preparedAt: Date,
        nembraBuildIdentifier: String?,
        nembraBuildInstanceID: String?,
        nembraBuildCommitSHA: String,
        setup: PassiveBluetoothStationaryCaptureSetup,
        sourceArtifact: SourceArtifact,
        evidenceSummary: EvidenceSummary
    ) {
        self.schemaVersion = schemaVersion
        self.experimentKind = experimentKind
        self.experimentID = experimentID
        self.experimentRecipeID = experimentRecipeID
        self.preparedAt = preparedAt
        self.nembraBuildIdentifier = nembraBuildIdentifier
        self.nembraBuildInstanceID = nembraBuildInstanceID
        self.nembraBuildCommitSHA = nembraBuildCommitSHA
        self.setup = setup
        self.sourceArtifact = sourceArtifact
        self.evidenceSummary = evidenceSummary
    }
}

public enum PassiveBluetoothStationaryCaptureManifestBuilder {
    /// Creates the current closed-world sidecar for the sealed ES80 fingerprint recipe.
    ///
    /// The build-instance ID must come from the accepted runtime/build provenance producer. It is an
    /// opaque rendezvous value that correlates this artifact with an independently accepted external
    /// build record; it is not cryptographic authorization and must never be rider-entered.
    public static func make(
        captureJSON: Data,
        experimentID: UUID = UUID(),
        experimentRecipe: PassiveBluetoothExperimentRecipe,
        preparedAt: Date = Date(),
        nembraBuildIdentifier: String,
        nembraBuildInstanceID: String,
        nembraBuildCommitSHA: String,
        selectedPeripheralIdentifier: String,
        setup: PassiveBluetoothStationaryCaptureSetup
    ) throws -> PassiveBluetoothStationaryCaptureManifest {
        guard experimentRecipe.id == .es80FingerprintV1 else {
            throw PassiveBluetoothStationaryCaptureManifestError
                .unsupportedExperimentRecipe(experimentRecipe.id)
        }
        return try makeValidated(
            schemaVersion: PassiveBluetoothStationaryCaptureManifest.currentSchemaVersion,
            captureJSON: captureJSON,
            experimentID: experimentID,
            experimentRecipeID: experimentRecipe.id,
            preparedAt: preparedAt,
            nembraBuildIdentifier: nembraBuildIdentifier,
            nembraBuildInstanceID: nembraBuildInstanceID,
            nembraBuildCommitSHA: nembraBuildCommitSHA,
            selectedPeripheralIdentifier: selectedPeripheralIdentifier,
            setup: setup
        )
    }

    /// Package-only legacy constructor retained so v2 regression fixtures can continue to prove old
    /// artifacts without exposing a production API that can mint a new capture without build-instance
    /// provenance. External app consumers can only see the schema-v3 producer above.
    package static func make(
        captureJSON: Data,
        experimentID: UUID = UUID(),
        experimentRecipe: PassiveBluetoothExperimentRecipe,
        preparedAt: Date = Date(),
        nembraBuildIdentifier: String,
        nembraBuildCommitSHA: String,
        selectedPeripheralIdentifier: String,
        setup: PassiveBluetoothStationaryCaptureSetup
    ) throws -> PassiveBluetoothStationaryCaptureManifest {
        guard experimentRecipe.id == .es80FingerprintV1 else {
            throw PassiveBluetoothStationaryCaptureManifestError
                .unsupportedExperimentRecipe(experimentRecipe.id)
        }
        return try makeValidated(
            schemaVersion: 2,
            captureJSON: captureJSON,
            experimentID: experimentID,
            experimentRecipeID: experimentRecipe.id,
            preparedAt: preparedAt,
            nembraBuildIdentifier: nembraBuildIdentifier,
            nembraBuildInstanceID: nil,
            nembraBuildCommitSHA: nembraBuildCommitSHA,
            selectedPeripheralIdentifier: selectedPeripheralIdentifier,
            setup: setup
        )
    }

    fileprivate static func makeValidated(
        schemaVersion: Int,
        captureJSON: Data,
        experimentID: UUID,
        experimentRecipeID: PassiveBluetoothExperimentRecipeID?,
        preparedAt: Date,
        nembraBuildIdentifier: String?,
        nembraBuildInstanceID: String?,
        nembraBuildCommitSHA: String,
        selectedPeripheralIdentifier: String,
        setup: PassiveBluetoothStationaryCaptureSetup
    ) throws -> PassiveBluetoothStationaryCaptureManifest {
        let buildCommit = try validatedBuildCommitSHA(nembraBuildCommitSHA)
        let buildIdentifier: String?
        let buildInstanceID: String?
        switch schemaVersion {
        case 1:
            guard experimentRecipeID == nil,
                  nembraBuildIdentifier == nil,
                  nembraBuildInstanceID == nil else {
                throw PassiveBluetoothStationaryCaptureManifestError.manifestDoesNotMatchCapture
            }
            buildIdentifier = nil
            buildInstanceID = nil
        case 2:
            guard let experimentRecipeID else {
                throw PassiveBluetoothStationaryCaptureManifestError.manifestDoesNotMatchCapture
            }
            guard experimentRecipeID == .es80FingerprintV1 else {
                throw PassiveBluetoothStationaryCaptureManifestError
                    .unsupportedExperimentRecipe(experimentRecipeID)
            }
            guard let nembraBuildIdentifier, nembraBuildInstanceID == nil else {
                throw PassiveBluetoothStationaryCaptureManifestError.manifestDoesNotMatchCapture
            }
            buildIdentifier = try validatedBuildIdentifier(nembraBuildIdentifier)
            buildInstanceID = nil
        case 3:
            guard let experimentRecipeID else {
                throw PassiveBluetoothStationaryCaptureManifestError.manifestDoesNotMatchCapture
            }
            guard experimentRecipeID == .es80FingerprintV1 else {
                throw PassiveBluetoothStationaryCaptureManifestError
                    .unsupportedExperimentRecipe(experimentRecipeID)
            }
            guard let nembraBuildIdentifier, let nembraBuildInstanceID else {
                throw PassiveBluetoothStationaryCaptureManifestError.manifestDoesNotMatchCapture
            }
            buildIdentifier = try validatedBuildIdentifier(nembraBuildIdentifier)
            buildInstanceID = try validatedBuildInstanceID(nembraBuildInstanceID)
        default:
            throw PassiveBluetoothStationaryCaptureManifestError.unsupportedSchemaVersion(schemaVersion)
        }

        guard preparedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw PassiveBluetoothStationaryCaptureManifestError.invalidPreparedAt
        }

        let selectedPeripheral = try canonicalPeripheralIdentifier(
            selectedPeripheralIdentifier,
            captured: false
        )
        let session = try PassiveBluetoothCaptureJSON.decode(captureJSON)
        let summary = try summarize(session: session, selectedPeripheral: selectedPeripheral)

        if setup.stockAppReferenceSetup == .none {
            if summary.stockAppMarkerCount > 0 {
                throw PassiveBluetoothStationaryCaptureManifestError
                    .stockAppMarkersWithoutDeclaredReference(markerCount: summary.stockAppMarkerCount)
            }
        } else if summary.stockAppMarkerCount == 0 {
            throw PassiveBluetoothStationaryCaptureManifestError
                .stockAppReferenceDeclaredWithoutMarkers
        }

        return PassiveBluetoothStationaryCaptureManifest(
            schemaVersion: schemaVersion,
            experimentKind: .stationaryBaseline,
            experimentID: experimentID,
            experimentRecipeID: experimentRecipeID,
            preparedAt: preparedAt,
            nembraBuildIdentifier: buildIdentifier,
            nembraBuildInstanceID: buildInstanceID,
            nembraBuildCommitSHA: buildCommit,
            setup: setup,
            sourceArtifact: .init(
                sha256: sha256Hex(of: captureJSON),
                byteCount: captureJSON.count,
                captureSessionID: session.id,
                selectedPeripheralIdentifier: selectedPeripheral
            ),
            evidenceSummary: summary
        )
    }

    fileprivate static func sha256Hex(of data: Data) -> String {
        SHA256.hash(data: data).map { byte in
            String(format: "%02x", byte)
        }.joined()
    }

    fileprivate static func validatedBuildCommitSHA(_ value: String) throws -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let allowedLengths: Set<Int> = [40, 64]
        let isHex = normalized.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 48...57, 97...102:
                true
            default:
                false
            }
        }
        guard allowedLengths.contains(normalized.count), isHex else {
            throw PassiveBluetoothStationaryCaptureManifestError.invalidBuildCommitSHA(value)
        }
        return normalized
    }

    fileprivate static func validatedBuildIdentifier(_ value: String) throws -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasControlCharacter = normalized.unicodeScalars.contains {
            CharacterSet.controlCharacters.contains($0)
        }
        guard !normalized.isEmpty, normalized.count <= 96, !hasControlCharacter else {
            throw PassiveBluetoothStationaryCaptureManifestError.invalidBuildIdentifier(value)
        }
        return normalized
    }

    fileprivate static func validatedBuildInstanceID(_ value: String) throws -> String {
        let normalized = value.lowercased()
        guard normalized.utf8.count == 36 else {
            throw PassiveBluetoothStationaryCaptureManifestError.invalidBuildInstanceID(value)
        }

        let bytes = Array(normalized.utf8)
        let hyphenOffsets: Set<Int> = [8, 13, 18, 23]
        for (offset, byte) in bytes.enumerated() {
            if hyphenOffsets.contains(offset) {
                guard byte == 45 else {
                    throw PassiveBluetoothStationaryCaptureManifestError.invalidBuildInstanceID(value)
                }
            } else {
                guard (48...57).contains(byte) || (97...102).contains(byte) else {
                    throw PassiveBluetoothStationaryCaptureManifestError.invalidBuildInstanceID(value)
                }
            }
        }
        return normalized
    }

    fileprivate static func canonicalPeripheralIdentifier(
        _ value: String,
        captured: Bool
    ) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let identifier = UUID(uuidString: trimmed) else {
            if captured {
                throw PassiveBluetoothStationaryCaptureManifestError
                    .invalidCapturedPeripheralIdentifier(value)
            }
            throw PassiveBluetoothStationaryCaptureManifestError
                .invalidSelectedPeripheralIdentifier(value)
        }
        return identifier.uuidString
    }

    fileprivate static func summarize(
        session: PassiveBluetoothCaptureSession,
        selectedPeripheral: String
    ) throws -> PassiveBluetoothStationaryCaptureManifest.EvidenceSummary {
        var availableGATTPeripherals = Set<String>()
        var targetGATTRecordCount = 0
        var targetValueRecordCount = 0
        var stockAppMarkerCount = 0
        var continuityBreakCount = 0

        func canonicalCaptured(_ value: String) throws -> String {
            try canonicalPeripheralIdentifier(value, captured: true)
        }

        for record in session.records {
            if record.event.breaksByteContinuity {
                continuityBreakCount += 1
            }

            switch record.event {
            case let .service(observation):
                let peripheral = try canonicalCaptured(observation.peripheralIdentifier)
                availableGATTPeripherals.insert(peripheral)
                if peripheral == selectedPeripheral { targetGATTRecordCount += 1 }
            case let .includedService(observation):
                let peripheral = try canonicalCaptured(observation.peripheralIdentifier)
                availableGATTPeripherals.insert(peripheral)
                if peripheral == selectedPeripheral { targetGATTRecordCount += 1 }
            case let .characteristic(observation):
                let peripheral = try canonicalCaptured(observation.peripheralIdentifier)
                availableGATTPeripherals.insert(peripheral)
                if peripheral == selectedPeripheral { targetGATTRecordCount += 1 }
            case let .descriptor(observation):
                let peripheral = try canonicalCaptured(observation.peripheralIdentifier)
                availableGATTPeripherals.insert(peripheral)
                if peripheral == selectedPeripheral { targetGATTRecordCount += 1 }
            case let .subscription(observation):
                let peripheral = try canonicalCaptured(observation.peripheralIdentifier)
                availableGATTPeripherals.insert(peripheral)
                if peripheral == selectedPeripheral { targetGATTRecordCount += 1 }
            case let .value(observation):
                let peripheral = try canonicalCaptured(observation.peripheralIdentifier)
                availableGATTPeripherals.insert(peripheral)
                if peripheral == selectedPeripheral {
                    targetGATTRecordCount += 1
                    targetValueRecordCount += 1
                }
            case .stockAppState:
                stockAppMarkerCount += 1
            case .connection, .interruption:
                continue
            case .advertisement:
                continue
            }
        }

        let available = availableGATTPeripherals.sorted()
        guard !available.isEmpty else {
            throw PassiveBluetoothStationaryCaptureManifestError.noTargetGATTEvidence
        }
        guard available.contains(selectedPeripheral) else {
            throw PassiveBluetoothStationaryCaptureManifestError.selectedPeripheralNotPresent(
                requested: selectedPeripheral,
                available: available
            )
        }
        guard available.count == 1 else {
            throw PassiveBluetoothStationaryCaptureManifestError
                .ambiguousTargetGATTEvidence(available)
        }

        return .init(
            targetGATTRecordCount: targetGATTRecordCount,
            targetValueRecordCount: targetValueRecordCount,
            stockAppMarkerCount: stockAppMarkerCount,
            continuityBreakCount: continuityBreakCount
        )
    }
}

public enum PassiveBluetoothStationaryCaptureManifestJSON {
    private struct VersionProbe: Decodable {
        let schemaVersion: Int
    }

    fileprivate struct SourceArtifactWire: Codable {
        let sha256: String
        let byteCount: Int
        let captureSessionID: UUID
        let selectedPeripheralIdentifier: String
    }

    fileprivate struct EvidenceSummaryWire: Codable {
        let targetGATTRecordCount: Int
        let targetValueRecordCount: Int
        let stockAppMarkerCount: Int
        let continuityBreakCount: Int
    }

    private struct WireV1: Codable {
        let schemaVersion: Int
        let experimentKind: PassiveBluetoothStationaryCaptureExperimentKind
        let experimentID: UUID
        let preparedAt: Date
        let nembraBuildCommitSHA: String
        let setup: PassiveBluetoothStationaryCaptureSetup
        let sourceArtifact: SourceArtifactWire
        let evidenceSummary: EvidenceSummaryWire

        init(_ manifest: PassiveBluetoothStationaryCaptureManifest) {
            schemaVersion = manifest.schemaVersion
            experimentKind = manifest.experimentKind
            experimentID = manifest.experimentID
            preparedAt = manifest.preparedAt
            nembraBuildCommitSHA = manifest.nembraBuildCommitSHA
            setup = manifest.setup
            sourceArtifact = .init(manifest.sourceArtifact)
            evidenceSummary = .init(manifest.evidenceSummary)
        }

        func exactManifest() -> PassiveBluetoothStationaryCaptureManifest {
            PassiveBluetoothStationaryCaptureManifest(
                schemaVersion: schemaVersion,
                experimentKind: experimentKind,
                experimentID: experimentID,
                experimentRecipeID: nil,
                preparedAt: preparedAt,
                nembraBuildIdentifier: nil,
                nembraBuildInstanceID: nil,
                nembraBuildCommitSHA: nembraBuildCommitSHA,
                setup: setup,
                sourceArtifact: sourceArtifact.exactArtifact,
                evidenceSummary: evidenceSummary.exactSummary
            )
        }
    }

    private struct WireV2: Codable {
        let schemaVersion: Int
        let experimentKind: PassiveBluetoothStationaryCaptureExperimentKind
        let experimentID: UUID
        let experimentRecipeID: PassiveBluetoothExperimentRecipeID
        let preparedAt: Date
        let nembraBuildIdentifier: String
        let nembraBuildCommitSHA: String
        let setup: PassiveBluetoothStationaryCaptureSetup
        let sourceArtifact: SourceArtifactWire
        let evidenceSummary: EvidenceSummaryWire

        init(_ manifest: PassiveBluetoothStationaryCaptureManifest) throws {
            guard let experimentRecipeID = manifest.experimentRecipeID,
                  let nembraBuildIdentifier = manifest.nembraBuildIdentifier,
                  manifest.nembraBuildInstanceID == nil else {
                throw PassiveBluetoothStationaryCaptureManifestError.manifestDoesNotMatchCapture
            }
            schemaVersion = manifest.schemaVersion
            experimentKind = manifest.experimentKind
            experimentID = manifest.experimentID
            self.experimentRecipeID = experimentRecipeID
            preparedAt = manifest.preparedAt
            self.nembraBuildIdentifier = nembraBuildIdentifier
            nembraBuildCommitSHA = manifest.nembraBuildCommitSHA
            setup = manifest.setup
            sourceArtifact = .init(manifest.sourceArtifact)
            evidenceSummary = .init(manifest.evidenceSummary)
        }

        func exactManifest() -> PassiveBluetoothStationaryCaptureManifest {
            PassiveBluetoothStationaryCaptureManifest(
                schemaVersion: schemaVersion,
                experimentKind: experimentKind,
                experimentID: experimentID,
                experimentRecipeID: experimentRecipeID,
                preparedAt: preparedAt,
                nembraBuildIdentifier: nembraBuildIdentifier,
                nembraBuildInstanceID: nil,
                nembraBuildCommitSHA: nembraBuildCommitSHA,
                setup: setup,
                sourceArtifact: sourceArtifact.exactArtifact,
                evidenceSummary: evidenceSummary.exactSummary
            )
        }
    }

    private struct WireV3: Codable {
        let schemaVersion: Int
        let experimentKind: PassiveBluetoothStationaryCaptureExperimentKind
        let experimentID: UUID
        let experimentRecipeID: PassiveBluetoothExperimentRecipeID
        let preparedAt: Date
        let nembraBuildIdentifier: String
        let nembraBuildInstanceID: String
        let nembraBuildCommitSHA: String
        let setup: PassiveBluetoothStationaryCaptureSetup
        let sourceArtifact: SourceArtifactWire
        let evidenceSummary: EvidenceSummaryWire

        init(_ manifest: PassiveBluetoothStationaryCaptureManifest) throws {
            guard let experimentRecipeID = manifest.experimentRecipeID,
                  let nembraBuildIdentifier = manifest.nembraBuildIdentifier,
                  let nembraBuildInstanceID = manifest.nembraBuildInstanceID else {
                throw PassiveBluetoothStationaryCaptureManifestError.manifestDoesNotMatchCapture
            }
            schemaVersion = manifest.schemaVersion
            experimentKind = manifest.experimentKind
            experimentID = manifest.experimentID
            self.experimentRecipeID = experimentRecipeID
            preparedAt = manifest.preparedAt
            self.nembraBuildIdentifier = nembraBuildIdentifier
            self.nembraBuildInstanceID = nembraBuildInstanceID
            nembraBuildCommitSHA = manifest.nembraBuildCommitSHA
            setup = manifest.setup
            sourceArtifact = .init(manifest.sourceArtifact)
            evidenceSummary = .init(manifest.evidenceSummary)
        }

        func exactManifest() -> PassiveBluetoothStationaryCaptureManifest {
            PassiveBluetoothStationaryCaptureManifest(
                schemaVersion: schemaVersion,
                experimentKind: experimentKind,
                experimentID: experimentID,
                experimentRecipeID: experimentRecipeID,
                preparedAt: preparedAt,
                nembraBuildIdentifier: nembraBuildIdentifier,
                nembraBuildInstanceID: nembraBuildInstanceID,
                nembraBuildCommitSHA: nembraBuildCommitSHA,
                setup: setup,
                sourceArtifact: sourceArtifact.exactArtifact,
                evidenceSummary: evidenceSummary.exactSummary
            )
        }
    }

    private static let commonTopLevelKeys: Set<String> = [
        "schemaVersion", "experimentKind", "experimentID", "preparedAt",
        "nembraBuildCommitSHA", "setup", "sourceArtifact", "evidenceSummary",
    ]

    private static func validateSchemaShape(_ data: Data) throws {
        if let duplicatePath = PassiveBluetoothStationaryCaptureManifestStrictJSON
            .duplicateObjectKeyPath(in: data) {
            throw PassiveBluetoothStationaryCaptureManifestError
                .duplicateManifestField(duplicatePath)
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        guard let schemaVersion = root["schemaVersion"] as? Int else {
            return
        }

        let allowedTopLevel: Set<String>
        switch schemaVersion {
        case 1:
            allowedTopLevel = commonTopLevelKeys
        case 2:
            allowedTopLevel = commonTopLevelKeys.union([
                "experimentRecipeID", "nembraBuildIdentifier",
            ])
        case 3:
            allowedTopLevel = commonTopLevelKeys.union([
                "experimentRecipeID", "nembraBuildIdentifier", "nembraBuildInstanceID",
            ])
        default:
            throw PassiveBluetoothStationaryCaptureManifestError.unsupportedSchemaVersion(schemaVersion)
        }

        try rejectUnexpectedKeys(in: root, allowed: allowedTopLevel, path: "")

        if let setup = root["setup"] as? [String: Any] {
            try rejectUnexpectedKeys(
                in: setup,
                allowed: ["chargerState", "executionContext", "stockAppReferenceSetup"],
                path: "setup"
            )
        }
        if let sourceArtifact = root["sourceArtifact"] as? [String: Any] {
            try rejectUnexpectedKeys(
                in: sourceArtifact,
                allowed: ["sha256", "byteCount", "captureSessionID", "selectedPeripheralIdentifier"],
                path: "sourceArtifact"
            )
        }
        if let evidenceSummary = root["evidenceSummary"] as? [String: Any] {
            try rejectUnexpectedKeys(
                in: evidenceSummary,
                allowed: [
                    "targetGATTRecordCount", "targetValueRecordCount",
                    "stockAppMarkerCount", "continuityBreakCount",
                ],
                path: "evidenceSummary"
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
            throw PassiveBluetoothStationaryCaptureManifestError
                .unexpectedManifestField(qualified)
        }
    }

    public static func encode(
        _ manifest: PassiveBluetoothStationaryCaptureManifest,
        prettyPrinted: Bool = true
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = prettyPrinted ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        switch manifest.schemaVersion {
        case 1:
            return try encoder.encode(WireV1(manifest))
        case 2:
            return try encoder.encode(WireV2(manifest))
        case 3:
            return try encoder.encode(WireV3(manifest))
        default:
            throw PassiveBluetoothStationaryCaptureManifestError
                .unsupportedSchemaVersion(manifest.schemaVersion)
        }
    }

    /// Verifies capture binding against the exact immutable capture bytes. Build/procedure fields are
    /// schema-validated declarations; cryptographic authorization of the field build is a separate layer.
    public static func verifyCaptureBinding(
        manifestJSON: Data,
        captureJSON: Data
    ) throws -> PassiveBluetoothStationaryCaptureManifest {
        try validateSchemaShape(manifestJSON)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let version = try decoder.decode(VersionProbe.self, from: manifestJSON).schemaVersion

        switch version {
        case 1:
            let wire = try decoder.decode(WireV1.self, from: manifestJSON)
            let rebuilt = try PassiveBluetoothStationaryCaptureManifestBuilder.makeValidated(
                schemaVersion: 1,
                captureJSON: captureJSON,
                experimentID: wire.experimentID,
                experimentRecipeID: nil,
                preparedAt: wire.preparedAt,
                nembraBuildIdentifier: nil,
                nembraBuildInstanceID: nil,
                nembraBuildCommitSHA: wire.nembraBuildCommitSHA,
                selectedPeripheralIdentifier: wire.sourceArtifact.selectedPeripheralIdentifier,
                setup: wire.setup
            )
            guard rebuilt == wire.exactManifest() else {
                throw PassiveBluetoothStationaryCaptureManifestError.manifestDoesNotMatchCapture
            }
            return rebuilt
        case 2:
            let wire = try decoder.decode(WireV2.self, from: manifestJSON)
            let rebuilt = try PassiveBluetoothStationaryCaptureManifestBuilder.makeValidated(
                schemaVersion: 2,
                captureJSON: captureJSON,
                experimentID: wire.experimentID,
                experimentRecipeID: wire.experimentRecipeID,
                preparedAt: wire.preparedAt,
                nembraBuildIdentifier: wire.nembraBuildIdentifier,
                nembraBuildInstanceID: nil,
                nembraBuildCommitSHA: wire.nembraBuildCommitSHA,
                selectedPeripheralIdentifier: wire.sourceArtifact.selectedPeripheralIdentifier,
                setup: wire.setup
            )
            guard rebuilt == wire.exactManifest() else {
                throw PassiveBluetoothStationaryCaptureManifestError.manifestDoesNotMatchCapture
            }
            return rebuilt
        case 3:
            let wire = try decoder.decode(WireV3.self, from: manifestJSON)
            let rebuilt = try PassiveBluetoothStationaryCaptureManifestBuilder.makeValidated(
                schemaVersion: 3,
                captureJSON: captureJSON,
                experimentID: wire.experimentID,
                experimentRecipeID: wire.experimentRecipeID,
                preparedAt: wire.preparedAt,
                nembraBuildIdentifier: wire.nembraBuildIdentifier,
                nembraBuildInstanceID: wire.nembraBuildInstanceID,
                nembraBuildCommitSHA: wire.nembraBuildCommitSHA,
                selectedPeripheralIdentifier: wire.sourceArtifact.selectedPeripheralIdentifier,
                setup: wire.setup
            )
            guard rebuilt == wire.exactManifest() else {
                throw PassiveBluetoothStationaryCaptureManifestError.manifestDoesNotMatchCapture
            }
            return rebuilt
        default:
            throw PassiveBluetoothStationaryCaptureManifestError.unsupportedSchemaVersion(version)
        }
    }
}

private extension PassiveBluetoothStationaryCaptureManifestJSON.SourceArtifactWire {
    init(_ source: PassiveBluetoothStationaryCaptureManifest.SourceArtifact) {
        sha256 = source.sha256
        byteCount = source.byteCount
        captureSessionID = source.captureSessionID
        selectedPeripheralIdentifier = source.selectedPeripheralIdentifier
    }

    var exactArtifact: PassiveBluetoothStationaryCaptureManifest.SourceArtifact {
        .init(
            sha256: sha256,
            byteCount: byteCount,
            captureSessionID: captureSessionID,
            selectedPeripheralIdentifier: selectedPeripheralIdentifier
        )
    }
}

private extension PassiveBluetoothStationaryCaptureManifestJSON.EvidenceSummaryWire {
    init(_ summary: PassiveBluetoothStationaryCaptureManifest.EvidenceSummary) {
        targetGATTRecordCount = summary.targetGATTRecordCount
        targetValueRecordCount = summary.targetValueRecordCount
        stockAppMarkerCount = summary.stockAppMarkerCount
        continuityBreakCount = summary.continuityBreakCount
    }

    var exactSummary: PassiveBluetoothStationaryCaptureManifest.EvidenceSummary {
        .init(
            targetGATTRecordCount: targetGATTRecordCount,
            targetValueRecordCount: targetValueRecordCount,
            stockAppMarkerCount: stockAppMarkerCount,
            continuityBreakCount: continuityBreakCount
        )
    }
}
