import Foundation

/// Deterministic readability/integrity facts for the exact final Experiment One Share bytes.
///
/// Success means the outer procedure wrapper and its exact nested SoftwareExport both pass their
/// package-owned closed-world verifiers, and the exact nested immutable Capture bytes are readable
/// under the current Capture schema. This is analysis-readiness evidence only. It does not
/// authenticate a physical ES80, prove RF completeness, attest the signed field build, authorize a
/// physical run, or assign protocol/telemetry meaning to any captured bytes.
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
    case exactSoftwareExportBytesUnavailable
    case nestedSoftwareExportDigestMismatch
}

public enum PassiveBluetoothExperimentOneFinalShareArtifactIntegrity {
    /// Inspects the exact bytes intended for the primary Share action without re-encoding them.
    ///
    /// Callers that present `Ready for analysis` must retain/share these same outer `data` bytes.
    public static func inspect(
        _ data: Data
    ) throws -> PassiveBluetoothExperimentOneFinalShareArtifactIntegrityReport {
        let verified = try PassiveBluetoothExperimentOneFinalShareArtifactCodec.decodeAndVerify(data)

        // The outer codec has already enforced the schema's closed-world shape. Extracting the exact
        // nested bytes here lets the existing SoftwareExport integrity inspector hash the bytes that
        // were actually carried by the final Share artifact rather than a re-encoding of its model.
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let encodedSoftwareExport = root["softwareExportJSONBase64"] as? String,
              let softwareExportJSON = Data(base64Encoded: encodedSoftwareExport) else {
            throw PassiveBluetoothExperimentOneFinalShareArtifactIntegrityError
                .exactSoftwareExportBytesUnavailable
        }

        let softwareExport = try PassiveBluetoothExperimentOneSoftwareExportIntegrity.inspect(
            softwareExportJSON
        )
        guard softwareExport.envelopeSHA256 == verified.softwareExportSHA256 else {
            throw PassiveBluetoothExperimentOneFinalShareArtifactIntegrityError
                .nestedSoftwareExportDigestMismatch
        }

        return .init(
            finalShareSHA256: PassiveBluetoothFinalizedArtifactIntegrity.sha256Hex(of: data),
            finalShareByteCount: data.count,
            experimentID: verified.experimentID,
            experimentRecipeID: verified.experimentRecipeID,
            procedureVersion: verified.procedureVersion,
            buildInstanceID: verified.buildInstanceID,
            softwareExport: softwareExport
        )
    }
}