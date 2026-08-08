import Foundation

/// Build record bundled with the field application by the trusted build/acceptance pipeline.
///
/// The record is still software provenance, not physical ES80 evidence and not a claim that the
/// embedded source commit cryptographically produced the executable. Its purpose is narrower:
/// provide an independently generated expected executable digest and procedure identity that the
/// running app can compare against its own measured executable bytes before field work.
public struct PassiveBluetoothCaptureTrustedBuildRecord: Equatable, Sendable {
    public let schemaVersion: Int
    public let buildIdentifier: String
    public let sourceCommitSHA: String
    public let executableSHA256: String
    public let experimentRecipeID: PassiveBluetoothExperimentRecipeID
    public let procedureVersion: String

    fileprivate init(
        schemaVersion: Int,
        buildIdentifier: String,
        sourceCommitSHA: String,
        executableSHA256: String,
        experimentRecipeID: PassiveBluetoothExperimentRecipeID,
        procedureVersion: String
    ) {
        self.schemaVersion = schemaVersion
        self.buildIdentifier = buildIdentifier
        self.sourceCommitSHA = sourceCommitSHA
        self.executableSHA256 = executableSHA256
        self.experimentRecipeID = experimentRecipeID
        self.procedureVersion = procedureVersion
    }
}

public enum PassiveBluetoothCaptureTrustedBuildRecordError: Error, Equatable, Sendable {
    case missingTrustedBuildRecord
    case trustedBuildRecordUnreadable
    case malformedTrustedBuildRecord
    case unexpectedTrustedBuildRecordFields([String])
    case unsupportedSchemaVersion(Int)
    case invalidBuildIdentifier
    case invalidSourceCommitSHA
    case invalidExecutableSHA256
    case unsupportedExperimentRecipeID(String)
    case invalidProcedureVersion
}

/// Production reader for the build record carried by the running application bundle.
///
/// There is deliberately no public API that accepts an arbitrary URL, dictionary, or record value.
/// Final field builds must receive `NembraCaptureTrustedBuildRecord.json` from the accepted build
/// pipeline. Tests use the package-scoped decoder to exercise the closed-world format.
public enum PassiveBluetoothCaptureTrustedBuildRecordReader {
    public static let resourceName = "NembraCaptureTrustedBuildRecord"
    public static let resourceExtension = "json"
    public static let currentSchemaVersion = 1
    public static let requiredExperimentRecipeID = PassiveBluetoothExperimentRecipeID.es80FingerprintV1
    public static let requiredProcedureVersion = "V14"

    private static let expectedWireKeys: Set<String> = [
        "schemaVersion",
        "buildIdentifier",
        "sourceCommitSHA",
        "executableSHA256",
        "experimentRecipeID",
        "procedureVersion",
    ]

    public static func currentApplication() throws -> PassiveBluetoothCaptureTrustedBuildRecord {
        guard let url = Bundle.main.url(
            forResource: resourceName,
            withExtension: resourceExtension
        ) else {
            throw PassiveBluetoothCaptureTrustedBuildRecordError.missingTrustedBuildRecord
        }

        let data: Data
        do {
            data = try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            throw PassiveBluetoothCaptureTrustedBuildRecordError.trustedBuildRecordUnreadable
        }

        return try decodeTrustedRecord(data)
    }

    package static func decodeTrustedRecord(
        _ data: Data
    ) throws -> PassiveBluetoothCaptureTrustedBuildRecord {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw PassiveBluetoothCaptureTrustedBuildRecordError.malformedTrustedBuildRecord
        }

        guard let dictionary = object as? [String: Any] else {
            throw PassiveBluetoothCaptureTrustedBuildRecordError.malformedTrustedBuildRecord
        }

        let actualKeys = Set(dictionary.keys)
        let unexpectedKeys = actualKeys.subtracting(expectedWireKeys).sorted()
        guard unexpectedKeys.isEmpty else {
            throw PassiveBluetoothCaptureTrustedBuildRecordError.unexpectedTrustedBuildRecordFields(
                unexpectedKeys
            )
        }
        guard actualKeys == expectedWireKeys else {
            throw PassiveBluetoothCaptureTrustedBuildRecordError.malformedTrustedBuildRecord
        }

        let wire: WireRecord
        do {
            wire = try JSONDecoder().decode(WireRecord.self, from: data)
        } catch {
            throw PassiveBluetoothCaptureTrustedBuildRecordError.malformedTrustedBuildRecord
        }

        guard wire.schemaVersion == currentSchemaVersion else {
            throw PassiveBluetoothCaptureTrustedBuildRecordError.unsupportedSchemaVersion(
                wire.schemaVersion
            )
        }
        guard isValidShortIdentifier(wire.buildIdentifier) else {
            throw PassiveBluetoothCaptureTrustedBuildRecordError.invalidBuildIdentifier
        }
        guard let normalizedCommit = PassiveBluetoothCaptureRuntimeBuildIdentityReader
            .normalizedFullGitCommitSHA(wire.sourceCommitSHA) else {
            throw PassiveBluetoothCaptureTrustedBuildRecordError.invalidSourceCommitSHA
        }
        guard isCanonicalSHA256(wire.executableSHA256) else {
            throw PassiveBluetoothCaptureTrustedBuildRecordError.invalidExecutableSHA256
        }
        guard let recipeID = PassiveBluetoothExperimentRecipeID(rawValue: wire.experimentRecipeID) else {
            throw PassiveBluetoothCaptureTrustedBuildRecordError.unsupportedExperimentRecipeID(
                wire.experimentRecipeID
            )
        }
        guard recipeID == requiredExperimentRecipeID else {
            throw PassiveBluetoothCaptureTrustedBuildRecordError.unsupportedExperimentRecipeID(
                wire.experimentRecipeID
            )
        }
        guard isValidShortIdentifier(wire.procedureVersion) else {
            throw PassiveBluetoothCaptureTrustedBuildRecordError.invalidProcedureVersion
        }
        guard wire.procedureVersion == requiredProcedureVersion else {
            throw PassiveBluetoothCaptureTrustedBuildRecordError.invalidProcedureVersion
        }

        return PassiveBluetoothCaptureTrustedBuildRecord(
            schemaVersion: wire.schemaVersion,
            buildIdentifier: wire.buildIdentifier,
            sourceCommitSHA: normalizedCommit,
            executableSHA256: wire.executableSHA256,
            experimentRecipeID: recipeID,
            procedureVersion: wire.procedureVersion
        )
    }

    private static func isCanonicalSHA256(_ value: String) -> Bool {
        guard value.utf8.count == 64 else { return false }
        return value.utf8.allSatisfy { byte in
            (48...57).contains(byte) || (97...102).contains(byte)
        }
    }

    private static func isValidShortIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 128 else { return false }
        guard value == value.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        return !value.unicodeScalars.contains { scalar in
            CharacterSet.controlCharacters.contains(scalar)
        }
    }

    private struct WireRecord: Decodable {
        let schemaVersion: Int
        let buildIdentifier: String
        let sourceCommitSHA: String
        let executableSHA256: String
        let experimentRecipeID: String
        let procedureVersion: String
    }
}

/// Result of comparing the measured running executable against the bundled trusted build record.
///
/// This is a software build-binding result only. It does not authorize the physical procedure;
/// `PassiveBluetoothExperimentOneFieldExecutionGate` remains the independent mechanical GO/NO-GO
/// authority and is intentionally untouched by this preflight layer.
public struct PassiveBluetoothCaptureRuntimeBuildBinding: Equatable, Sendable {
    public let buildIdentifier: String
    public let sourceCommitSHA: String
    public let executableSHA256: String
    public let experimentRecipeID: PassiveBluetoothExperimentRecipeID
    public let procedureVersion: String

    fileprivate init(record: PassiveBluetoothCaptureTrustedBuildRecord) {
        buildIdentifier = record.buildIdentifier
        sourceCommitSHA = record.sourceCommitSHA
        executableSHA256 = record.executableSHA256
        experimentRecipeID = record.experimentRecipeID
        procedureVersion = record.procedureVersion
    }
}

public enum PassiveBluetoothCaptureBuildPreflightError: Error, Equatable, Sendable {
    case buildIdentifierMismatch
    case sourceCommitSHAMismatch
    case executableSHA256Mismatch
}

/// Sealed production preflight for exact field-build identity.
///
/// Production has one entry point: measure the running executable, read the app-bundled trusted
/// record, and compare them exactly. Callers cannot supply either side to the public API.
public enum PassiveBluetoothCaptureBuildPreflight {
    public static func currentApplication() throws -> PassiveBluetoothCaptureRuntimeBuildBinding {
        let runtimeIdentity = try PassiveBluetoothCaptureRuntimeBuildIdentityReader.currentApplication()
        let trustedRecord = try PassiveBluetoothCaptureTrustedBuildRecordReader.currentApplication()
        return try evaluate(runtimeIdentity: runtimeIdentity, trustedRecord: trustedRecord)
    }

    package static func evaluate(
        runtimeIdentity: PassiveBluetoothCaptureRuntimeBuildIdentity,
        trustedRecord: PassiveBluetoothCaptureTrustedBuildRecord
    ) throws -> PassiveBluetoothCaptureRuntimeBuildBinding {
        guard runtimeIdentity.buildIdentifier == trustedRecord.buildIdentifier else {
            throw PassiveBluetoothCaptureBuildPreflightError.buildIdentifierMismatch
        }
        guard runtimeIdentity.sourceCommitSHA == trustedRecord.sourceCommitSHA else {
            throw PassiveBluetoothCaptureBuildPreflightError.sourceCommitSHAMismatch
        }
        guard runtimeIdentity.executableSHA256 == trustedRecord.executableSHA256 else {
            throw PassiveBluetoothCaptureBuildPreflightError.executableSHA256Mismatch
        }

        return PassiveBluetoothCaptureRuntimeBuildBinding(record: trustedRecord)
    }
}
