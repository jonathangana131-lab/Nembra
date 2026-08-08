import CryptoKit
import Foundation

/// Package-owned bytes for the primary Experiment One share action.
///
/// The inner `PassiveBluetoothExperimentOneSoftwareExport` remains the source of capture,
/// correlation, manifest, setup, and produced-build truth. This outer artifact binds those exact
/// verified bytes to the accepted experiment/procedure identity needed by the field workflow.
///
/// This is still software evidence only. `procedureVersion == V14` and a matching build-instance
/// rendezvous do not authorize a physical run; independent accepted field-build/GO evidence remains
/// required before `PassiveBluetoothExperimentOneFieldExecutionGate` may ever permit execution.
public struct PassiveBluetoothExperimentOneFinalShareArtifact: Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public static let artifactKind = "nembra.es80.experiment-one.final-share"
    public static let procedureVersion = "V14"

    /// Exact bytes that should be staged to disk and presented to the system share sheet.
    public let json: Data
    public let suggestedFilename: String

    fileprivate init(json: Data, suggestedFilename: String) {
        self.json = json
        self.suggestedFilename = suggestedFilename
    }
}

public struct PassiveBluetoothExperimentOneVerifiedFinalShareArtifact: Equatable, Sendable {
    public let experimentID: UUID
    public let experimentRecipeID: PassiveBluetoothExperimentRecipeID
    public let procedureVersion: String
    public let buildInstanceID: String
    public let softwareExportSHA256: String
    public let softwareExport: PassiveBluetoothExperimentOneSoftwareExport

    fileprivate init(
        experimentID: UUID,
        experimentRecipeID: PassiveBluetoothExperimentRecipeID,
        procedureVersion: String,
        buildInstanceID: String,
        softwareExportSHA256: String,
        softwareExport: PassiveBluetoothExperimentOneSoftwareExport
    ) {
        self.experimentID = experimentID
        self.experimentRecipeID = experimentRecipeID
        self.procedureVersion = procedureVersion
        self.buildInstanceID = buildInstanceID
        self.softwareExportSHA256 = softwareExportSHA256
        self.softwareExport = softwareExport
    }
}

public enum PassiveBluetoothExperimentOneFinalShareArtifactError: Error, Equatable, Sendable {
    case malformedWireData
    case unsupportedSchemaVersion(Int)
    case unexpectedArtifactKind(String)
    case unsupportedRecipe(PassiveBluetoothExperimentRecipeID)
    case unsupportedProcedureVersion(String)
    case unexpectedWireField(String)
    case softwareExportDigestMismatch
    case softwareExportRecipeMismatch
    case softwareExportExperimentMismatch
    case softwareExportBuildInstanceMismatch
}

public enum PassiveBluetoothExperimentOneFinalShareArtifactCodec {
    /// Production entry point. Runtime provenance is read by the package and cannot be rider-entered.
    public static func makeForCurrentApplication(
        finalizedArtifact: PassiveBluetoothExperimentOneCoordinator.FinalizedArtifact,
        setup: PassiveBluetoothStationaryCaptureSetup
    ) throws -> PassiveBluetoothExperimentOneFinalShareArtifact {
        try make(
            finalizedArtifact: finalizedArtifact,
            runtimeBuildIdentity: PassiveBluetoothCaptureRuntimeBuildIdentityReader.currentApplication(),
            setup: setup
        )
    }

    /// Package-only deterministic seam for executable regression tests.
    package static func make(
        finalizedArtifact: PassiveBluetoothExperimentOneCoordinator.FinalizedArtifact,
        runtimeBuildIdentity: PassiveBluetoothCaptureRuntimeBuildIdentity,
        setup: PassiveBluetoothStationaryCaptureSetup
    ) throws -> PassiveBluetoothExperimentOneFinalShareArtifact {
        let softwareExport = try PassiveBluetoothExperimentOneSoftwareExportCodec.make(
            finalizedArtifact: finalizedArtifact,
            runtimeBuildIdentity: runtimeBuildIdentity,
            setup: setup
        )
        return try make(softwareExport: softwareExport)
    }

    package static func make(
        softwareExport: PassiveBluetoothExperimentOneSoftwareExport
    ) throws -> PassiveBluetoothExperimentOneFinalShareArtifact {
        let softwareExportJSON = try PassiveBluetoothExperimentOneSoftwareExportCodec.encode(
            softwareExport,
            prettyPrinted: false
        )
        let verifiedSoftwareExport = try PassiveBluetoothExperimentOneSoftwareExportCodec
            .decodeAndVerify(softwareExportJSON)
        let manifest = try PassiveBluetoothStationaryCaptureManifestJSON.verifyCaptureBinding(
            manifestJSON: verifiedSoftwareExport.stationaryManifestJSON,
            captureJSON: verifiedSoftwareExport.captureJSON
        )
        guard let recipe = manifest.experimentRecipeID,
              recipe == verifiedSoftwareExport.experimentRecipeID else {
            throw PassiveBluetoothExperimentOneFinalShareArtifactError.softwareExportRecipeMismatch
        }

        let wire = WireV1(
            schemaVersion: PassiveBluetoothExperimentOneFinalShareArtifact.currentSchemaVersion,
            artifactKind: PassiveBluetoothExperimentOneFinalShareArtifact.artifactKind,
            experimentID: manifest.experimentID.uuidString,
            experimentRecipeID: recipe.rawValue,
            procedureVersion: PassiveBluetoothExperimentOneFinalShareArtifact.procedureVersion,
            buildInstanceID: verifiedSoftwareExport.build.buildInstanceID,
            softwareExportSHA256: sha256Hex(softwareExportJSON),
            softwareExportJSONBase64: softwareExportJSON.base64EncodedString()
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let json = try encoder.encode(wire)
        return .init(
            json: json,
            suggestedFilename: "Nembra-ES80-Fingerprint-\(manifest.experimentID.uuidString).json"
        )
    }

    public static func decodeAndVerify(
        _ data: Data
    ) throws -> PassiveBluetoothExperimentOneVerifiedFinalShareArtifact {
        try validateClosedWorldShape(data)

        let decoder = JSONDecoder()
        let wire: WireV1
        do {
            wire = try decoder.decode(WireV1.self, from: data)
        } catch {
            throw PassiveBluetoothExperimentOneFinalShareArtifactError.malformedWireData
        }

        guard wire.schemaVersion == PassiveBluetoothExperimentOneFinalShareArtifact.currentSchemaVersion else {
            throw PassiveBluetoothExperimentOneFinalShareArtifactError
                .unsupportedSchemaVersion(wire.schemaVersion)
        }
        guard wire.artifactKind == PassiveBluetoothExperimentOneFinalShareArtifact.artifactKind else {
            throw PassiveBluetoothExperimentOneFinalShareArtifactError
                .unexpectedArtifactKind(wire.artifactKind)
        }
        guard let recipe = PassiveBluetoothExperimentRecipeID(rawValue: wire.experimentRecipeID) else {
            throw PassiveBluetoothExperimentOneFinalShareArtifactError.malformedWireData
        }
        guard recipe == .es80FingerprintV1 else {
            throw PassiveBluetoothExperimentOneFinalShareArtifactError.unsupportedRecipe(recipe)
        }
        guard wire.procedureVersion == PassiveBluetoothExperimentOneFinalShareArtifact.procedureVersion else {
            throw PassiveBluetoothExperimentOneFinalShareArtifactError
                .unsupportedProcedureVersion(wire.procedureVersion)
        }
        guard let experimentID = UUID(uuidString: wire.experimentID),
              experimentID.uuidString == wire.experimentID,
              PassiveBluetoothCaptureRuntimeBuildIdentityReader
                .normalizedBuildInstanceID(wire.buildInstanceID) == wire.buildInstanceID,
              isCanonicalSHA256(wire.softwareExportSHA256),
              let softwareExportJSON = Data(base64Encoded: wire.softwareExportJSONBase64) else {
            throw PassiveBluetoothExperimentOneFinalShareArtifactError.malformedWireData
        }
        guard sha256Hex(softwareExportJSON) == wire.softwareExportSHA256 else {
            throw PassiveBluetoothExperimentOneFinalShareArtifactError.softwareExportDigestMismatch
        }

        let softwareExport = try PassiveBluetoothExperimentOneSoftwareExportCodec
            .decodeAndVerify(softwareExportJSON)
        guard softwareExport.experimentRecipeID == recipe else {
            throw PassiveBluetoothExperimentOneFinalShareArtifactError.softwareExportRecipeMismatch
        }
        guard softwareExport.build.buildInstanceID == wire.buildInstanceID else {
            throw PassiveBluetoothExperimentOneFinalShareArtifactError.softwareExportBuildInstanceMismatch
        }
        let manifest = try PassiveBluetoothStationaryCaptureManifestJSON.verifyCaptureBinding(
            manifestJSON: softwareExport.stationaryManifestJSON,
            captureJSON: softwareExport.captureJSON
        )
        guard manifest.experimentID == experimentID else {
            throw PassiveBluetoothExperimentOneFinalShareArtifactError.softwareExportExperimentMismatch
        }

        return .init(
            experimentID: experimentID,
            experimentRecipeID: recipe,
            procedureVersion: wire.procedureVersion,
            buildInstanceID: wire.buildInstanceID,
            softwareExportSHA256: wire.softwareExportSHA256,
            softwareExport: softwareExport
        )
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func isCanonicalSHA256(_ value: String) -> Bool {
        guard value.utf8.count == 64 else { return false }
        return value.utf8.allSatisfy { byte in
            (48...57).contains(byte) || (97...102).contains(byte)
        }
    }

    private static func validateClosedWorldShape(_ data: Data) throws {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PassiveBluetoothExperimentOneFinalShareArtifactError.malformedWireData
        }
        let allowed: Set<String> = [
            "schemaVersion", "artifactKind", "experimentID", "experimentRecipeID",
            "procedureVersion", "buildInstanceID", "softwareExportSHA256",
            "softwareExportJSONBase64",
        ]
        if let unexpected = root.keys.sorted().first(where: { !allowed.contains($0) }) {
            throw PassiveBluetoothExperimentOneFinalShareArtifactError.unexpectedWireField(unexpected)
        }
    }

    private struct WireV1: Codable {
        let schemaVersion: Int
        let artifactKind: String
        let experimentID: String
        let experimentRecipeID: String
        let procedureVersion: String
        let buildInstanceID: String
        let softwareExportSHA256: String
        let softwareExportJSONBase64: String
    }
}

public extension PassiveBluetoothExperimentOneCoordinator {
    func finalizedShareArtifactForCurrentApplication(
        setup: PassiveBluetoothStationaryCaptureSetup
    ) throws -> PassiveBluetoothExperimentOneFinalShareArtifact {
        guard let finalizedArtifact else {
            throw PassiveBluetoothExperimentOneSoftwareExportError.artifactNotFinalized
        }
        return try PassiveBluetoothExperimentOneFinalShareArtifactCodec.makeForCurrentApplication(
            finalizedArtifact: finalizedArtifact,
            setup: setup
        )
    }
}
