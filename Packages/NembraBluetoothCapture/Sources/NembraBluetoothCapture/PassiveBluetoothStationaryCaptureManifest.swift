import CryptoKit
import Foundation
import NembraCore

/// Declared experiment-context binding for the first stationary physical ES80 capture.
///
/// This sidecar never changes the raw capture JSON. It retains structured procedure/setup
/// provenance next to those exact immutable bytes. Operator declarations are not independently
/// authenticated by the capture and must never be promoted into physical or protocol truth.
public enum PassiveBluetoothStationaryCaptureManifestError: Error, Equatable, Sendable {
    case invalidBuildCommitSHA(String)
    case invalidPreparedAt
    case invalidSelectedPeripheralIdentifier(String)
    case invalidCapturedPeripheralIdentifier(String)
    case noTargetGATTEvidence
    case selectedPeripheralNotPresent(requested: String, available: [String])
    case ambiguousTargetGATTEvidence([String])
    case stockAppMarkersWithoutDeclaredReference(markerCount: Int)
    case unsupportedSchemaVersion(Int)
    case unexpectedManifestField(String)
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

/// Operator-declared execution conditions. This is provenance, not OS attestation.
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

/// Capture-consistent sidecar projection for the first stationary physical-capture artifact.
///
/// Schema v2 adds an exact stable experiment-recipe identifier. This records which sealed Nembra
/// procedure the product intended to run; it is not evidence that the operator completed its steps.
public struct PassiveBluetoothStationaryCaptureManifest: Equatable, Sendable {
    public static let currentSchemaVersion = 2

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
        /// Every structured disconnect plus every generic interruption marker according to
        /// `PassiveBluetoothCaptureEvent.breaksByteContinuity`.
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
    public let recipeID: PassiveBluetoothExperimentRecipeID
    public let experimentID: UUID
    public let preparedAt: Date
    public let nembraBuildCommitSHA: String
    public let setup: PassiveBluetoothStationaryCaptureSetup
    public let sourceArtifact: SourceArtifact
    public let evidenceSummary: EvidenceSummary

    fileprivate init(
        schemaVersion: Int,
        experimentKind: PassiveBluetoothStationaryCaptureExperimentKind,
        recipeID: PassiveBluetoothExperimentRecipeID,
        experimentID: UUID,
        preparedAt: Date,
        nembraBuildCommitSHA: String,
        setup: PassiveBluetoothStationaryCaptureSetup,
        sourceArtifact: SourceArtifact,
        evidenceSummary: EvidenceSummary
    ) {
        self.schemaVersion = schemaVersion
        self.experimentKind = experimentKind
        self.recipeID = recipeID
        self.experimentID = experimentID
        self.preparedAt = preparedAt
        self.nembraBuildCommitSHA = nembraBuildCommitSHA
        self.setup = setup
        self.sourceArtifact = sourceArtifact
        self.evidenceSummary = evidenceSummary
    }
}

public enum PassiveBluetoothStationaryCaptureManifestBuilder {
    /// Creates the schema-v2 sidecar for the first stationary ES80 fingerprint procedure.
    ///
    /// `recipe` defaults to the sealed `ES80-FINGERPRINT-v1` contract so existing mechanical
    /// callers cannot accidentally produce a recipe-less V14 manifest. The recipe object itself
    /// has a private constructor, so callers cannot forge the official ID with altered ordering.
    public static func make(
        captureJSON: Data,
        experimentID: UUID = UUID(),
        preparedAt: Date = Date(),
        nembraBuildCommitSHA: String,
        selectedPeripheralIdentifier: String,
        setup: PassiveBluetoothStationaryCaptureSetup,
        recipe: PassiveBluetoothExperimentRecipe = .es80FingerprintV1
    ) throws -> PassiveBluetoothStationaryCaptureManifest {
        let buildCommit = try validatedBuildCommitSHA(nembraBuildCommitSHA)
        guard preparedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw PassiveBluetoothStationaryCaptureManifestError.invalidPreparedAt
        }

        let selectedPeripheral = try canonicalPeripheralIdentifier(
            selectedPeripheralIdentifier,
            captured: false
        )
        let session = try PassiveBluetoothCaptureJSON.decode(captureJSON)
        let summary = try summarize(session: session, selectedPeripheral: selectedPeripheral)
        if setup.stockAppReferenceSetup == .none, summary.stockAppMarkerCount > 0 {
            throw PassiveBluetoothStationaryCaptureManifestError
                .stockAppMarkersWithoutDeclaredReference(markerCount: summary.stockAppMarkerCount)
        }

        return PassiveBluetoothStationaryCaptureManifest(
            schemaVersion: PassiveBluetoothStationaryCaptureManifest.currentSchemaVersion,
            experimentKind: .stationaryBaseline,
            recipeID: recipe.id,
            experimentID: experimentID,
            preparedAt: preparedAt,
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
    private struct SourceArtifactWire: Codable {
        let sha256: String
        let byteCount: Int
        let captureSessionID: UUID
        let selectedPeripheralIdentifier: String
    }

    private struct EvidenceSummaryWire: Codable {
        let targetGATTRecordCount: Int
        let targetValueRecordCount: Int
        let stockAppMarkerCount: Int
        let continuityBreakCount: Int
    }

    private struct Wire: Codable {
        let schemaVersion: Int
        let experimentKind: PassiveBluetoothStationaryCaptureExperimentKind
        let recipeID: PassiveBluetoothExperimentRecipeID
        let experimentID: UUID
        let preparedAt: Date
        let nembraBuildCommitSHA: String
        let setup: PassiveBluetoothStationaryCaptureSetup
        let sourceArtifact: SourceArtifactWire
        let evidenceSummary: EvidenceSummaryWire

        init(_ manifest: PassiveBluetoothStationaryCaptureManifest) {
            schemaVersion = manifest.schemaVersion
            experimentKind = manifest.experimentKind
            recipeID = manifest.recipeID
            experimentID = manifest.experimentID
            preparedAt = manifest.preparedAt
            nembraBuildCommitSHA = manifest.nembraBuildCommitSHA
            setup = manifest.setup
            sourceArtifact = .init(
                sha256: manifest.sourceArtifact.sha256,
                byteCount: manifest.sourceArtifact.byteCount,
                captureSessionID: manifest.sourceArtifact.captureSessionID,
                selectedPeripheralIdentifier: manifest.sourceArtifact.selectedPeripheralIdentifier
            )
            evidenceSummary = .init(
                targetGATTRecordCount: manifest.evidenceSummary.targetGATTRecordCount,
                targetValueRecordCount: manifest.evidenceSummary.targetValueRecordCount,
                stockAppMarkerCount: manifest.evidenceSummary.stockAppMarkerCount,
                continuityBreakCount: manifest.evidenceSummary.continuityBreakCount
            )
        }

        func exactManifest() -> PassiveBluetoothStationaryCaptureManifest {
            PassiveBluetoothStationaryCaptureManifest(
                schemaVersion: schemaVersion,
                experimentKind: experimentKind,
                recipeID: recipeID,
                experimentID: experimentID,
                preparedAt: preparedAt,
                nembraBuildCommitSHA: nembraBuildCommitSHA,
                setup: setup,
                sourceArtifact: .init(
                    sha256: sourceArtifact.sha256,
                    byteCount: sourceArtifact.byteCount,
                    captureSessionID: sourceArtifact.captureSessionID,
                    selectedPeripheralIdentifier: sourceArtifact.selectedPeripheralIdentifier
                ),
                evidenceSummary: .init(
                    targetGATTRecordCount: evidenceSummary.targetGATTRecordCount,
                    targetValueRecordCount: evidenceSummary.targetValueRecordCount,
                    stockAppMarkerCount: evidenceSummary.stockAppMarkerCount,
                    continuityBreakCount: evidenceSummary.continuityBreakCount
                )
            )
        }
    }

    private static func declaredSchemaVersion(_ data: Data) throws -> Int {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let number = root["schemaVersion"] as? NSNumber else {
            throw DecodingError.keyNotFound(
                CodingKeys.schemaVersion,
                .init(codingPath: [], debugDescription: "Manifest schemaVersion is required")
            )
        }
        return number.intValue
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
    }

    private static func validateSchemaShape(_ data: Data) throws {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        try rejectUnexpectedKeys(
            in: root,
            allowed: [
                "schemaVersion", "experimentKind", "recipeID", "experimentID", "preparedAt",
                "nembraBuildCommitSHA", "setup", "sourceArtifact", "evidenceSummary"
            ],
            path: ""
        )

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
                allowed: [
                    "sha256", "byteCount", "captureSessionID",
                    "selectedPeripheralIdentifier"
                ],
                path: "sourceArtifact"
            )
        }
        if let evidenceSummary = root["evidenceSummary"] as? [String: Any] {
            try rejectUnexpectedKeys(
                in: evidenceSummary,
                allowed: [
                    "targetGATTRecordCount", "targetValueRecordCount",
                    "stockAppMarkerCount", "continuityBreakCount"
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
        guard manifest.schemaVersion == PassiveBluetoothStationaryCaptureManifest.currentSchemaVersion else {
            throw PassiveBluetoothStationaryCaptureManifestError
                .unsupportedSchemaVersion(manifest.schemaVersion)
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = prettyPrinted ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return try encoder.encode(Wire(manifest))
    }

    /// Verifies schema-v2 procedure provenance plus capture-derived fields against the exact
    /// immutable capture bytes. Build/setup values remain declarations unless a separate trusted
    /// build/OS/physical attestation source exists.
    public static func verifyCaptureBinding(
        manifestJSON: Data,
        captureJSON: Data
    ) throws -> PassiveBluetoothStationaryCaptureManifest {
        let schemaVersion = try declaredSchemaVersion(manifestJSON)
        guard schemaVersion == PassiveBluetoothStationaryCaptureManifest.currentSchemaVersion else {
            throw PassiveBluetoothStationaryCaptureManifestError
                .unsupportedSchemaVersion(schemaVersion)
        }
        try validateSchemaShape(manifestJSON)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let wire = try decoder.decode(Wire.self, from: manifestJSON)

        let rebuilt = try PassiveBluetoothStationaryCaptureManifestBuilder.make(
            captureJSON: captureJSON,
            experimentID: wire.experimentID,
            preparedAt: wire.preparedAt,
            nembraBuildCommitSHA: wire.nembraBuildCommitSHA,
            selectedPeripheralIdentifier: wire.sourceArtifact.selectedPeripheralIdentifier,
            setup: wire.setup,
            recipe: recipe(for: wire.recipeID)
        )

        guard rebuilt == wire.exactManifest() else {
            throw PassiveBluetoothStationaryCaptureManifestError.manifestDoesNotMatchCapture
        }
        return rebuilt
    }

    private static func recipe(
        for id: PassiveBluetoothExperimentRecipeID
    ) -> PassiveBluetoothExperimentRecipe {
        switch id {
        case .es80FingerprintV1:
            .es80FingerprintV1
        }
    }
}
