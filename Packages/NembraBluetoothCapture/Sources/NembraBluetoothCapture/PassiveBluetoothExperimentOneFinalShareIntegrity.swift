import Foundation

/// Deterministic analysis-readiness facts derived from the exact primary Experiment One Share bytes.
///
/// Earning this report means the exact final-share bytes pass the package-owned outer procedure /
/// build-instance / nested-export digest checks, the exact nested SoftwareExport passes its current
/// closed-world evidence checks, and the exact nested immutable Capture bytes decode under the
/// current Capture schema.
///
/// This remains software readability and self-consistency evidence. It does not authenticate the
/// physical scooter, prove RF completeness, independently attest the build, authorize a field run,
/// or assign GATT/Tuya/DP/telemetry meaning to captured bytes.
public struct PassiveBluetoothExperimentOneFinalShareIntegrityReport: Equatable, Sendable {
    public let finalShareSHA256: String
    public let finalShareByteCount: Int
    public let experimentID: UUID
    public let experimentRecipeID: PassiveBluetoothExperimentRecipeID
    public let procedureVersion: String
    public let softwareExportSHA256: String
    public let capture: PassiveBluetoothFinalizedArtifactIntegrityReport
    public let buildIdentifier: String
    public let buildInstanceID: String
    public let sourceCommitSHA: String
    public let executableSHA256: String

    public init(
        finalShareSHA256: String,
        finalShareByteCount: Int,
        experimentID: UUID,
        experimentRecipeID: PassiveBluetoothExperimentRecipeID,
        procedureVersion: String,
        softwareExportSHA256: String,
        capture: PassiveBluetoothFinalizedArtifactIntegrityReport,
        buildIdentifier: String,
        buildInstanceID: String,
        sourceCommitSHA: String,
        executableSHA256: String
    ) {
        self.finalShareSHA256 = finalShareSHA256
        self.finalShareByteCount = finalShareByteCount
        self.experimentID = experimentID
        self.experimentRecipeID = experimentRecipeID
        self.procedureVersion = procedureVersion
        self.softwareExportSHA256 = softwareExportSHA256
        self.capture = capture
        self.buildIdentifier = buildIdentifier
        self.buildInstanceID = buildInstanceID
        self.sourceCommitSHA = sourceCommitSHA
        self.executableSHA256 = executableSHA256
    }
}

public enum PassiveBluetoothExperimentOneFinalShareIntegrity {
    /// Inspects exactly the bytes that the product intends to share. No re-encoding is used to earn
    /// the outer digest or nested Capture integrity facts.
    public static func inspect(
        _ data: Data
    ) throws -> PassiveBluetoothExperimentOneFinalShareIntegrityReport {
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
            softwareExportSHA256: verified.softwareExportSHA256,
            capture: capture,
            buildIdentifier: verified.softwareExport.build.buildIdentifier,
            buildInstanceID: verified.buildInstanceID,
            sourceCommitSHA: verified.softwareExport.build.sourceCommitSHA,
            executableSHA256: verified.softwareExport.build.executableSHA256
        )
    }
}
