import CryptoKit
import Foundation

/// Closed-world declaration emitted by the signed-field IPA evidence producer.
///
/// Parsing proves only schema/byte/build consistency. The signing and provisioning values remain
/// externally produced declarations until an independently trusted acceptance system verifies the
/// exact evidence bytes and retained IPA. This value never authorizes physical Experiment One.
public struct PassiveBluetoothCaptureSignedFieldArtifactEvidence: Equatable, Sendable {
    public static let currentSchemaVersion = 2
    public static let requiredAuthority = "signed-field-artifact-evidence-not-field-authorization"
    public static let requiredBundleIdentifier = "com.jonathangana131.nembra"
    public static let requiredPlatformName = "iphoneos"

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
    public let codeDirectoryHash: String
    public let provisioningProfileUUID: String
    public let provisioningProfileExpirationUTC: String
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
        codeDirectoryHash: String,
        provisioningProfileUUID: String,
        provisioningProfileExpirationUTC: String,
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
        self.codeDirectoryHash = codeDirectoryHash
        self.provisioningProfileUUID = provisioningProfileUUID
        self.provisioningProfileExpirationUTC = provisioningProfileExpirationUTC
        self.ipaSHA256 = ipaSHA256
        self.ipaByteCount = ipaByteCount
        self.executableSHA256 = executableSHA256
        self.infoPlistSHA256 = infoPlistSHA256
        self.externalBuildRecordSHA256 = externalBuildRecordSHA256
        self.experimentRecipeID = experimentRecipeID
        self.procedureVersion = procedureVersion
    }

    /// Reconciles this parsed evidence declaration with the exact external record bytes and the
    /// build identity measured from the application that is actually running.
    ///
    /// Success is a mechanical rendezvous only. It intentionally returns the existing non-authority
    /// SoftwareExport comparison reference and cannot mutate the physical field-execution gate.
    public func makeMechanicallyBoundSoftwareExportReference(
        matching externalRecord: PassiveBluetoothCaptureExternalBuildRecord,
        running runtimeIdentity: PassiveBluetoothCaptureRuntimeBuildIdentity
    ) throws -> PassiveBluetoothExperimentOneSoftwareExportBuildReference {
        guard externalBuildRecordSHA256 == externalRecord.exactRecordSHA256 else {
            throw PassiveBluetoothCaptureSignedFieldArtifactEvidenceError.externalBuildRecordDigestMismatch
        }
        guard buildIdentifier == externalRecord.buildIdentifier,
              buildInstanceID == externalRecord.buildInstanceID,
              sourceCommitSHA == externalRecord.sourceCommitSHA,
              executableSHA256 == externalRecord.executableSHA256,
              infoPlistSHA256 == externalRecord.infoPlistSHA256,
              experimentRecipeID == externalRecord.experimentRecipeID,
              procedureVersion == externalRecord.procedureVersion else {
            throw PassiveBluetoothCaptureSignedFieldArtifactEvidenceError.externalBuildTupleMismatch
        }

        try externalRecord.validateRuntimeBinding(to: runtimeIdentity)
        return try externalRecord.makeSoftwareExportBuildReference()
    }
}

public enum PassiveBluetoothCaptureSignedFieldArtifactEvidenceError: Error, Equatable, Sendable {
    case malformedJSON
    case duplicateField(String)
    case unexpectedField(String)
    case unsupportedSchemaVersion(Int)
    case invalidAuthority
    case invalidBuildIdentifier
    case invalidBuildInstanceID
    case invalidSourceCommitSHA
    case invalidBundleIdentifier
    case invalidPlatformName
    case invalidSupportedPlatforms
    case invalidTeamIdentifier
    case invalidSigningAuthorities
    case invalidCodeDirectoryHash
    case invalidProvisioningProfileUUID
    case invalidProvisioningProfileExpirationUTC
    case invalidIPASHA256
    case invalidIPAByteCount
    case invalidExecutableSHA256
    case invalidInfoPlistSHA256
    case invalidExternalBuildRecordSHA256
    case unsupportedExperimentRecipe(String)
    case unsupportedProcedureVersion(String)
    case externalBuildRecordDigestMismatch
    case externalBuildTupleMismatch
}

public enum PassiveBluetoothCaptureSignedFieldArtifactEvidenceJSON {
    private struct WireV2: Decodable {
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
        let codeDirectoryHash: String
        let provisioningProfileUUID: String
        let provisioningProfileExpirationUTC: String
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
    ) throws -> PassiveBluetoothCaptureSignedFieldArtifactEvidence {
        try validateClosedWorldShape(data)

        let wire: WireV2
        do {
            wire = try JSONDecoder().decode(WireV2.self, from: data)
        } catch {
            throw PassiveBluetoothCaptureSignedFieldArtifactEvidenceError.malformedJSON
        }

        guard wire.schemaVersion == PassiveBluetoothCaptureSignedFieldArtifactEvidence.currentSchemaVersion else {
            throw PassiveBluetoothCaptureSignedFieldArtifactEvidenceError.unsupportedSchemaVersion(wire.schemaVersion)
        }
        guard wire.authority == PassiveBluetoothCaptureSignedFieldArtifactEvidence.requiredAuthority else {
            throw PassiveBluetoothCaptureSignedFieldArtifactEvidenceError.invalidAuthority
        }
        guard let normalizedSourceCommitSHA = PassiveBluetoothCaptureRuntimeBuildIdentityReader
            .normalizedFullGitCommitSHA(wire.sourceCommitSHA),
              normalizedSourceCommitSHA == wire.sourceCommitSHA else {
            throw PassiveBluetoothCaptureSignedFieldArtifactEvidenceError.invalidSourceCommitSHA
        }
        guard wire.buildIdentifier == "Capture Build V14-\(wire.sourceCommitSHA.prefix(12))" else {
            throw PassiveBluetoothCaptureSignedFieldArtifactEvidenceError.invalidBuildIdentifier
        }
        guard let normalizedBuildInstanceID = PassiveBluetoothCaptureRuntimeBuildIdentityReader
            .normalizedBuildInstanceID(wire.buildInstanceID),
              normalizedBuildInstanceID == wire.buildInstanceID else {
            throw PassiveBluetoothCaptureSignedFieldArtifactEvidenceError.invalidBuildInstanceID
        }
        guard wire.bundleIdentifier == PassiveBluetoothCaptureSignedFieldArtifactEvidence.requiredBundleIdentifier else {
            throw PassiveBluetoothCaptureSignedFieldArtifactEvidenceError.invalidBundleIdentifier
        }
        guard wire.platformName == PassiveBluetoothCaptureSignedFieldArtifactEvidence.requiredPlatformName else {
            throw PassiveBluetoothCaptureSignedFieldArtifactEvidenceError.invalidPlatformName
        }
        guard validSupportedPlatforms(wire.supportedPlatforms) else {
            throw PassiveBluetoothCaptureSignedFieldArtifactEvidenceError.invalidSupportedPlatforms
        }
        guard validTeamIdentifier(wire.teamIdentifier) else {
            throw PassiveBluetoothCaptureSignedFieldArtifactEvidenceError.invalidTeamIdentifier
        }
        guard validStringArray(wire.signingAuthorities) else {
            throw PassiveBluetoothCaptureSignedFieldArtifactEvidenceError.invalidSigningAuthorities
        }
        guard canonicalHex(wire.codeDirectoryHash, allowedLengths: 40...64) else {
            throw PassiveBluetoothCaptureSignedFieldArtifactEvidenceError.invalidCodeDirectoryHash
        }
        guard validBoundedString(wire.provisioningProfileUUID, maxUTF8Count: 128) else {
            throw PassiveBluetoothCaptureSignedFieldArtifactEvidenceError.invalidProvisioningProfileUUID
        }
        guard validUTCExpiration(wire.provisioningProfileExpirationUTC) else {
            throw PassiveBluetoothCaptureSignedFieldArtifactEvidenceError.invalidProvisioningProfileExpirationUTC
        }
        guard canonicalHex(wire.ipaSHA256, allowedLengths: 64...64) else {
            throw PassiveBluetoothCaptureSignedFieldArtifactEvidenceError.invalidIPASHA256
        }
        guard wire.ipaByteCount > 0 else {
            throw PassiveBluetoothCaptureSignedFieldArtifactEvidenceError.invalidIPAByteCount
        }
        guard canonicalHex(wire.executableSHA256, allowedLengths: 64...64) else {
            throw PassiveBluetoothCaptureSignedFieldArtifactEvidenceError.invalidExecutableSHA256
        }
        guard canonicalHex(wire.infoPlistSHA256, allowedLengths: 64...64) else {
            throw PassiveBluetoothCaptureSignedFieldArtifactEvidenceError.invalidInfoPlistSHA256
        }
        guard canonicalHex(wire.externalBuildRecordSHA256, allowedLengths: 64...64) else {
            throw PassiveBluetoothCaptureSignedFieldArtifactEvidenceError.invalidExternalBuildRecordSHA256
        }
        guard wire.experimentRecipeID == PassiveBluetoothExperimentRecipeID.es80FingerprintV1.rawValue else {
            throw PassiveBluetoothCaptureSignedFieldArtifactEvidenceError
                .unsupportedExperimentRecipe(wire.experimentRecipeID)
        }
        guard wire.procedureVersion == PassiveBluetoothCaptureExternalBuildRecord.requiredProcedureVersion else {
            throw PassiveBluetoothCaptureSignedFieldArtifactEvidenceError
                .unsupportedProcedureVersion(wire.procedureVersion)
        }

        return PassiveBluetoothCaptureSignedFieldArtifactEvidence(
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
            codeDirectoryHash: wire.codeDirectoryHash,
            provisioningProfileUUID: wire.provisioningProfileUUID,
            provisioningProfileExpirationUTC: wire.provisioningProfileExpirationUTC,
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
        if let duplicateKey = duplicateTopLevelObjectKey(in: data) {
            throw PassiveBluetoothCaptureSignedFieldArtifactEvidenceError.duplicateField(duplicateKey)
        }

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
            "signingAuthorities", "codeDirectoryHash", "provisioningProfileUUID",
            "provisioningProfileExpirationUTC", "ipaSHA256", "ipaByteCount", "executableSHA256",
            "infoPlistSHA256", "externalBuildRecordSHA256", "experimentRecipeID", "procedureVersion",
        ]
        for key in root.keys.sorted() where !allowed.contains(key) {
            throw PassiveBluetoothCaptureSignedFieldArtifactEvidenceError.unexpectedField(key)
        }
    }

    /// JSONSerialization and JSONDecoder both collapse duplicate object members into keyed storage.
    /// Scan the exact UTF-8 evidence bytes first so parser precedence can never choose between two
    /// conflicting declarations. Escaped and unescaped spellings of one semantic key are duplicates.
    private static func duplicateTopLevelObjectKey(in data: Data) -> String? {
        let bytes = Array(data)
        var objectDepth = 0
        var seenKeys = Set<String>()
        var index = 0

        while index < bytes.count {
            switch bytes[index] {
            case 0x7B: // {
                objectDepth += 1
            case 0x7D: // }
                objectDepth -= 1
            case 0x22: // "
                let stringStart = index
                index += 1
                var isEscaped = false

                while index < bytes.count {
                    let byte = bytes[index]
                    if isEscaped {
                        isEscaped = false
                    } else if byte == 0x5C { // \\
                        isEscaped = true
                    } else if byte == 0x22 {
                        break
                    }
                    index += 1
                }

                guard index < bytes.count else { return nil }
                let stringEnd = index

                if objectDepth == 1 {
                    var lookahead = index + 1
                    while lookahead < bytes.count, isJSONWhitespace(bytes[lookahead]) {
                        lookahead += 1
                    }
                    if lookahead < bytes.count, bytes[lookahead] == 0x3A { // :
                        let encodedKey = Data(bytes[stringStart...stringEnd])
                        if let key = try? JSONDecoder().decode(String.self, from: encodedKey),
                           !seenKeys.insert(key).inserted {
                            return key
                        }
                    }
                }
            default:
                break
            }
            index += 1
        }

        return nil
    }

    private static func isJSONWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D
    }

    private static func validSupportedPlatforms(_ values: [String]) -> Bool {
        guard values.contains("iPhoneOS"), validStringArray(values) else { return false }
        return !values.contains(where: { $0.localizedCaseInsensitiveContains("Simulator") })
    }

    private static func validTeamIdentifier(_ value: String) -> Bool {
        guard value.utf8.count == 10 else { return false }
        return value.utf8.allSatisfy { byte in
            (48...57).contains(byte) || (65...90).contains(byte)
        }
    }

    private static func validStringArray(_ values: [String]) -> Bool {
        guard !values.isEmpty, Set(values).count == values.count else { return false }
        return values.allSatisfy { validBoundedString($0, maxUTF8Count: 256) }
    }

    private static func validBoundedString(_ value: String, maxUTF8Count: Int) -> Bool {
        guard !value.isEmpty, value.utf8.count <= maxUTF8Count else { return false }
        guard value == value.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        return !value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }

    private static func validUTCExpiration(_ value: String) -> Bool {
        guard validBoundedString(value, maxUTF8Count: 64), value.hasSuffix("Z") else { return false }
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: value) != nil
    }

    private static func canonicalHex(_ value: String, allowedLengths: ClosedRange<Int>) -> Bool {
        guard allowedLengths.contains(value.utf8.count) else { return false }
        return value.utf8.allSatisfy { byte in
            (48...57).contains(byte) || (97...102).contains(byte)
        }
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
