import Foundation

/// Exact bytes of the build runner's external Experiment One build record after closed-world decode.
///
/// Decoding this record proves only that the bytes have the expected V14 schema and canonical value
/// shapes. It deliberately does not authenticate who produced the bytes, verify a GitHub attestation,
/// or authorize a physical experiment. An independent trust layer must verify the exact `recordJSON`
/// bytes before a caller promotes `buildReference` into accepted field-build evidence.
public struct PassiveBluetoothExperimentOneExternalBuildRecord: Equatable, Sendable {
    public static let currentSchemaVersion = 2
    public static let acceptedProcedureVersion = "V14"

    /// Exact input bytes. Preserve these bytes for independent signature/attestation verification;
    /// do not re-encode this value and treat the new bytes as the originally attested record.
    public let recordJSON: Data
    public let buildReference: PassiveBluetoothExperimentOneSoftwareExportBuildReference
    public let experimentRecipeID: PassiveBluetoothExperimentRecipeID
    public let procedureVersion: String

    fileprivate init(
        recordJSON: Data,
        buildReference: PassiveBluetoothExperimentOneSoftwareExportBuildReference,
        experimentRecipeID: PassiveBluetoothExperimentRecipeID,
        procedureVersion: String
    ) {
        self.recordJSON = recordJSON
        self.buildReference = buildReference
        self.experimentRecipeID = experimentRecipeID
        self.procedureVersion = procedureVersion
    }
}

public enum PassiveBluetoothExperimentOneExternalBuildRecordError: Error, Equatable, Sendable {
    case malformedRecord
    case unexpectedField(String)
    case unsupportedSchemaVersion(Int)
    case unsupportedExperimentRecipe(String)
    case unsupportedProcedureVersion(String)
}

public enum PassiveBluetoothExperimentOneExternalBuildRecordCodec {
    /// Closed-world decodes the exact external-record bytes emitted by the trusted build topology.
    ///
    /// The returned value is intentionally *untrusted decoded data*. Physical admission must remain
    /// closed until a separate verifier establishes acceptance/attestation over `recordJSON` itself.
    public static func decodeUntrusted(
        _ data: Data
    ) throws -> PassiveBluetoothExperimentOneExternalBuildRecord {
        try validateClosedWorldShape(data)

        let wire: Wire
        do {
            wire = try JSONDecoder().decode(Wire.self, from: data)
        } catch {
            throw PassiveBluetoothExperimentOneExternalBuildRecordError.malformedRecord
        }

        guard wire.schemaVersion == PassiveBluetoothExperimentOneExternalBuildRecord.currentSchemaVersion else {
            throw PassiveBluetoothExperimentOneExternalBuildRecordError
                .unsupportedSchemaVersion(wire.schemaVersion)
        }
        guard let recipeID = PassiveBluetoothExperimentRecipeID(rawValue: wire.experimentRecipeID),
              recipeID == .es80FingerprintV1 else {
            throw PassiveBluetoothExperimentOneExternalBuildRecordError
                .unsupportedExperimentRecipe(wire.experimentRecipeID)
        }
        guard wire.procedureVersion == PassiveBluetoothExperimentOneExternalBuildRecord.acceptedProcedureVersion else {
            throw PassiveBluetoothExperimentOneExternalBuildRecordError
                .unsupportedProcedureVersion(wire.procedureVersion)
        }

        let reference: PassiveBluetoothExperimentOneSoftwareExportBuildReference
        do {
            reference = try .init(
                buildIdentifier: wire.buildIdentifier,
                buildInstanceID: wire.buildInstanceID,
                sourceCommitSHA: wire.sourceCommitSHA,
                executableSHA256: wire.executableSHA256
            )
        } catch {
            throw PassiveBluetoothExperimentOneExternalBuildRecordError.malformedRecord
        }

        return .init(
            recordJSON: data,
            buildReference: reference,
            experimentRecipeID: recipeID,
            procedureVersion: wire.procedureVersion
        )
    }

    private static func validateClosedWorldShape(_ data: Data) throws {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PassiveBluetoothExperimentOneExternalBuildRecordError.malformedRecord
        }

        let allowed: Set<String> = [
            "schemaVersion",
            "buildIdentifier",
            "buildInstanceID",
            "sourceCommitSHA",
            "executableSHA256",
            "experimentRecipeID",
            "procedureVersion"
        ]
        if let unexpected = root.keys.sorted().first(where: { !allowed.contains($0) }) {
            throw PassiveBluetoothExperimentOneExternalBuildRecordError.unexpectedField(unexpected)
        }
    }

    private struct Wire: Decodable {
        let schemaVersion: Int
        let buildIdentifier: String
        let buildInstanceID: String
        let sourceCommitSHA: String
        let executableSHA256: String
        let experimentRecipeID: String
        let procedureVersion: String
    }
}
