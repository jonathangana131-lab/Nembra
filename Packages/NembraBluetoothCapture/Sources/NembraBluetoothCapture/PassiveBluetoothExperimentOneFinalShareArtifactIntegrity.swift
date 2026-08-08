import Foundation

/// Deterministic integrity/readability facts for the exact final Experiment One bytes presented to
/// the system Share sheet.
///
/// Success means the exact outer final-share bytes pass the package's closed-world procedure/build
/// rendezvous verification, the exact nested SoftwareExport passes its closed-world evidence checks,
/// and the exact nested immutable Capture bytes remain readable by the current Capture schema.
/// This is software self-consistency only. It does not authenticate the physical ES80, prove RF
/// completeness, independently attest the executable/build chain, authorize a field run, or assign
/// protocol/telemetry meaning to captured bytes.
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
    /// Verifies the exact final Share bytes without re-encoding them and returns stable facts the
    /// product can use for an analysis-readiness state and Engineering Details.
    ///
    /// Callers that present `Ready for analysis` must preserve/share these same `data` bytes. A
    /// temporary-file staging retry must therefore restage the retained bytes rather than ask the
    /// coordinator to mint a second final artifact.
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
