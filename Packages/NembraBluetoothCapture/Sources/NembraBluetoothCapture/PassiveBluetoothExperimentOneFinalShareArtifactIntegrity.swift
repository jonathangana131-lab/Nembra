import Foundation

/// Deterministic analysis-readiness facts for the exact V14 Experiment One bytes offered by the
/// product's primary Share action.
///
/// Earning this report means the exact outer final-share bytes pass their closed-world
/// procedure/build rendezvous, the exact nested SoftwareExport passes its own closed-world evidence
/// verification, and the exact nested immutable Capture bytes decode under the current Capture
/// schema. It remains software evidence only: no physical ES80 authentication, RF completeness,
/// protocol meaning, external signed-build attestation, or field authorization is implied.
public struct PassiveBluetoothExperimentOneFinalShareArtifactIntegrityReport: Equatable, Sendable {
    public let finalShareSHA256: String
    public let finalShareByteCount: Int
    public let experimentID: UUID
    public let experimentRecipeID: PassiveBluetoothExperimentRecipeID
    public let procedureVersion: String
    public let buildIdentifier: String
    public let buildInstanceID: String
    public let sourceCommitSHA: String
    public let executableSHA256: String
    public let softwareExportSHA256: String
    public let capture: PassiveBluetoothFinalizedArtifactIntegrityReport

    public init(
        finalShareSHA256: String,
        finalShareByteCount: Int,
        experimentID: UUID,
        experimentRecipeID: PassiveBluetoothExperimentRecipeID,
        procedureVersion: String,
        buildIdentifier: String,
        buildInstanceID: String,
        sourceCommitSHA: String,
        executableSHA256: String,
        softwareExportSHA256: String,
        capture: PassiveBluetoothFinalizedArtifactIntegrityReport
    ) {
        self.finalShareSHA256 = finalShareSHA256
        self.finalShareByteCount = finalShareByteCount
        self.experimentID = experimentID
        self.experimentRecipeID = experimentRecipeID
        self.procedureVersion = procedureVersion
        self.buildIdentifier = buildIdentifier
        self.buildInstanceID = buildInstanceID
        self.sourceCommitSHA = sourceCommitSHA
        self.executableSHA256 = executableSHA256
        self.softwareExportSHA256 = softwareExportSHA256
        self.capture = capture
    }
}

public enum PassiveBluetoothExperimentOneFinalShareArtifactIntegrity {
    /// Inspects the exact primary Share bytes without re-encoding them.
    ///
    /// A caller that presents `Ready for analysis` must preserve and share these same `data` bytes.
    /// Rebuilding the final-share wrapper would create a different exact artifact even if its nested
    /// capture remained equivalent.
    public static func inspect(
        _ data: Data
    ) throws -> PassiveBluetoothExperimentOneFinalShareArtifactIntegrityReport {
        let verified = try PassiveBluetoothExperimentOneFinalShareArtifactCodec.decodeAndVerify(data)
        let capture = try PassiveBluetoothFinalizedArtifactIntegrity.inspect(
            verified.softwareExport.captureJSON
        )

        return .init(
            finalShareSHA256: PassiveBluetoothFinalizedArtifactIntegrity.sha256Hex(of: data),
            finalShareByteCount: data.count,
            experimentID: verified.experimentID,
            experimentRecipeID: verified.experimentRecipeID,
            procedureVersion: verified.procedureVersion,
            buildIdentifier: verified.softwareExport.build.buildIdentifier,
            buildInstanceID: verified.buildInstanceID,
            sourceCommitSHA: verified.softwareExport.build.sourceCommitSHA,
            executableSHA256: verified.softwareExport.build.executableSHA256,
            softwareExportSHA256: verified.softwareExportSHA256,
            capture: capture
        )
    }
}
