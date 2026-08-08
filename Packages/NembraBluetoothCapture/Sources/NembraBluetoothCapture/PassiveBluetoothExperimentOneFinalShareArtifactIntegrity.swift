import Foundation

/// Integrity/readability facts for the exact outer Experiment One bytes presented by the primary
/// Share action.
///
/// This report is intentionally layered: `finalShareSHA256` names the exact file the rider will
/// share, while `softwareExport` and its nested Capture report describe the already-verified bytes
/// carried inside that file. Earning this report proves software self-consistency only. It does not
/// authenticate a physical ES80, attest the source-to-binary build chain, or authorize a field run.
public struct PassiveBluetoothExperimentOneFinalShareArtifactIntegrityReport: Equatable, Sendable {
    public let finalShareSHA256: String
    public let finalShareByteCount: Int
    public let experimentID: UUID
    public let experimentRecipeID: PassiveBluetoothExperimentRecipeID
    public let procedureVersion: String
    public let buildInstanceID: String
    public let softwareExportSHA256: String
    public let softwareExport: PassiveBluetoothExperimentOneSoftwareExportIntegrityReport

    public init(
        finalShareSHA256: String,
        finalShareByteCount: Int,
        experimentID: UUID,
        experimentRecipeID: PassiveBluetoothExperimentRecipeID,
        procedureVersion: String,
        buildInstanceID: String,
        softwareExportSHA256: String,
        softwareExport: PassiveBluetoothExperimentOneSoftwareExportIntegrityReport
    ) {
        self.finalShareSHA256 = finalShareSHA256
        self.finalShareByteCount = finalShareByteCount
        self.experimentID = experimentID
        self.experimentRecipeID = experimentRecipeID
        self.procedureVersion = procedureVersion
        self.buildInstanceID = buildInstanceID
        self.softwareExportSHA256 = softwareExportSHA256
        self.softwareExport = softwareExport
    }
}

public enum PassiveBluetoothExperimentOneFinalShareArtifactIntegrity {
    /// Verifies the exact primary Share bytes without re-encoding either envelope.
    ///
    /// Callers that present `Ready for analysis` must preserve and share these same `data` bytes.
    public static func inspect(
        _ data: Data
    ) throws -> PassiveBluetoothExperimentOneFinalShareArtifactIntegrityReport {
        let verified = try PassiveBluetoothExperimentOneFinalShareArtifactCodec.decodeAndVerify(data)

        // The final-share codec has already performed closed-world validation and the exact nested
        // SHA-256 check. Recover the original base64 payload only so the nested integrity inspector
        // sees the very bytes bound by that digest; never re-encode the decoded software export.
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let encodedSoftwareExport = root["softwareExportJSONBase64"] as? String,
              let softwareExportJSON = Data(base64Encoded: encodedSoftwareExport) else {
            throw PassiveBluetoothExperimentOneFinalShareArtifactError.malformedWireData
        }

        let softwareExport = try PassiveBluetoothExperimentOneSoftwareExportIntegrity.inspect(
            softwareExportJSON
        )
        guard softwareExport.envelopeSHA256 == verified.softwareExportSHA256,
              softwareExport.experimentRecipeID == verified.experimentRecipeID,
              softwareExport.buildInstanceID == verified.buildInstanceID else {
            // The final-share verifier should make this unreachable; retain a fail-closed boundary
            // if either verifier evolves independently in the future.
            throw PassiveBluetoothExperimentOneFinalShareArtifactError.softwareExportDigestMismatch
        }

        return .init(
            finalShareSHA256: PassiveBluetoothFinalizedArtifactIntegrity.sha256Hex(of: data),
            finalShareByteCount: data.count,
            experimentID: verified.experimentID,
            experimentRecipeID: verified.experimentRecipeID,
            procedureVersion: verified.procedureVersion,
            buildInstanceID: verified.buildInstanceID,
            softwareExportSHA256: verified.softwareExportSHA256,
            softwareExport: softwareExport
        )
    }
}
