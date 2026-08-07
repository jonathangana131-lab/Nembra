import CryptoKit
import Foundation
import NembraCore

/// Operator-context validation for the first stationary physical ES80 capture.
///
/// This sidecar never changes the raw capture JSON. It binds a small amount of
/// structured setup context to the exact immutable capture bytes so later
/// offline analysis can tell which build/setup produced the evidence without
/// reinterpreting that context as scooter telemetry.
public enum PassiveBluetoothStationaryCaptureManifestError: Error, Equatable, Sendable {
    case invalidBuildCommitSHA(String)
    case invalidPreparedAt
    case invalidSelectedPeripheralIdentifier(String)
    case invalidCapturedPeripheralIdentifier(String)
    case noTargetGATTEvidence
    case selectedPeripheralNotPresent(requested: String, available: [String])
    case ambiguousTargetGATTEvidence([String])
    case unsupportedSchemaVersion(Int)
    case manifestDoesNotMatchCapture
}

public enum PassiveBluetoothStationaryCaptureReferenceSetup: String, Codable, Sendable {
    /// No stock-app reference value was used for this capture.
    case none
    /// The stock app was observed on the same phone before Nembra began capture.
    case sameDeviceBeforeCapture
    /// The stock app was observed on the same phone only after Nembra ended capture.
    case sameDeviceAfterCapture
    /// The stock app was observed on the same phone before and after capture,
    /// never represented as a simultaneous same-phone Bluetooth observation.
    case sameDeviceBeforeAndAfterCapture
    /// A physically separate observer device supplied legitimate visible stock-app references.
    case separateObserverDevice
}

public enum PassiveBluetoothStationaryCaptureChargerState: String, Codable, Sendable {
    case disconnected
    case connected
}

public struct PassiveBluetoothStationaryCaptureSetup: Equatable, Codable, Sendable {
    public let chargerState: PassiveBluetoothStationaryCaptureChargerState
    public let stockAppReferenceSetup: PassiveBluetoothStationaryCaptureReferenceSetup

    public init(
        chargerState: PassiveBluetoothStationaryCaptureChargerState,
        stockAppReferenceSetup: PassiveBluetoothStationaryCaptureReferenceSetup
    ) {
        self.chargerState = chargerState
        self.stockAppReferenceSetup = stockAppReferenceSetup
    }
}

/// A verified sidecar projection for one stationary physical-capture artifact.
///
/// Construction is intentionally sealed behind `PassiveBluetoothStationaryCaptureManifestBuilder`.
/// The SHA-256 binds the sidecar to exact capture bytes, but it is only artifact
/// integrity/provenance. It does not authenticate the scooter, prove ES80 identity,
/// or verify any battery/current/power/speed semantic.
public struct PassiveBluetoothStationaryCaptureManifest: Equatable, Sendable {
    public static let currentSchemaVersion = 1

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
        /// Target-attributable service/included-service/characteristic/descriptor/
        /// subscription/value records. Advertisement and connection records do not
        /// satisfy the target GATT gate.
        public let targetGATTRecordCount: Int
        public let targetValueRecordCount: Int
        public let stockAppMarkerCount: Int
        /// Generic interruption markers plus selected-target disconnects.
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
    public let experimentID: UUID
    public let preparedAt: Date
    public let nembraBuildCommitSHA: String
    public let setup: PassiveBluetoothStationaryCaptureSetup
    public let sourceArtifact: SourceArtifact
    public let evidenceSummary: EvidenceSummary

    fileprivate init(
        schemaVersion: Int,
        experimentID: UUID,
        preparedAt: Date,
        nembraBuildCommitSHA: String,
        setup: PassiveBluetoothStationaryCaptureSetup,
        sourceArtifact: SourceArtifact,
        evidenceSummary: EvidenceSummary
    ) {
        self.schemaVersion = schemaVersion
        self.experimentID = experimentID
        self.preparedAt = preparedAt
        self.nembraBuildCommitSHA = nembraBuildCommitSHA
        self.setup = setup
        self.sourceArtifact = sourceArtifact
        self.evidenceSummary = evidenceSummary
    }
}

public enum PassiveBluetoothStationaryCaptureManifestBuilder {
    /// Creates one machine-readable sidecar for the smallest useful physical
    /// experiment: scooter stationary, exact Nembra build known, charger state
    /// explicitly recorded, and one selected target already represented by GATT evidence.
    public static func make(
        captureJSON: Data,
        experimentID: UUID = UUID(),
        preparedAt: Date = Date(),
        nembraBuildCommitSHA: String,
        selectedPeripheralIdentifier: String,
        setup: PassiveBluetoothStationaryCaptureSetup
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

        return PassiveBluetoothStationaryCaptureManifest(
            schemaVersion: PassiveBluetoothStationaryCaptureManifest.currentSchemaVersion,
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
            case let .connection(observation):
                let peripheral = try canonicalCaptured(observation.peripheralIdentifier)
                if peripheral == selectedPeripheral, observation.state == .disconnected {
                    continuityBreakCount += 1
                }
            case .interruption:
                continuityBreakCount += 1
            case .advertisement:
                // Broad-scan candidates intentionally cannot satisfy target attribution.
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
        let experimentID: UUID
        let preparedAt: Date
        let nembraBuildCommitSHA: String
        let setup: PassiveBluetoothStationaryCaptureSetup
        let sourceArtifact: SourceArtifactWire
        let evidenceSummary: EvidenceSummaryWire

        init(_ manifest: PassiveBluetoothStationaryCaptureManifest) {
            schemaVersion = manifest.schemaVersion
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

    public static func encode(
        _ manifest: PassiveBluetoothStationaryCaptureManifest,
        prettyPrinted: Bool = true
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = prettyPrinted ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return try encoder.encode(Wire(manifest))
    }

    /// Verifies an imported sidecar against the exact immutable capture bytes.
    /// A manifest is never accepted from JSON alone because its derived counts,
    /// session identity, selected target, and digest all need the raw artifact.
    public static func verify(
        manifestJSON: Data,
        captureJSON: Data
    ) throws -> PassiveBluetoothStationaryCaptureManifest {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let wire = try decoder.decode(Wire.self, from: manifestJSON)
        guard wire.schemaVersion == PassiveBluetoothStationaryCaptureManifest.currentSchemaVersion else {
            throw PassiveBluetoothStationaryCaptureManifestError
                .unsupportedSchemaVersion(wire.schemaVersion)
        }

        let rebuilt = try PassiveBluetoothStationaryCaptureManifestBuilder.make(
            captureJSON: captureJSON,
            experimentID: wire.experimentID,
            preparedAt: wire.preparedAt,
            nembraBuildCommitSHA: wire.nembraBuildCommitSHA,
            selectedPeripheralIdentifier: wire.sourceArtifact.selectedPeripheralIdentifier,
            setup: wire.setup
        )

        guard rebuilt == wire.exactManifest() else {
            throw PassiveBluetoothStationaryCaptureManifestError.manifestDoesNotMatchCapture
        }
        return rebuilt
    }
}
