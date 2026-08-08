import Foundation

/// Closed-world declaration emitted outside `Nembra.app` by the accepted build pipeline.
///
/// Parsing this record proves only that its bytes match the supported schema and canonical
/// Experiment One vocabulary. It does **not** verify a GitHub attestation, signature, release
/// approval, physical field authorization, or that the referenced bytes were actually installed.
/// An external trust layer must independently accept the exact record before its mechanical build
/// reference can contribute to field admission.
public struct PassiveBluetoothCaptureExternalBuildRecord: Equatable, Sendable {
    public static let currentSchemaVersion = 3
    public static let requiredProcedureVersion = "V14"

    public let schemaVersion: Int
    public let buildIdentifier: String
    public let buildInstanceID: String
    public let sourceCommitSHA: String
    public let executableSHA256: String
    public let infoPlistSHA256: String
    public let experimentRecipeID: PassiveBluetoothExperimentRecipeID
    public let procedureVersion: String

    fileprivate init(
        schemaVersion: Int,
        buildIdentifier: String,
        buildInstanceID: String,
        sourceCommitSHA: String,
        executableSHA256: String,
        infoPlistSHA256: String,
        experimentRecipeID: PassiveBluetoothExperimentRecipeID,
        procedureVersion: String
    ) {
        self.schemaVersion = schemaVersion
        self.buildIdentifier = buildIdentifier
        self.buildInstanceID = buildInstanceID
        self.sourceCommitSHA = sourceCommitSHA
        self.executableSHA256 = executableSHA256
        self.infoPlistSHA256 = infoPlistSHA256
        self.experimentRecipeID = experimentRecipeID
        self.procedureVersion = procedureVersion
    }

    /// Projects this parsed declaration into #781's mechanical build-comparison input.
    ///
    /// A successful projection inherits no trust merely because this record parsed. Callers must
    /// keep independently accepted external-record/attestation authority separate from this value.
    public func makeSoftwareExportBuildReference() throws
        -> PassiveBluetoothExperimentOneSoftwareExportBuildReference
    {
        try .init(
            buildIdentifier: buildIdentifier,
            buildInstanceID: buildInstanceID,
            sourceCommitSHA: sourceCommitSHA,
            executableSHA256: executableSHA256
        )
    }
}

public enum PassiveBluetoothCaptureExternalBuildRecordError: Error, Equatable, Sendable {
    case malformedJSON
    case unexpectedField(String)
    case unsupportedSchemaVersion(Int)
    case invalidBuildIdentifier
    case invalidBuildInstanceID
    case invalidSourceCommitSHA
    case invalidExecutableSHA256
    case invalidInfoPlistSHA256
    case unsupportedExperimentRecipe(String)
    case unsupportedProcedureVersion(String)
}

/// Strict parser for the non-self-referential external build record produced by Nembra's build
/// pipeline. This parser intentionally performs no network lookup and mints no accepted/attested
/// authority from arbitrary JSON bytes.
public enum PassiveBluetoothCaptureExternalBuildRecordJSON {
    private struct WireV3: Decodable {
        let schemaVersion: Int
        let buildIdentifier: String
        let buildInstanceID: String
        let sourceCommitSHA: String
        let executableSHA256: String
        let infoPlistSHA256: String
        let experimentRecipeID: String
        let procedureVersion: String
    }

    public static func decodeDeclaration(
        _ data: Data
    ) throws -> PassiveBluetoothCaptureExternalBuildRecord {
        try validateClosedWorldShape(data)

        let wire: WireV3
        do {
            wire = try JSONDecoder().decode(WireV3.self, from: data)
        } catch {
            throw PassiveBluetoothCaptureExternalBuildRecordError.malformedJSON
        }

        guard wire.schemaVersion == PassiveBluetoothCaptureExternalBuildRecord.currentSchemaVersion else {
            throw PassiveBluetoothCaptureExternalBuildRecordError
                .unsupportedSchemaVersion(wire.schemaVersion)
        }
        guard isValidBuildIdentifier(wire.buildIdentifier) else {
            throw PassiveBluetoothCaptureExternalBuildRecordError.invalidBuildIdentifier
        }
        guard let normalizedBuildInstanceID = PassiveBluetoothCaptureRuntimeBuildIdentityReader
            .normalizedBuildInstanceID(wire.buildInstanceID),
              normalizedBuildInstanceID == wire.buildInstanceID else {
            throw PassiveBluetoothCaptureExternalBuildRecordError.invalidBuildInstanceID
        }
        guard let normalizedSourceCommitSHA = PassiveBluetoothCaptureRuntimeBuildIdentityReader
            .normalizedFullGitCommitSHA(wire.sourceCommitSHA),
              normalizedSourceCommitSHA == wire.sourceCommitSHA else {
            throw PassiveBluetoothCaptureExternalBuildRecordError.invalidSourceCommitSHA
        }
        guard isCanonicalSHA256(wire.executableSHA256) else {
            throw PassiveBluetoothCaptureExternalBuildRecordError.invalidExecutableSHA256
        }
        guard isCanonicalSHA256(wire.infoPlistSHA256) else {
            throw PassiveBluetoothCaptureExternalBuildRecordError.invalidInfoPlistSHA256
        }
        guard wire.experimentRecipeID == PassiveBluetoothExperimentRecipeID.es80FingerprintV1.rawValue else {
            throw PassiveBluetoothCaptureExternalBuildRecordError
                .unsupportedExperimentRecipe(wire.experimentRecipeID)
        }
        guard wire.procedureVersion == PassiveBluetoothCaptureExternalBuildRecord.requiredProcedureVersion else {
            throw PassiveBluetoothCaptureExternalBuildRecordError
                .unsupportedProcedureVersion(wire.procedureVersion)
        }

        return PassiveBluetoothCaptureExternalBuildRecord(
            schemaVersion: wire.schemaVersion,
            buildIdentifier: wire.buildIdentifier,
            buildInstanceID: wire.buildInstanceID,
            sourceCommitSHA: wire.sourceCommitSHA,
            executableSHA256: wire.executableSHA256,
            infoPlistSHA256: wire.infoPlistSHA256,
            experimentRecipeID: .es80FingerprintV1,
            procedureVersion: wire.procedureVersion
        )
    }

    private static func validateClosedWorldShape(_ data: Data) throws {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw PassiveBluetoothCaptureExternalBuildRecordError.malformedJSON
        }
        guard let root = object as? [String: Any] else {
            throw PassiveBluetoothCaptureExternalBuildRecordError.malformedJSON
        }

        let allowed: Set<String> = [
            "schemaVersion",
            "buildIdentifier",
            "buildInstanceID",
            "sourceCommitSHA",
            "executableSHA256",
            "infoPlistSHA256",
            "experimentRecipeID",
            "procedureVersion",
        ]
        for key in root.keys.sorted() where !allowed.contains(key) {
            throw PassiveBluetoothCaptureExternalBuildRecordError.unexpectedField(key)
        }
    }

    private static func isValidBuildIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 128 else { return false }
        guard value == value.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        guard !value.unicodeScalars.contains(where: { scalar in
            CharacterSet.controlCharacters.contains(scalar)
        }) else {
            return false
        }
        return true
    }

    private static func isCanonicalSHA256(_ value: String) -> Bool {
        guard value.utf8.count == 64 else { return false }
        return value.utf8.allSatisfy { byte in
            (48...57).contains(byte) || (97...102).contains(byte)
        }
    }
}
