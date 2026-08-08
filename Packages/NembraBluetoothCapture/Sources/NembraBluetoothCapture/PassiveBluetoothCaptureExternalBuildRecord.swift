import CryptoKit
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

    /// SHA-256 of the exact external JSON bytes passed to the parser, without re-encoding.
    /// This is a rendezvous fact for an independently accepted attestation subject, not trust itself.
    public let exactRecordSHA256: String
    public let schemaVersion: Int
    public let buildIdentifier: String
    public let buildInstanceID: String
    public let sourceCommitSHA: String
    public let executableSHA256: String
    public let infoPlistSHA256: String
    public let experimentRecipeID: PassiveBluetoothExperimentRecipeID
    public let procedureVersion: String

    fileprivate init(
        exactRecordSHA256: String,
        schemaVersion: Int,
        buildIdentifier: String,
        buildInstanceID: String,
        sourceCommitSHA: String,
        executableSHA256: String,
        infoPlistSHA256: String,
        experimentRecipeID: PassiveBluetoothExperimentRecipeID,
        procedureVersion: String
    ) {
        self.exactRecordSHA256 = exactRecordSHA256
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

    /// Fail-closed mechanical comparison against the identity measured from the running app.
    ///
    /// Exact equality here proves only that this parsed declaration names the same build facts the
    /// app can measure locally. It does **not** prove that the external record was independently
    /// attested or accepted, and it never authorizes the physical Experiment One procedure.
    public func validateRuntimeBinding(
        to runtimeIdentity: PassiveBluetoothCaptureRuntimeBuildIdentity
    ) throws {
        guard buildIdentifier == runtimeIdentity.buildIdentifier else {
            throw PassiveBluetoothCaptureExternalBuildRuntimeBindingError.buildIdentifierMismatch
        }
        guard buildInstanceID == runtimeIdentity.buildInstanceID else {
            throw PassiveBluetoothCaptureExternalBuildRuntimeBindingError.buildInstanceIDMismatch
        }
        guard sourceCommitSHA == runtimeIdentity.sourceCommitSHA else {
            throw PassiveBluetoothCaptureExternalBuildRuntimeBindingError.sourceCommitSHAMismatch
        }
        guard executableSHA256 == runtimeIdentity.executableSHA256 else {
            throw PassiveBluetoothCaptureExternalBuildRuntimeBindingError.executableSHA256Mismatch
        }
        guard infoPlistSHA256 == runtimeIdentity.infoPlistSHA256 else {
            throw PassiveBluetoothCaptureExternalBuildRuntimeBindingError.infoPlistSHA256Mismatch
        }
    }
}

public enum PassiveBluetoothCaptureExternalBuildRuntimeBindingError: Error, Equatable, Sendable {
    case buildIdentifierMismatch
    case buildInstanceIDMismatch
    case sourceCommitSHAMismatch
    case executableSHA256Mismatch
    case infoPlistSHA256Mismatch
}

public enum PassiveBluetoothCaptureExternalBuildRecordError: Error, Equatable, Sendable {
    case malformedJSON
    case unexpectedField(String)
    case duplicateField(String)
    case unsupportedSchemaVersion(Int)
    case invalidBuildIdentifier
    case buildIdentifierSourceMismatch
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
        guard wire.buildIdentifier == expectedBuildIdentifier(for: normalizedSourceCommitSHA) else {
            throw PassiveBluetoothCaptureExternalBuildRecordError.buildIdentifierSourceMismatch
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
            exactRecordSHA256: sha256Hex(data),
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
        if let duplicateKey = PassiveBluetoothStrictJSONObject.duplicateTopLevelObjectKey(in: data) {
            throw PassiveBluetoothCaptureExternalBuildRecordError.duplicateField(duplicateKey)
        }

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

    private static func expectedBuildIdentifier(for sourceCommitSHA: String) -> String {
        "Capture Build V14-\(sourceCommitSHA.prefix(12))"
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

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
