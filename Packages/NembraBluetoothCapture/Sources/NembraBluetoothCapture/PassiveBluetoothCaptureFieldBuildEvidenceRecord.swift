import CryptoKit
import Foundation

/// Closed-world declaration emitted beside one externally measured signed iPhone Capture IPA.
///
/// This type deliberately represents **evidence, not acceptance**. Parsing the record does not
/// verify Apple signing, a GitHub attestation, release approval, installation on a device, or
/// physical Experiment One authorization. Those remain responsibilities of a later independently
/// trusted acceptance layer.
public struct PassiveBluetoothCaptureFieldBuildEvidenceRecord: Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public static let requiredAuthority = "signed-field-artifact-evidence-not-field-authorization"
    public static let requiredBundleIdentifier = "com.jonathangana131.nembra"
    public static let requiredPlatformName = "iphoneos"

    /// SHA-256 of the exact companion evidence JSON bytes passed to the parser, without re-encoding.
    public let exactEvidenceRecordSHA256: String
    public let schemaVersion: Int
    public let authority: String
    public let buildIdentifier: String
    public let buildInstanceID: String
    public let sourceCommitSHA: String
    public let bundleIdentifier: String
    public let platformName: String
    public let supportedPlatforms: [String]
    public let teamIdentifier: String
    public let signingAuthorities: [String]
    public let ipaSHA256: String
    public let ipaByteCount: Int
    public let executableSHA256: String
    public let infoPlistSHA256: String
    public let externalBuildRecordSHA256: String
    public let experimentRecipeID: PassiveBluetoothExperimentRecipeID
    public let procedureVersion: String

    fileprivate init(
        exactEvidenceRecordSHA256: String,
        schemaVersion: Int,
        authority: String,
        buildIdentifier: String,
        buildInstanceID: String,
        sourceCommitSHA: String,
        bundleIdentifier: String,
        platformName: String,
        supportedPlatforms: [String],
        teamIdentifier: String,
        signingAuthorities: [String],
        ipaSHA256: String,
        ipaByteCount: Int,
        executableSHA256: String,
        infoPlistSHA256: String,
        externalBuildRecordSHA256: String,
        experimentRecipeID: PassiveBluetoothExperimentRecipeID,
        procedureVersion: String
    ) {
        self.exactEvidenceRecordSHA256 = exactEvidenceRecordSHA256
        self.schemaVersion = schemaVersion
        self.authority = authority
        self.buildIdentifier = buildIdentifier
        self.buildInstanceID = buildInstanceID
        self.sourceCommitSHA = sourceCommitSHA
        self.bundleIdentifier = bundleIdentifier
        self.platformName = platformName
        self.supportedPlatforms = supportedPlatforms
        self.teamIdentifier = teamIdentifier
        self.signingAuthorities = signingAuthorities
        self.ipaSHA256 = ipaSHA256
        self.ipaByteCount = ipaByteCount
        self.executableSHA256 = executableSHA256
        self.infoPlistSHA256 = infoPlistSHA256
        self.externalBuildRecordSHA256 = externalBuildRecordSHA256
        self.experimentRecipeID = experimentRecipeID
        self.procedureVersion = procedureVersion
    }

    /// Re-proves that this signed-IPA evidence declaration names the exact schema-v3 external build
    /// record bytes and exact produced-build tuple before projecting the existing SoftwareExport
    /// comparison reference.
    ///
    /// Success still grants no trust or physical field authority.
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
    case unexpectedField(String)
    case unsupportedSchemaVersion(Int)
    case unsupportedAuthority(String)
    case invalidBuildIdentifier
    case invalidBuildInstanceID
    case invalidSourceCommitSHA
    case unsupportedBundleIdentifier(String)
    case unsupportedPlatformName(String)
    case invalidSupportedPlatforms
    case invalidTeamIdentifier
    case invalidSigningAuthorities
    case invalidIPASHA256
    case invalidIPAByteCount
    case invalidExecutableSHA256
    case invalidInfoPlistSHA256
    case invalidExternalBuildRecordSHA256
    case unsupportedExperimentRecipe(String)
    case unsupportedProcedureVersion(String)
    case externalBuildRecordMismatch
}

/// Strict consumer for `NembraCaptureSignedFieldArtifactEvidence.json` emitted by
/// `scripts/ci/es80_signed_field_artifact_evidence.py`.
///
/// The parser mirrors that producer's schema exactly. It performs no network lookup, code-signature
/// verification, attestation verification, or GO decision and rejects authority-looking extensions.
public enum PassiveBluetoothCaptureFieldBuildEvidenceRecordJSON {
    private struct WireV1: Decodable {
        let schemaVersion: Int
        let authority: String
        let buildIdentifier: String
        let buildInstanceID: String
        let sourceCommitSHA: String
        let bundleIdentifier: String
        let platformName: String
        let supportedPlatforms: [String]
        let teamIdentifier: String
        let signingAuthorities: [String]
        let ipaSHA256: String
        let ipaByteCount: Int
        let executableSHA256: String
        let infoPlistSHA256: String
        let externalBuildRecordSHA256: String
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
        guard wire.authority == PassiveBluetoothCaptureFieldBuildEvidenceRecord.requiredAuthority else {
            throw PassiveBluetoothCaptureFieldBuildEvidenceRecordError
                .unsupportedAuthority(wire.authority)
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
        guard wire.buildIdentifier == "Capture Build V14-\(wire.sourceCommitSHA.prefix(12))" else {
            throw PassiveBluetoothCaptureFieldBuildEvidenceRecordError.invalidBuildIdentifier
        }
        guard wire.bundleIdentifier == PassiveBluetoothCaptureFieldBuildEvidenceRecord.requiredBundleIdentifier else {
            throw PassiveBluetoothCaptureFieldBuildEvidenceRecordError
                .unsupportedBundleIdentifier(wire.bundleIdentifier)
        }
        guard wire.platformName == PassiveBluetoothCaptureFieldBuildEvidenceRecord.requiredPlatformName else {
            throw PassiveBluetoothCaptureFieldBuildEvidenceRecordError
                .unsupportedPlatformName(wire.platformName)
        }
        guard !wire.supportedPlatforms.isEmpty,
              wire.supportedPlatforms.contains("iPhoneOS"),
              wire.supportedPlatforms.allSatisfy({ !$0.contains("Simulator") && isSafeEvidenceString($0) }) else {
            throw PassiveBluetoothCaptureFieldBuildEvidenceRecordError.invalidSupportedPlatforms
        }
        guard isSafeEvidenceString(wire.teamIdentifier) else {
            throw PassiveBluetoothCaptureFieldBuildEvidenceRecordError.invalidTeamIdentifier
        }
        guard !wire.signingAuthorities.isEmpty,
              wire.signingAuthorities.allSatisfy(isSafeEvidenceString) else {
            throw PassiveBluetoothCaptureFieldBuildEvidenceRecordError.invalidSigningAuthorities
        }
        guard isCanonicalSHA256(wire.ipaSHA256) else {
            throw PassiveBluetoothCaptureFieldBuildEvidenceRecordError.invalidIPASHA256
        }
        guard wire.ipaByteCount > 0 else {
            throw PassiveBluetoothCaptureFieldBuildEvidenceRecordError.invalidIPAByteCount
        }
        guard isCanonicalSHA256(wire.executableSHA256) else {
            throw PassiveBluetoothCaptureFieldBuildEvidenceRecordError.invalidExecutableSHA256
        }
        guard isCanonicalSHA256(wire.infoPlistSHA256) else {
            throw PassiveBluetoothCaptureFieldBuildEvidenceRecordError.invalidInfoPlistSHA256
        }
        guard isCanonicalSHA256(wire.externalBuildRecordSHA256) else {
            throw PassiveBluetoothCaptureFieldBuildEvidenceRecordError.invalidExternalBuildRecordSHA256
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
            schemaVersion: wire.schemaVersion,
            authority: wire.authority,
            buildIdentifier: wire.buildIdentifier,
            buildInstanceID: wire.buildInstanceID,
            sourceCommitSHA: wire.sourceCommitSHA,
            bundleIdentifier: wire.bundleIdentifier,
            platformName: wire.platformName,
            supportedPlatforms: wire.supportedPlatforms,
            teamIdentifier: wire.teamIdentifier,
            signingAuthorities: wire.signingAuthorities,
            ipaSHA256: wire.ipaSHA256,
            ipaByteCount: wire.ipaByteCount,
            executableSHA256: wire.executableSHA256,
            infoPlistSHA256: wire.infoPlistSHA256,
            externalBuildRecordSHA256: wire.externalBuildRecordSHA256,
            experimentRecipeID: .es80FingerprintV1,
            procedureVersion: wire.procedureVersion
        )
    }

    private static func validateClosedWorldShape(_ data: Data) throws {
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
            "authority",
            "buildIdentifier",
            "buildInstanceID",
            "sourceCommitSHA",
            "bundleIdentifier",
            "platformName",
            "supportedPlatforms",
            "teamIdentifier",
            "signingAuthorities",
            "ipaSHA256",
            "ipaByteCount",
            "executableSHA256",
            "infoPlistSHA256",
            "externalBuildRecordSHA256",
            "experimentRecipeID",
            "procedureVersion",
        ]
        for key in root.keys.sorted() where !allowed.contains(key) {
            throw PassiveBluetoothCaptureFieldBuildEvidenceRecordError.unexpectedField(key)
        }
    }

    private static func isValidBuildIdentifier(_ value: String) -> Bool {
        !value.isEmpty
            && value.utf8.count <= 128
            && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
            && !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    }

    private static func isSafeEvidenceString(_ value: String) -> Bool {
        !value.isEmpty
            && value.utf8.count <= 512
            && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
            && !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
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
