import Foundation

/// Deterministic integrity/readability facts for the exact package-owned Experiment One software
/// envelope bytes offered for Share.
///
/// Earning this report means the exact outer bytes decode under the current closed-world software
/// export schema, all export self-consistency checks pass, and the exact nested immutable Capture
/// bytes decode under the current Capture schema. It does not authenticate the physical scooter,
/// prove RF completeness, attest the source-to-binary build chain, authorize a field run, or assign
/// protocol/telemetry meaning to any recorded bytes.
public struct PassiveBluetoothExperimentOneSoftwareExportIntegrityReport: Equatable, Sendable {
    public let envelopeSHA256: String
    public let envelopeByteCount: Int
    public let capture: PassiveBluetoothFinalizedArtifactIntegrityReport
    public let experimentRecipeID: PassiveBluetoothExperimentRecipeID
    public let buildIdentifier: String
    public let buildInstanceID: String
    public let sourceCommitSHA: String
    public let executableSHA256: String

    // Keep the evidence-bearing value package-constructed. Public clients may inspect verified
    // facts but cannot mint a report that bypasses SoftwareExportIntegrity.inspect(_:).
    init(
        envelopeSHA256: String,
        envelopeByteCount: Int,
        capture: PassiveBluetoothFinalizedArtifactIntegrityReport,
        experimentRecipeID: PassiveBluetoothExperimentRecipeID,
        buildIdentifier: String,
        buildInstanceID: String,
        sourceCommitSHA: String,
        executableSHA256: String
    ) {
        self.envelopeSHA256 = envelopeSHA256
        self.envelopeByteCount = envelopeByteCount
        self.capture = capture
        self.experimentRecipeID = experimentRecipeID
        self.buildIdentifier = buildIdentifier
        self.buildInstanceID = buildInstanceID
        self.sourceCommitSHA = sourceCommitSHA
        self.executableSHA256 = executableSHA256
    }
}

public enum PassiveBluetoothExperimentOneSoftwareExportIntegrity {
    /// Verifies the exact Share-envelope bytes without re-encoding them.
    ///
    /// Callers that present an analysis-ready state must preserve/share these same `data` bytes.
    public static func inspect(
        _ data: Data
    ) throws -> PassiveBluetoothExperimentOneSoftwareExportIntegrityReport {
        let export = try PassiveBluetoothExperimentOneSoftwareExportCodec.decodeAndVerify(data)
        let capture = try PassiveBluetoothFinalizedArtifactIntegrity.inspect(export.captureJSON)

        return .init(
            envelopeSHA256: PassiveBluetoothFinalizedArtifactIntegrity.sha256Hex(of: data),
            envelopeByteCount: data.count,
            capture: capture,
            experimentRecipeID: export.experimentRecipeID,
            buildIdentifier: export.build.buildIdentifier,
            buildInstanceID: export.build.buildInstanceID,
            sourceCommitSHA: export.build.sourceCommitSHA,
            executableSHA256: export.build.executableSHA256
        )
    }
}
