import Foundation

/// Deterministic integrity/readability facts for the exact package-owned bytes presented by the
/// primary Experiment One Share action.
///
/// Success proves that the exact outer final-share bytes pass their closed-world procedure/build
/// rendezvous checks, that the nested SoftwareExport passes its existing closed-world evidence
/// checks, and that the exact nested immutable Capture bytes decode under the current Capture
/// schema. It does not authenticate the physical scooter, prove RF completeness, independently
/// attest the source-to-binary build chain, authorize a field run, or assign protocol semantics.
public struct PassiveBluetoothExperimentOneFinalShareIntegrityReport: Equatable, Sendable {
    public let finalShareSHA256: String
    public let finalShareByteCount: Int
    public let experimentID: UUID
    public let experimentRecipeID: PassiveBluetoothExperimentRecipeID
    public let procedureVersion: String
    public let buildInstanceID: String
    public let softwareExportSHA256: String
    public let capture: PassiveBluetoothFinalizedArtifactIntegrityReport
    public let buildIdentifier: String
    public let sourceCommitSHA: String
    public let executableSHA256: String

    public init(
        finalShareSHA256: String,
        finalShareByteCount: Int,
        experimentID: UUID,
        experimentRecipeID: PassiveBluetoothExperimentRecipeID,
        procedureVersion: String,
        buildInstanceID: String,
        softwareExportSHA256: String,
        capture: PassiveBluetoothFinalizedArtifactIntegrityReport,
        buildIdentifier: String,
        sourceCommitSHA: String,
        executableSHA256: String
    ) {
        self.finalShareSHA256 = finalShareSHA256
        self.finalShareByteCount = finalShareByteCount
        self.experimentID = experimentID
        self.experimentRecipeID = experimentRecipeID
        self.procedureVersion = procedureVersion
        self.buildInstanceID = buildInstanceID
        self.softwareExportSHA256 = softwareExportSHA256
        self.capture = capture
        self.buildIdentifier = buildIdentifier
        self.sourceCommitSHA = sourceCommitSHA
        self.executableSHA256 = executableSHA256
    }
}

public enum PassiveBluetoothExperimentOneFinalShareIntegrity {
    /// Verifies the exact bytes that should be staged to disk and passed to `ShareLink`.
    ///
    /// Callers that present an analysis-ready state must preserve/share these same `data` bytes.
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
            buildInstanceID: verified.buildInstanceID,
            softwareExportSHA256: verified.softwareExportSHA256,
            capture: capture,
            buildIdentifier: verified.softwareExport.build.buildIdentifier,
            sourceCommitSHA: verified.softwareExport.build.sourceCommitSHA,
            executableSHA256: verified.softwareExport.build.executableSHA256
        )
    }
}
