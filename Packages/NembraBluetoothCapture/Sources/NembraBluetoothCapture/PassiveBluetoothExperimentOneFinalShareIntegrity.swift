import Foundation

/// Deterministic analysis-readiness facts for the exact package-owned final Share bytes.
///
/// Earning this report means the outer final-share artifact passed its closed-world procedure/build
/// rendezvous, the exact nested SoftwareExport bytes passed their own closed-world verification,
/// and the exact nested immutable Capture bytes decoded under the current Capture schema. This is
/// software readability/integrity evidence only; it is not physical ES80 authentication or GO.
public struct PassiveBluetoothExperimentOneFinalShareIntegrityReport: Equatable, Sendable {
    public let finalShareSHA256: String
    public let finalShareByteCount: Int
    public let experimentID: UUID
    public let experimentRecipeID: PassiveBluetoothExperimentRecipeID
    public let procedureVersion: String
    public let buildInstanceID: String
    public let softwareExport: PassiveBluetoothExperimentOneSoftwareExportIntegrityReport

    // Package-owned construction is deliberate: product code treats possession of this value as
    // evidence that inspect(_:) accepted the exact final Share bytes. Public clients may read the
    // facts but cannot manufacture an analysis-ready report from caller-selected fields.
    init(
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

public enum PassiveBluetoothExperimentOneFinalShareIntegrityError: Error, Equatable, Sendable {
    case nestedSoftwareExportDigestMismatch
    case nestedBuildInstanceMismatch
    case nestedRecipeMismatch
}

public enum PassiveBluetoothExperimentOneFinalShareIntegrity {
    /// Verifies the exact final Share bytes without re-encoding either evidence layer.
    ///
    /// A caller may present `Ready for analysis` only for the same `data` bytes that earned this
    /// report. Temporary-file staging may fail later without revoking the report or sealed capture.
    public static func inspect(
        _ data: Data
    ) throws -> PassiveBluetoothExperimentOneFinalShareIntegrityReport {
        let verified = try PassiveBluetoothExperimentOneFinalShareArtifactCodec.decodeAndVerify(data)
        let softwareReport = try PassiveBluetoothExperimentOneSoftwareExportIntegrity.inspect(
            verified.softwareExportJSON
        )

        guard softwareReport.envelopeSHA256 == verified.softwareExportSHA256 else {
            throw PassiveBluetoothExperimentOneFinalShareIntegrityError
                .nestedSoftwareExportDigestMismatch
        }
        guard softwareReport.buildInstanceID == verified.buildInstanceID else {
            throw PassiveBluetoothExperimentOneFinalShareIntegrityError
                .nestedBuildInstanceMismatch
        }
        guard softwareReport.experimentRecipeID == verified.experimentRecipeID else {
            throw PassiveBluetoothExperimentOneFinalShareIntegrityError.nestedRecipeMismatch
        }

        return .init(
            finalShareSHA256: PassiveBluetoothFinalizedArtifactIntegrity.sha256Hex(of: data),
            finalShareByteCount: data.count,
            experimentID: verified.experimentID,
            experimentRecipeID: verified.experimentRecipeID,
            procedureVersion: verified.procedureVersion,
            buildInstanceID: verified.buildInstanceID,
            softwareExport: softwareReport
        )
    }
}
