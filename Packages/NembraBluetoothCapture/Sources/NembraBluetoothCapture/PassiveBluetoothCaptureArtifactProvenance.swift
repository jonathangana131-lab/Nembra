import CryptoKit
import Foundation
import NembraCore

private struct PassiveBluetoothCaptureArtifactSchemaProbe: Decodable {
    let schemaVersion: Int
}

/// Validation errors for the operator-supplied provenance sidecar that travels
/// with one immutable passive-capture JSON artifact.
public enum PassiveBluetoothCaptureArtifactProvenanceError: Error, Equatable, Sendable {
    case unsupportedSchemaVersion(Int)
    case invalidSourceArtifactDigest
    case invalidSourceArtifactByteCount
    case invalidSourceCaptureSchemaVersion
    case sourceArtifactMismatch
    case invalidNembraSourceRevision
    case emptyAppVersion
    case emptyAppBuild
    case emptySelectedPeripheralIdentifier
    case selectedPeripheralNotAttributable(requested: String, available: [String])
    case emptyPhysicalCorrelationNote
    case emptyResearchSetupNote
    case emptyAcquisitionFailureNote
}

/// A versioned sidecar for physical-capture provenance that deliberately stays
/// outside the immutable raw capture schema.
///
/// The sidecar binds operator-supplied build/setup context to the exact source
/// JSON bytes with SHA-256. Neither the digest nor these notes authenticate the
/// scooter, prove recorder identity, establish chain of custody, or verify any
/// ES80 protocol/telemetry meaning.
public struct PassiveBluetoothCaptureArtifactProvenance: Equatable, Codable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let sourceArtifact: SourceArtifactSummary
    public let nembraBuild: NembraBuildIdentity
    public let selectedTarget: SelectedTarget
    public let researchSetup: ResearchSetup

    /// Wall-clock time when this metadata sidecar was created. It is metadata,
    /// not a replacement for the raw capture's monotonic receipt clocks.
    public let createdAt: Date

    public struct SourceArtifactSummary: Equatable, Codable, Sendable {
        public let sha256: String
        public let byteCount: Int
        public let captureSchemaVersion: Int
        public let sessionID: UUID
        public let sessionStartedAt: Date
    }

    public struct NembraBuildIdentity: Equatable, Codable, Sendable {
        /// Exact Git object ID for the Nembra source used to make the capture.
        /// A branch name such as `main` is intentionally rejected.
        public let sourceRevision: String
        public let appVersion: String?
        public let appBuild: String?
    }

    public struct SelectedTarget: Equatable, Codable, Sendable {
        /// Exact opaque CoreBluetooth peripheral identifier recorded by Nembra.
        /// This remains observed attribution evidence, not permanent scooter ID.
        public let peripheralIdentifier: String

        /// Operator-supplied description of the legitimate physical correlation
        /// used to choose this target. It is not converted into protocol truth.
        public let physicalCorrelationNote: String
    }

    public struct ResearchSetup: Equatable, Codable, Sendable {
        /// Operator-supplied physical state/setup (for example stationary versus
        /// moving, charger state, visible reference state, and observer layout).
        public let physicalStateNote: String

        /// Optional operator note for an incomplete/discarded acquisition. Its
        /// presence does not repair missing raw evidence or make absence claims.
        public let acquisitionFailureNote: String?
    }

    /// Deterministic JSON for durable review/export. Dates use the same
    /// millisecond epoch convention as the raw passive-capture codec.
    public func jsonData(prettyPrinted: Bool = true) throws -> Data {
        try validate()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = prettyPrinted ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return try encoder.encode(self)
    }

    /// Decode a sidecar through the version/truth gates instead of accepting a
    /// synthesized `Codable` value as durable evidence without validation.
    public static func decodeJSON(_ data: Data) throws -> Self {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let value = try decoder.decode(Self.self, from: data)
        try value.validate()
        return value
    }

    /// Re-check that this sidecar still belongs to these exact raw capture bytes.
    /// A match establishes artifact association only; it does not authenticate a
    /// scooter or promote any physical/protocol claim.
    public func matchesSourceArtifact(_ captureJSON: Data) throws -> Bool {
        try validate()
        let session = try PassiveBluetoothCaptureJSON.decode(captureJSON)
        let captureSchemaVersion = try JSONDecoder()
            .decode(PassiveBluetoothCaptureArtifactSchemaProbe.self, from: captureJSON)
            .schemaVersion

        return sourceArtifact.sha256
                == PassiveBluetoothCaptureArtifactProvenanceBuilder.sha256Hex(of: captureJSON)
            && sourceArtifact.byteCount == captureJSON.count
            && sourceArtifact.captureSchemaVersion == captureSchemaVersion
            && sourceArtifact.sessionID == session.id
            && sourceArtifact.sessionStartedAt == session.startedAt
    }

    fileprivate func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw PassiveBluetoothCaptureArtifactProvenanceError
                .unsupportedSchemaVersion(schemaVersion)
        }
        guard Self.isLowercaseSHA256(sourceArtifact.sha256) else {
            throw PassiveBluetoothCaptureArtifactProvenanceError.invalidSourceArtifactDigest
        }
        guard sourceArtifact.byteCount >= 0 else {
            throw PassiveBluetoothCaptureArtifactProvenanceError.invalidSourceArtifactByteCount
        }
        guard sourceArtifact.captureSchemaVersion > 0 else {
            throw PassiveBluetoothCaptureArtifactProvenanceError.invalidSourceCaptureSchemaVersion
        }
        guard Self.isExactGitObjectID(nembraBuild.sourceRevision) else {
            throw PassiveBluetoothCaptureArtifactProvenanceError.invalidNembraSourceRevision
        }
        try Self.validateOptionalNonblank(
            nembraBuild.appVersion,
            error: .emptyAppVersion
        )
        try Self.validateOptionalNonblank(
            nembraBuild.appBuild,
            error: .emptyAppBuild
        )
        guard Self.isExactNonblank(selectedTarget.peripheralIdentifier) else {
            throw PassiveBluetoothCaptureArtifactProvenanceError.emptySelectedPeripheralIdentifier
        }
        guard !selectedTarget.physicalCorrelationNote
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PassiveBluetoothCaptureArtifactProvenanceError.emptyPhysicalCorrelationNote
        }
        guard !researchSetup.physicalStateNote
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PassiveBluetoothCaptureArtifactProvenanceError.emptyResearchSetupNote
        }
        try Self.validateOptionalNonblank(
            researchSetup.acquisitionFailureNote,
            error: .emptyAcquisitionFailureNote
        )
    }

    private static func validateOptionalNonblank(
        _ value: String?,
        error: PassiveBluetoothCaptureArtifactProvenanceError
    ) throws {
        guard let value else { return }
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw error
        }
    }

    fileprivate static func isExactNonblank(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed == value
    }

    fileprivate static func isExactGitObjectID(_ value: String) -> Bool {
        guard value.count == 40 || value.count == 64 else { return false }
        return value.utf8.allSatisfy { byte in
            (48...57).contains(byte) || (97...102).contains(byte)
        }
    }

    private static func isLowercaseSHA256(_ value: String) -> Bool {
        guard value.count == 64 else { return false }
        return value.utf8.allSatisfy { byte in
            (48...57).contains(byte) || (97...102).contains(byte)
        }
    }
}

public enum PassiveBluetoothCaptureArtifactProvenanceBuilder {
    /// Build provenance from the exact raw JSON bytes. The selected peripheral
    /// must already appear in target-attributable connection/GATT/value evidence;
    /// advertisement-only catalog evidence is deliberately insufficient.
    public static func make(
        captureJSON: Data,
        nembraSourceRevision: String,
        appVersion: String? = nil,
        appBuild: String? = nil,
        selectedPeripheralIdentifier: String,
        physicalCorrelationNote: String,
        researchSetupNote: String,
        acquisitionFailureNote: String? = nil,
        createdAt: Date = .now
    ) throws -> PassiveBluetoothCaptureArtifactProvenance {
        guard PassiveBluetoothCaptureArtifactProvenance
            .isExactNonblank(selectedPeripheralIdentifier) else {
            throw PassiveBluetoothCaptureArtifactProvenanceError.emptySelectedPeripheralIdentifier
        }
        guard PassiveBluetoothCaptureArtifactProvenance
            .isExactGitObjectID(nembraSourceRevision) else {
            throw PassiveBluetoothCaptureArtifactProvenanceError.invalidNembraSourceRevision
        }

        let session = try PassiveBluetoothCaptureJSON.decode(captureJSON)
        let captureSchemaVersion = try JSONDecoder()
            .decode(PassiveBluetoothCaptureArtifactSchemaProbe.self, from: captureJSON)
            .schemaVersion

        let available = attributablePeripheralIdentifiers(in: session)
        guard available.contains(selectedPeripheralIdentifier) else {
            throw PassiveBluetoothCaptureArtifactProvenanceError
                .selectedPeripheralNotAttributable(
                    requested: selectedPeripheralIdentifier,
                    available: available
                )
        }

        let value = PassiveBluetoothCaptureArtifactProvenance(
            schemaVersion: PassiveBluetoothCaptureArtifactProvenance.currentSchemaVersion,
            sourceArtifact: .init(
                sha256: sha256Hex(of: captureJSON),
                byteCount: captureJSON.count,
                captureSchemaVersion: captureSchemaVersion,
                sessionID: session.id,
                sessionStartedAt: session.startedAt
            ),
            nembraBuild: .init(
                sourceRevision: nembraSourceRevision,
                appVersion: appVersion,
                appBuild: appBuild
            ),
            selectedTarget: .init(
                peripheralIdentifier: selectedPeripheralIdentifier,
                physicalCorrelationNote: physicalCorrelationNote
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            ),
            researchSetup: .init(
                physicalStateNote: researchSetupNote
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                acquisitionFailureNote: acquisitionFailureNote.map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            ),
            createdAt: createdAt
        )
        try value.validate()
        return value
    }

    public static func sha256Hex(of data: Data) -> String {
        SHA256.hash(data: data).map { byte in
            String(format: "%02x", byte)
        }.joined()
    }

    /// Deliberately excludes advertisement-only sightings. A broad-scan
    /// candidate is catalog evidence, not selected-target capture attribution.
    public static func attributablePeripheralIdentifiers(
        in session: PassiveBluetoothCaptureSession
    ) -> [String] {
        var identifiers = Set<String>()

        for record in session.records {
            switch record.event {
            case .advertisement, .stockAppState, .interruption:
                break
            case let .connection(observation):
                identifiers.insert(observation.peripheralIdentifier)
            case let .service(observation):
                identifiers.insert(observation.peripheralIdentifier)
            case let .includedService(observation):
                identifiers.insert(observation.peripheralIdentifier)
            case let .characteristic(observation):
                identifiers.insert(observation.peripheralIdentifier)
            case let .descriptor(observation):
                identifiers.insert(observation.peripheralIdentifier)
            case let .subscription(observation):
                identifiers.insert(observation.peripheralIdentifier)
            case let .value(observation):
                identifiers.insert(observation.peripheralIdentifier)
            }
        }

        return identifiers.sorted()
    }
}
