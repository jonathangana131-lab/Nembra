import CryptoKit
import Foundation

/// Closed-world declaration emitted by the signed-IPA evidence producer. It binds one externally
/// measured iPhone installable and its observed signing context to the exact external Capture build
/// record for the same produced build instance.
///
/// This is deliberately **evidence, not acceptance**. Parsing these bytes does not establish that
/// the observed signing team/authority is trusted, that an attestation was accepted, that this IPA
/// is installed on the field device, or that physical Experiment One is authorized.
public struct PassiveBluetoothCaptureFieldBuildEvidenceRecord: Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public static let requiredAuthority = "signed-field-artifact-evidence-not-field-authorization"
    public static let requiredInstallableKind = "ipa"
    public static let requiredBundleIdentifier = "com.jonathangana131.nembra"
    public static let requiredPlatformName = "iphoneos"
    public static let requiredSupportedPlatform = "iPhoneOS"

    /// SHA-256 of the exact evidence JSON bytes passed to the parser, without re-encoding.
    public let exactEvidenceRecordSHA256: String

    /// SHA-256 of the exact schema-v3 external build-record bytes measured by the producer.
    public let externalBuildRecordSHA256: String

    /// SHA-256 of the exact final signed `.ipa` bytes. The package validates only the declaration;
    /// an independently trusted system must re-hash/attest the actual retained IPA bytes.
    public let signedInstallableSHA256: String
    public let signedInstallableKind: String
    public let signedInstallableByteCount: Int

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
    public let executableSHA256: String
    public let infoPlistSHA256: String
    public let experimentRecipeID: PassiveBluetoothExperimentRecipeID
    public let procedureVersion: String

    fileprivate init(
        exactEvidenceRecordSHA256: String,
        externalBuildRecordSHA256: String,
        signedInstallableSHA256: String,
        signedInstallableByteCount: Int,
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
        executableSHA256: String,
        infoPlistSHA256: String,
        experimentRecipeID: PassiveBluetoothExperimentRecipeID,
        procedureVersion: String
    ) {
        self.exactEvidenceRecordSHA256 = exactEvidenceRecordSHA256
        self.externalBuildRecordSHA256 = externalBuildRecordSHA256
        self.signedInstallableSHA256 = signedInstallableSHA256
        signedInstallableKind = Self.requiredInstallableKind
        self.signedInstallableByteCount = signedInstallableByteCount
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
    case unexpectedField(String)
    case unsupportedSchemaVersion(Int)
    case unsupportedAuthority(String)
    case invalidExternalBuildRecordSHA256
    case invalidSignedInstallableSHA256
    case invalidSignedInstallableByteCount(Int)
    case invalidBuildIdentifier
    case invalidBuildInstanceID
    case invalidSourceCommitSHA
    case unsupportedBundleIdentifier(String)
    case unsupportedPlatformName(String)
    case invalidSupportedPlatforms
    case invalidTeamIdentifier
    case invalidSigningAuthorities
    case invalidExecutableSHA256
    case invalidInfoPlistSHA256
    case unsupportedExperimentRecipe(String)
    case unsupportedProcedureVersion(String)
    case externalBuildRecordMismatch
}

/// Strict parser for the exact companion JSON emitted by
/// `scripts/ci/es80_signed_field_artifact_evidence.py`.
///
/// This parser intentionally performs no network lookup, code-signature verification, attestation
/// verification, trust decision, or GO decision. Signing metadata is retained as evidence only.
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
            throw PassiveBluetoothCaptureFieldBuildEvidenceRecordError.unsupportedAuthority(wire.authority)
        }
        guard isCanonicalSHA256(wire.externalBuildRecordSHA256) else {
            throw PassiveBluetoothCaptureFieldBuildEvidenceRecordError.invalidExternalBuildRecordSHA256
        }
        guard isCanonicalSHA256(wire.ipaSHA256) else {
            throw PassiveBluetoothCaptureFieldBuildEvidenceRecordError.invalidSignedInstallableSHA256
        }
        guard wire.ipaByteCount > 0 else {
            throw PassiveBluetoothCaptureFieldBuildEvidenceRecordError
                .invalidSignedInstallableByteCount(wire.ipaByteCount)
        }
        guard isValidEvidenceString(wire.buildIdentifier, maximumUTF8Count: 128) else {
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
        guard wire.bundleIdentifier == PassiveBluetoothCaptureFieldBuildEvidenceRecord.requiredBundleIdentifier else {
            throw PassiveBluetoothCaptureFieldBuildEvidenceRecordError
                .unsupportedBundleIdentifier(wire.bundleIdentifier)
        }
        guard wire.platformName == PassiveBluetoothCaptureFieldBuildEvidenceRecord.requiredPlatformName else {
            throw PassiveBluetoothCaptureFieldBuildEvidenceRecordError
                .unsupportedPlatformName(wire.platformName)
        }
        guard wire.supportedPlatforms.contains(
            PassiveBluetoothCaptureFieldBuildEvidenceRecord.requiredSupportedPlatform
        ),
              !wire.supportedPlatforms.isEmpty,
              wire.supportedPlatforms.allSatisfy({
                  isValidEvidenceString($0, maximumUTF8Count: 64) && !$0.contains("Simulator")
              }) else {
            throw PassiveBluetoothCaptureFieldBuildEvidenceRecordError.invalidSupportedPlatforms
        }
        guard isValidEvidenceString(wire.teamIdentifier, maximumUTF8Count: 128),
              !["not set", "none", "-"].contains(wire.teamIdentifier.lowercased()) else {
            throw PassiveBluetoothCaptureFieldBuildEvidenceRecordError.invalidTeamIdentifier
        }
        guard !wire.signingAuthorities.isEmpty,
              wire.signingAuthorities.allSatisfy({ isValidEvidenceString($0, maximumUTF8Count: 512) }) else {
            throw PassiveBluetoothCaptureFieldBuildEvidenceRecordError.invalidSigningAuthorities
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
            signedInstallableSHA256: wire.ipaSHA256,
            signedInstallableByteCount: wire.ipaByteCount,
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

    private static func isValidEvidenceString(_ value: String, maximumUTF8Count: Int) -> Bool {
        guard !value.isEmpty, value.utf8.count <= maximumUTF8Count else { return false }
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
