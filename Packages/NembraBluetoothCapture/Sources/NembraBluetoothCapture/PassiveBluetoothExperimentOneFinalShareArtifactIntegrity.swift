import Foundation

/// Deterministic readability/integrity facts for the exact package-owned Experiment One bytes
/// presented by the primary Share action.
///
/// Earning this report means the exact outer final-share bytes pass their closed-world
/// procedure/build rendezvous checks, the exact nested SoftwareExport bytes pass their own
/// closed-world self-consistency checks, and the exact immutable Capture bytes decode under the
/// current Capture schema. It does not authenticate the physical scooter, prove RF completeness,
/// attest source-to-binary provenance, authorize a field run, or assign protocol/telemetry meaning.
public struct PassiveBluetoothExperimentOneFinalShareArtifactIntegrityReport: Equatable, Sendable {
    public let finalShareSHA256: String
    public let finalShareByteCount: Int
    public let experimentID: UUID
    public let experimentRecipeID: PassiveBluetoothExperimentRecipeID
    public let procedureVersion: String
    public let buildInstanceID: String
    public let softwareExport: PassiveBluetoothExperimentOneSoftwareExportIntegrityReport

    public init(
        finalShareSHA256: String,
        finalShareByteCount: Int,
        experimentID: UUID,
        experimentRecipeID: PassiveBluetoothExperimentRecipeID,
        procedureVersion: String,
        buildInstanceID: String,
        softwareExport: PassiveBluetoothExperimentOneSoftwareExportIntegrityReport
    ) {
        self.finalShareSHA256 = finalShareSHA256
        self.finalShareByteCount = finalShareByteCount
        self.experimentID = experimentID
        self.experimentRecipeID = experimentRecipeID
        self.procedureVersion = procedureVersion
        self.buildInstanceID = buildInstanceID
        self.softwareExport = softwareExport
    }
}

public enum PassiveBluetoothExperimentOneFinalShareArtifactIntegrityError: Error, Equatable, Sendable {
    case nestedSoftwareExportBytesUnavailable
    case nestedSoftwareExportDigestMismatch
    case nestedSoftwareExportRecipeMismatch
    case nestedSoftwareExportBuildInstanceMismatch
}

public enum PassiveBluetoothExperimentOneFinalShareArtifactIntegrity {
    /// Verifies the exact primary Share bytes without re-encoding any evidence layer.
    ///
    /// Callers that present an analysis-ready state must retain/share the same `data` bytes.
    public static func inspect(
        _ data: Data
    ) throws -> PassiveBluetoothExperimentOneFinalShareArtifactIntegrityReport {
        let verifiedFinalShare = try PassiveBluetoothExperimentOneFinalShareArtifactCodec
            .decodeAndVerify(data)

        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let nestedBase64 = root["softwareExportJSONBase64"] as? String,
              let nestedSoftwareExportJSON = Data(base64Encoded: nestedBase64) else {
            throw PassiveBluetoothExperimentOneFinalShareArtifactIntegrityError
                .nestedSoftwareExportBytesUnavailable
        }

        let softwareExport = try PassiveBluetoothExperimentOneSoftwareExportIntegrity
            .inspect(nestedSoftwareExportJSON)
        guard softwareExport.envelopeSHA256 == verifiedFinalShare.softwareExportSHA256 else {
            throw PassiveBluetoothExperimentOneFinalShareArtifactIntegrityError
                .nestedSoftwareExportDigestMismatch
        }
        guard softwareExport.experimentRecipeID == verifiedFinalShare.experimentRecipeID else {
            throw PassiveBluetoothExperimentOneFinalShareArtifactIntegrityError
                .nestedSoftwareExportRecipeMismatch
        }
        guard softwareExport.buildInstanceID == verifiedFinalShare.buildInstanceID else {
            throw PassiveBluetoothExperimentOneFinalShareArtifactIntegrityError
                .nestedSoftwareExportBuildInstanceMismatch
        }

        return .init(
            finalShareSHA256: PassiveBluetoothFinalizedArtifactIntegrity.sha256Hex(of: data),
            finalShareByteCount: data.count,
            experimentID: verifiedFinalShare.experimentID,
            experimentRecipeID: verifiedFinalShare.experimentRecipeID,
            procedureVersion: verifiedFinalShare.procedureVersion,
            buildInstanceID: verifiedFinalShare.buildInstanceID,
            softwareExport: softwareExport
        )
    }
}