import CryptoKit
import Foundation

/// Closed-world facts measured from one exact already-signed/installable field IPA.
///
/// Decoding this value proves only that the evidence bytes match Nembra's supported V14 evidence
/// schema and canonical vocabulary. Independent authorization is earned only when the field GO
/// verifier validates a signature over the SHA-256 of these exact evidence bytes.
public struct PassiveBluetoothCaptureSignedFieldArtifactEvidence: Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public static let requiredAuthority = "signed-field-artifact-evidence-not-field-authorization"
    public static let requiredBundleIdentifier = "com.jonathangana131.nembra"
    public static let requiredPlatformName = "iphoneos"
    public static let requiredProcedureVersion = "V14"

    public let exactEvidenceSHA256: String
    public let schemaVersion: Int
    public let buildIdentifier: String
    public let buildInstanceID: String
    public let sourceCommitSHA: String
    public let bundleIdentifier: String
    public let platformName: String
    public let supportedPlatforms: [String]
    public let teamIdentifier: String
    public let signingAuthorities: [String]
    public let ipaSHA256: String
    public let ipaByteCount: UInt64
    public let executableSHA256: String
    public let infoPlistSHA256: String
    public let externalBuildRecordSHA256: String
    public let experimentRecipeID: PassiveBluetoothExperimentRecipeID
    public let procedureVersion: String

    fileprivate init(
        exactEvidenceSHA256: String,
        schemaVersion: Int,
        buildIdentifier: String,
        buildInstanceID: String,
        sourceCommitSHA: String,
        bundleIdentifier: String,
        platformName: String,
        supportedPlatforms: [String],
        teamIdentifier: String,
        signingAuthorities: [String],
        ipaSHA256: String,
        ipaByteCount: UInt64,
        executableSHA256: String,
        infoPlistSHA256: String,
        externalBuildRecordSHA256: String,
        experimentRecipeID: PassiveBluetoothExperimentRecipeID,
        procedureVersion: String
    ) {
        self.exactEvidenceSHA256 = exactEvidenceSHA256
        self.schemaVersion = schemaVersion
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
}

public enum PassiveBluetoothCaptureSignedFieldArtifactEvidenceError: Error, Equatable, Sendable {
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
}

public enum PassiveBluetoothCaptureSignedFieldArtifactEvidenceJSON {
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
        let ipaByteCount: UInt64
        let executableSHA256: String
        let infoPlistSHA256: String
        let externalBuildRecordSHA256: String
        let experimentRecipeID: String
        let procedureVersion: String
    }

    public static func decodeDeclaration(
        _ data: Data
    ) throws -> PassiveBluetoothCaptureSignedFieldArtifactEvidence {
        try validateClosedWorldShape(data)

        let wire: WireV1
        do {
            wire = try JSONDecoder().decode(WireV1.self, from: data)
        } catch {
            throw PassiveBluetoothCaptureSignedFieldArtifactEvidenceError.malformedJSON
        }

        guard wire.schemaVersion == PassiveBluetoothCaptureSignedFieldArtifactEvidence.currentSchemaVersion else {
            throw PassiveBluetoothCaptureSignedFieldArtifactEvidenceError
                .unsupportedSchemaVersion(wire.schemaVersion)
        }
        guard wire.authority == PassiveBluetoothCaptureSignedFieldArtifactEvidence.requiredAuthority else {
            throw PassiveBluetoothCaptureSignedFieldArtifactEvidenceError
                .unsupportedAuthority(wire.authority)
        }
        guard isValidBuildIdentifier(wire.buildIdentifier) else {
            throw PassiveBluetoothCaptureSignedFieldArtifactEvidenceError.invalidBuildIdentifier
        }
        guard PassiveBluetoothCaptureRuntimeBuildIdentityReader
            .normalizedBuildInstanceID(wire.buildInstanceID) == wire.buildInstanceID else {
            throw PassiveBluetoothCaptureSignedFieldArtifactEvidenceError.invalidBuildInstanceID
        }
        guard PassiveBluetoothCaptureRuntimeBuildIdentityReader
            .normalizedFullGitCommitSHA(wire.sourceCommitSHA) == wire.sourceCommitSHA else {
            throw PassiveBluetoothCaptureSignedFieldArtifactEvidenceError.invalidSourceCommitSHA
        }
        guard wire.bundleIdentifier == PassiveBluetoothCaptureSignedFieldArtifactEvidence.requiredBundleIdentifier else {
            throw PassiveBluetoothCaptureSignedFieldArtifactEvidenceError
                .unsupportedBundleIdentifier(wire.bundleIdentifier)
        }
        guard wire.platformName == PassiveBluetoothCaptureSignedFieldArtifactEvidence.requiredPlatformName else {
            throw PassiveBluetoothCaptureSignedFieldArtifactEvidenceError
                .unsupportedPlatformName(wire.platformName)
        }
        guard wire.supportedPlatforms.contains("iPhoneOS"),
              !wire.supportedPlatforms.isEmpty,
              !wire.supportedPlatforms.contains(where: { $0.contains("Simulator") }),
              Set(wire.supportedPlatforms).count == wire.supportedPlatforms.count else {
            throw PassiveBluetoothCaptureSignedFieldArtifactEvidenceError.invalidSupportedPlatforms
        }
        guard isCanonicalText(wire.teamIdentifier) else {
            throw PassiveBluetoothCaptureSignedFieldArtifactEvidenceError.invalidTeamIdentifier
        }
        guard !wire.signingAuthorities.isEmpty,
              wire.signingAuthorities.allSatisfy(isCanonicalText),
              Set(wire.signingAuthorities).count == wire.signingAuthorities.count else {
            throw PassiveBluetoothCaptureSignedFieldArtifactEvidenceError.invalidSigningAuthorities
        }
        guard isCanonicalSHA256(wire.ipaSHA256) else {
            throw PassiveBluetoothCaptureSignedFieldArtifactEvidenceError.invalidIPASHA256
        }
        guard wire.ipaByteCount > 0 else {
            throw PassiveBluetoothCaptureSignedFieldArtifactEvidenceError.invalidIPAByteCount
        }
        guard isCanonicalSHA256(wire.executableSHA256) else {
            throw PassiveBluetoothCaptureSignedFieldArtifactEvidenceError.invalidExecutableSHA256
        }
        guard isCanonicalSHA256(wire.infoPlistSHA256) else {
            throw PassiveBluetoothCaptureSignedFieldArtifactEvidenceError.invalidInfoPlistSHA256
        }
        guard isCanonicalSHA256(wire.externalBuildRecordSHA256) else {
            throw PassiveBluetoothCaptureSignedFieldArtifactEvidenceError.invalidExternalBuildRecordSHA256
        }
        guard wire.experimentRecipeID == PassiveBluetoothExperimentRecipeID.es80FingerprintV1.rawValue else {
            throw PassiveBluetoothCaptureSignedFieldArtifactEvidenceError
                .unsupportedExperimentRecipe(wire.experimentRecipeID)
        }
        guard wire.procedureVersion == PassiveBluetoothCaptureSignedFieldArtifactEvidence.requiredProcedureVersion else {
            throw PassiveBluetoothCaptureSignedFieldArtifactEvidenceError
                .unsupportedProcedureVersion(wire.procedureVersion)
        }

        return .init(
            exactEvidenceSHA256: sha256Hex(data),
            schemaVersion: wire.schemaVersion,
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
            throw PassiveBluetoothCaptureSignedFieldArtifactEvidenceError.malformedJSON
        }
        guard let root = object as? [String: Any] else {
            throw PassiveBluetoothCaptureSignedFieldArtifactEvidenceError.malformedJSON
        }

        let allowed: Set<String> = [
            "schemaVersion", "authority", "buildIdentifier", "buildInstanceID", "sourceCommitSHA",
            "bundleIdentifier", "platformName", "supportedPlatforms", "teamIdentifier",
            "signingAuthorities", "ipaSHA256", "ipaByteCount", "executableSHA256",
            "infoPlistSHA256", "externalBuildRecordSHA256", "experimentRecipeID",
            "procedureVersion",
        ]
        for key in root.keys.sorted() where !allowed.contains(key) {
            throw PassiveBluetoothCaptureSignedFieldArtifactEvidenceError.unexpectedField(key)
        }
    }

    private static func isValidBuildIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 128 else { return false }
        return isCanonicalText(value)
    }

    private static func isCanonicalText(_ value: String) -> Bool {
        guard !value.isEmpty,
              value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
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
