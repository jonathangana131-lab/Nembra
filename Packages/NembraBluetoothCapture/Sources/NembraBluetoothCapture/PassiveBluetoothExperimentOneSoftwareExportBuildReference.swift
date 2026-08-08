import Foundation

/// Exact produced-build values supplied by an independently evaluated build/GO record.
///
/// This type is a comparison input only. Constructing it does not make the values trusted,
/// attested, accepted, or field-authorized. A caller must establish that external authority before
/// using a successful software-export match as one input to physical field admission.
public struct PassiveBluetoothExperimentOneSoftwareExportBuildReference: Equatable, Sendable {
    public let buildIdentifier: String
    public let buildInstanceID: String
    public let sourceCommitSHA: String
    public let executableSHA256: String

    public init(
        buildIdentifier: String,
        buildInstanceID: String,
        sourceCommitSHA: String,
        executableSHA256: String
    ) throws {
        guard !buildIdentifier.isEmpty,
              buildIdentifier.utf8.count <= 128,
              buildIdentifier == buildIdentifier.trimmingCharacters(in: .whitespacesAndNewlines),
              !buildIdentifier.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              PassiveBluetoothCaptureRuntimeBuildIdentityReader.normalizedBuildInstanceID(buildInstanceID) == buildInstanceID,
              PassiveBluetoothCaptureRuntimeBuildIdentityReader.normalizedFullGitCommitSHA(sourceCommitSHA) == sourceCommitSHA,
              executableSHA256.utf8.count == 64,
              executableSHA256.utf8.allSatisfy({ byte in
                  (48...57).contains(byte) || (97...102).contains(byte)
              }) else {
            throw PassiveBluetoothExperimentOneSoftwareExportBuildReferenceError.malformedReference
        }

        self.buildIdentifier = buildIdentifier
        self.buildInstanceID = buildInstanceID
        self.sourceCommitSHA = sourceCommitSHA
        self.executableSHA256 = executableSHA256
    }
}

public enum PassiveBluetoothExperimentOneSoftwareExportBuildReferenceError: Error, Equatable, Sendable {
    case malformedReference
    case mismatch
}

public extension PassiveBluetoothExperimentOneSoftwareExportCodec {
    /// Verifies the export's existing closed-world software/recipe contract, then compares all exact
    /// produced-build fields against a separately supplied reference, including executable SHA-256.
    ///
    /// Equality does not authenticate the reference itself. External attestation/acceptance remains
    /// a separate authority boundary and physical Experiment One remains gated independently.
    static func decodeAndVerify(
        _ data: Data,
        matching buildReference: PassiveBluetoothExperimentOneSoftwareExportBuildReference
    ) throws -> PassiveBluetoothExperimentOneSoftwareExport {
        let export = try decodeAndVerify(data)
        guard export.build.buildIdentifier == buildReference.buildIdentifier,
              export.build.buildInstanceID == buildReference.buildInstanceID,
              export.build.sourceCommitSHA == buildReference.sourceCommitSHA,
              export.build.executableSHA256 == buildReference.executableSHA256 else {
            throw PassiveBluetoothExperimentOneSoftwareExportBuildReferenceError.mismatch
        }
        return export
    }
}
