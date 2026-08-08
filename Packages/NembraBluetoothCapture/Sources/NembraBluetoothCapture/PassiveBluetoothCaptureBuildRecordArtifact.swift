import Foundation

/// Strict, machine-readable metadata produced outside the running application for build-provenance
/// comparison during Capture preflight.
///
/// Decoding this artifact proves only that the bytes satisfy Nembra's schema. It does NOT establish
/// that the bytes came from the accepted build pipeline. Trust/authenticity must be established by
/// the final acceptance path before this record can participate in any future physical GO decision.
public struct PassiveBluetoothCaptureBuildRecordArtifact: Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let expectedBuildRecord: PassiveBluetoothCaptureExpectedBuildRecord
    public let procedureVersion: String
    public let toolchainIdentifier: String

    package init(
        schemaVersion: Int = currentSchemaVersion,
        expectedBuildRecord: PassiveBluetoothCaptureExpectedBuildRecord,
        procedureVersion: String,
        toolchainIdentifier: String
    ) {
        self.schemaVersion = schemaVersion
        self.expectedBuildRecord = expectedBuildRecord
        self.procedureVersion = procedureVersion
        self.toolchainIdentifier = toolchainIdentifier
    }
}

public enum PassiveBluetoothCaptureBuildRecordArtifactError: Error, Equatable, Sendable {
    case topLevelMustBeJSONObject
    case unexpectedField(String)
    case unsupportedSchemaVersion(Int)
    case invalidBuildIdentifier(String)
    case invalidSourceCommitSHA(String)
    case invalidExecutableSHA256(String)
    case invalidExperimentRecipeID(String)
    case invalidProcedureVersion(String)
    case invalidToolchainIdentifier(String)
}

public enum PassiveBluetoothCaptureBuildRecordArtifactJSON {
    private struct WireRecord: Codable {
        let schemaVersion: Int
        let buildIdentifier: String
        let sourceCommitSHA: String
        let executableSHA256: String
        let experimentRecipeID: String
        let procedureVersion: String
        let toolchainIdentifier: String
    }

    private static let expectedKeys: Set<String> = [
        "schemaVersion",
        "buildIdentifier",
        "sourceCommitSHA",
        "executableSHA256",
        "experimentRecipeID",
        "procedureVersion",
        "toolchainIdentifier",
    ]

    /// Decodes a strict schema-v1 external build record.
    ///
    /// Unknown fields fail closed so a record cannot smuggle claims such as `physicalGo`,
    /// `verifiedES80`, or other authority outside this narrow provenance schema.
    public static func decode(_ data: Data) throws -> PassiveBluetoothCaptureBuildRecordArtifact {
        let topLevel = try JSONSerialization.jsonObject(with: data)
        guard let object = topLevel as? [String: Any] else {
            throw PassiveBluetoothCaptureBuildRecordArtifactError.topLevelMustBeJSONObject
        }

        if let unexpected = Set(object.keys).subtracting(expectedKeys).sorted().first {
            throw PassiveBluetoothCaptureBuildRecordArtifactError.unexpectedField(unexpected)
        }

        let wire = try JSONDecoder().decode(WireRecord.self, from: data)
        guard wire.schemaVersion == PassiveBluetoothCaptureBuildRecordArtifact.currentSchemaVersion else {
            throw PassiveBluetoothCaptureBuildRecordArtifactError.unsupportedSchemaVersion(
                wire.schemaVersion
            )
        }

        guard isValidBoundedIdentifier(wire.buildIdentifier, maximumUTF8Count: 128) else {
            throw PassiveBluetoothCaptureBuildRecordArtifactError.invalidBuildIdentifier(
                wire.buildIdentifier
            )
        }
        guard let commit = normalizedHex(wire.sourceCommitSHA, characterCount: 40) else {
            throw PassiveBluetoothCaptureBuildRecordArtifactError.invalidSourceCommitSHA(
                wire.sourceCommitSHA
            )
        }
        guard let executableDigest = normalizedHex(
            wire.executableSHA256,
            characterCount: 64
        ) else {
            throw PassiveBluetoothCaptureBuildRecordArtifactError.invalidExecutableSHA256(
                wire.executableSHA256
            )
        }
        guard let recipeID = PassiveBluetoothExperimentRecipeID(rawValue: wire.experimentRecipeID) else {
            throw PassiveBluetoothCaptureBuildRecordArtifactError.invalidExperimentRecipeID(
                wire.experimentRecipeID
            )
        }
        guard isValidBoundedIdentifier(wire.procedureVersion, maximumUTF8Count: 128) else {
            throw PassiveBluetoothCaptureBuildRecordArtifactError.invalidProcedureVersion(
                wire.procedureVersion
            )
        }
        guard isValidBoundedIdentifier(wire.toolchainIdentifier, maximumUTF8Count: 256) else {
            throw PassiveBluetoothCaptureBuildRecordArtifactError.invalidToolchainIdentifier(
                wire.toolchainIdentifier
            )
        }

        return PassiveBluetoothCaptureBuildRecordArtifact(
            expectedBuildRecord: .init(
                buildIdentifier: wire.buildIdentifier,
                sourceCommitSHA: commit,
                executableSHA256: executableDigest,
                experimentRecipeID: recipeID
            ),
            procedureVersion: wire.procedureVersion,
            toolchainIdentifier: wire.toolchainIdentifier
        )
    }

    /// Package-owned canonical encoder used by deterministic tests and an eventual accepted build
    /// producer. Encoding is not signing and does not make the resulting bytes trusted.
    package static func encode(_ artifact: PassiveBluetoothCaptureBuildRecordArtifact) throws -> Data {
        let record = artifact.expectedBuildRecord
        let wire = WireRecord(
            schemaVersion: artifact.schemaVersion,
            buildIdentifier: record.buildIdentifier,
            sourceCommitSHA: record.sourceCommitSHA,
            executableSHA256: record.executableSHA256,
            experimentRecipeID: record.experimentRecipeID.rawValue,
            procedureVersion: artifact.procedureVersion,
            toolchainIdentifier: artifact.toolchainIdentifier
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(wire)
    }

    private static func isValidBoundedIdentifier(
        _ value: String,
        maximumUTF8Count: Int
    ) -> Bool {
        guard !value.isEmpty, value.utf8.count <= maximumUTF8Count else { return false }
        guard value == value.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        return !value.unicodeScalars.contains(where: { scalar in
            CharacterSet.controlCharacters.contains(scalar)
        })
    }

    private static func normalizedHex(_ value: String, characterCount: Int) -> String? {
        let normalized = value.lowercased()
        guard normalized.utf8.count == characterCount else { return nil }
        guard normalized.utf8.allSatisfy({ byte in
            (48...57).contains(byte) || (97...102).contains(byte)
        }) else {
            return nil
        }
        return normalized
    }
}
