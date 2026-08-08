import CryptoKit
import Foundation

/// Closed-world declaration that binds one externally measured, signed iPhone installable to the
/// exact external Capture build record for the same produced build instance.
///
/// This is deliberately **evidence, not acceptance**. Parsing these bytes does not verify Apple
/// code signing, a GitHub attestation, release approval, installation on a device, or physical
/// Experiment One authorization. A trusted build/acceptance system must independently verify the
/// exact evidence-record bytes and the exact signed installable before any later field-GO authority
/// can consume this rendezvous.
public struct PassiveBluetoothCaptureFieldBuildEvidenceRecord: Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public static let requiredInstallableKind = "ipa"

    /// SHA-256 of the exact evidence JSON bytes passed to the parser, without re-encoding.
    public let exactEvidenceRecordSHA256: String

    /// SHA-256 of the exact schema-v3 external build-record bytes independently measured by the
    /// producer. This binds the signed-installable statement to one exact external record encoding.
    public let externalBuildRecordSHA256: String

    /// SHA-256 of the exact final signed `.ipa` bytes. The parser validates only canonical spelling;
    /// an external trusted system must independently re-hash/attest those actual bytes.
    public let signedInstallableSHA256: String

    public let signedInstallableKind: String
    public let schemaVersion: Int
    public let buildIdentifier: String
    public let buildInstanceID: String
    public let sourceCommitSHA: String
    public let executableSHA256: String
    public let infoPlistSHA256: String
    public let experimentRecipeID: PassiveBluetoothExperimentRecipeID
    public let procedureVersion: String

    fileprivate init(
        exactEvidenceRecordSHA256: String,
        externalBuildRecordSHA256: String,
        signedInstallableSHA256: String,
        signedInstallableKind: String,
        schemaVersion: Int,
        buildIdentifier: String,
        buildInstanceID: String,
        sourceCommitSHA: String,
        executableSHA256: String,
        infoPlistSHA256: String,
        experimentRecipeID: PassiveBluetoothExperimentRecipeID,
        procedureVersion: String
    ) {
        self.exactEvidenceRecordSHA256 = exactEvidenceRecordSHA256
        self.externalBuildRecordSHA256 = externalBuildRecordSHA256
        self.signedInstallableSHA256 = signedInstallableSHA256
        self.signedInstallableKind = signedInstallableKind
        self.schemaVersion = schemaVersion
        self.buildIdentifier = buildIdentifier
        self.buildInstanceID = buildInstanceID
        self.sourceCommitSHA = sourceCommitSHA
        self.executableSHA256 = executableSHA256
        self.infoPlistSHA256 = infoPlistSHA256
        self.experimentRecipeID = experimentRecipeID
        self.procedureVersion = procedureVersion
    }

    /// Re-proves that this signed-installable declaration is bound to the exact external build
    /// record bytes and exact produced-build tuple before projecting the existing SoftwareExport
    /// comparison reference.
    ///
    /// A successful result is still software/build rendezvous evidence only. It does not grant
    /// physical field authority and cannot mutate `PassiveBluetoothExperimentOneFieldExecutionGate`.
    public func makeSoftwareExportBuildReference(
        matching externalRecord: PassiveBluetoothCaptureExternalBuildRecord
    ) throws -> PassiveBluetoothExperimentOneSoftwareExportBuildReference {
        guard externalBuildRecordSHA256 == externalRecord.exactRecordSHA256,
              buildIdentifier == externalRecord.buildIdentifier,
              buildInstanceID == externalRecord.buildInstanceID,
              sourceCommitSHA == externalRecord.sourceCommitSHA,
              executableSHA256 == externalRecord.executableSHA256,
              infoPlistSHA256 == externalRecord.infoPlistSHA256,
              experimentRecipeID == externalRecord.experimentRecipeID,
              procedureVersion == externalRecord.procedureVersion else {
            throw PassiveBluetoothCaptureFieldBuildEvidenceRecordError.externalBuildRecordMismatch
        }
        return try externalRecord.makeSoftwareExportBuildReference()
    }
}

public enum PassiveBluetoothCaptureFieldBuildEvidenceRecordError: Error, Equatable, Sendable {
    case malformedJSON
    case duplicateField(String)
    case unexpectedField(String)
    case unsupportedSchemaVersion(Int)
    case invalidExternalBuildRecordSHA256
    case invalidSignedInstallableSHA256
    case unsupportedSignedInstallableKind(String)
    case invalidBuildIdentifier
    case invalidBuildInstanceID
    case invalidSourceCommitSHA
    case invalidExecutableSHA256
    case invalidInfoPlistSHA256
    case unsupportedExperimentRecipe(String)
    case unsupportedProcedureVersion(String)
    case externalBuildRecordMismatch
}

/// Strict parser for an externally produced signed-field-build evidence declaration.
///
/// This parser intentionally performs no network lookup, signature verification, attestation
/// verification, or GO decision. It only establishes a closed-world exact-byte/build rendezvous that
/// a later independently trusted acceptance layer can consume without accepting caller-invented
/// booleans or loose build labels.
public enum PassiveBluetoothCaptureFieldBuildEvidenceRecordJSON {
    private struct WireV1: Decodable {
        let schemaVersion: Int
        let externalBuildRecordSHA256: String
        let signedInstallableSHA256: String
        let signedInstallableKind: String
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
    ) throws -> PassiveBluetoothCaptureFieldBuildEvidenceRecord {
        try validateClosedWorldShape(data)

        let wire: WireV1
        do {
            wire = try JSONDecoder().decode(WireV1.self, from: data)
        } catch {
            throw PassiveBluetoothCaptureFieldBuildEvidenceRecordError.malformedJSON
        }

        guard wire.schemaVersion == PassiveBluetoothCaptureFieldBuildEvidenceRecord.currentSchemaVersion else {
            throw PassiveBluetoothCaptureFieldBuildEvidenceRecordError
                .unsupportedSchemaVersion(wire.schemaVersion)
        }
        guard isCanonicalSHA256(wire.externalBuildRecordSHA256) else {
            throw PassiveBluetoothCaptureFieldBuildEvidenceRecordError.invalidExternalBuildRecordSHA256
        }
        guard isCanonicalSHA256(wire.signedInstallableSHA256) else {
            throw PassiveBluetoothCaptureFieldBuildEvidenceRecordError.invalidSignedInstallableSHA256
        }
        guard wire.signedInstallableKind == PassiveBluetoothCaptureFieldBuildEvidenceRecord.requiredInstallableKind else {
            throw PassiveBluetoothCaptureFieldBuildEvidenceRecordError
                .unsupportedSignedInstallableKind(wire.signedInstallableKind)
        }
        guard isValidBuildIdentifier(wire.buildIdentifier) else {
            throw PassiveBluetoothCaptureFieldBuildEvidenceRecordError.invalidBuildIdentifier
        }
        guard let normalizedBuildInstanceID = PassiveBluetoothCaptureRuntimeBuildIdentityReader
            .normalizedBuildInstanceID(wire.buildInstanceID),
              normalizedBuildInstanceID == wire.buildInstanceID else {
            throw PassiveBluetoothCaptureFieldBuildEvidenceRecordError.invalidBuildInstanceID
        }
        guard let normalizedSourceCommitSHA = PassiveBluetoothCaptureRuntimeBuildIdentityReader
            .normalizedFullGitCommitSHA(wire.sourceCommitSHA),
              normalizedSourceCommitSHA == wire.sourceCommitSHA else {
            throw PassiveBluetoothCaptureFieldBuildEvidenceRecordError.invalidSourceCommitSHA
        }
        guard isCanonicalSHA256(wire.executableSHA256) else {
            throw PassiveBluetoothCaptureFieldBuildEvidenceRecordError.invalidExecutableSHA256
        }
        guard isCanonicalSHA256(wire.infoPlistSHA256) else {
            throw PassiveBluetoothCaptureFieldBuildEvidenceRecordError.invalidInfoPlistSHA256
        }
        guard wire.experimentRecipeID == PassiveBluetoothExperimentRecipeID.es80FingerprintV1.rawValue else {
            throw PassiveBluetoothCaptureFieldBuildEvidenceRecordError
                .unsupportedExperimentRecipe(wire.experimentRecipeID)
        }
        guard wire.procedureVersion == PassiveBluetoothCaptureExternalBuildRecord.requiredProcedureVersion else {
            throw PassiveBluetoothCaptureFieldBuildEvidenceRecordError
                .unsupportedProcedureVersion(wire.procedureVersion)
        }

        return PassiveBluetoothCaptureFieldBuildEvidenceRecord(
            exactEvidenceRecordSHA256: sha256Hex(data),
            externalBuildRecordSHA256: wire.externalBuildRecordSHA256,
            signedInstallableSHA256: wire.signedInstallableSHA256,
            signedInstallableKind: wire.signedInstallableKind,
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
        do {
            try PassiveBluetoothCaptureStrictJSON.validateNoDuplicateObjectKeys(data)
        } catch PassiveBluetoothCaptureStrictJSONError.duplicateObjectKey(let key) {
            throw PassiveBluetoothCaptureFieldBuildEvidenceRecordError.duplicateField(key)
        } catch {
            throw PassiveBluetoothCaptureFieldBuildEvidenceRecordError.malformedJSON
        }

        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw PassiveBluetoothCaptureFieldBuildEvidenceRecordError.malformedJSON
        }
        guard let root = object as? [String: Any] else {
            throw PassiveBluetoothCaptureFieldBuildEvidenceRecordError.malformedJSON
        }

        let allowed: Set<String> = [
            "schemaVersion",
            "externalBuildRecordSHA256",
            "signedInstallableSHA256",
            "signedInstallableKind",
            "buildIdentifier",
            "buildInstanceID",
            "sourceCommitSHA",
            "executableSHA256",
            "infoPlistSHA256",
            "experimentRecipeID",
            "procedureVersion",
        ]
        for key in root.keys.sorted() where !allowed.contains(key) {
            throw PassiveBluetoothCaptureFieldBuildEvidenceRecordError.unexpectedField(key)
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

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
