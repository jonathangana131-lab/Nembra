import CryptoKit
import Foundation
import NembraCore

/// Durable wrapper that binds a deterministic framing-candidate report to the
/// exact package-owned final Share bytes and their already-verified nested
/// SoftwareExport + immutable capture subjects.
///
/// These hashes are software integrity/provenance identifiers only. They do not
/// authenticate the physical scooter, prove RF completeness, or verify any ES80
/// protocol/telemetry meaning.
public struct PassiveBluetoothTuyaCaptureArtifactReport: Equatable, Codable, Sendable {
    public static let currentSchemaVersion = 2

    public let schemaVersion: Int
    public let sourceArtifact: SourceArtifactSummary
    public let analysis: PassiveBluetoothTuyaCaptureReport

    public struct SourceArtifactSummary: Equatable, Codable, Sendable {
        public let finalShareSHA256: String
        public let finalShareByteCount: Int
        public let softwareExportSHA256: String
        public let captureSHA256: String
        public let captureByteCount: Int
        public let experimentID: UUID
        public let experimentRecipeID: String
        public let procedureVersion: String
        public let buildInstanceID: String
        public let sourceCommitSHA: String
    }

    public func jsonData(prettyPrinted: Bool = true) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = prettyPrinted ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return try encoder.encode(self)
    }
}

public enum PassiveBluetoothTuyaCaptureArtifactReportBuilder {
    /// Verifies and analyzes the exact final Share file emitted by Nembra Capture.
    ///
    /// The package-owned final-share integrity verifier is the admission authority:
    /// it validates the outer closed-world Share, exact nested SoftwareExport,
    /// immutable Capture readability, and procedure/build/recipe rendezvous. The
    /// stationary manifest then supplies the already-verified selected peripheral.
    /// The operator is never asked to extract nested JSON or type a UUID.
    ///
    /// `maximumArtifactBytes` is an offline process-safety ceiling only. It is not
    /// a physical ES80 packet/session/capture maximum. File callers should first
    /// use `PassiveBluetoothCaptureArtifactInputPolicy.readExactBytes` so the
    /// source Data is bounded before whole-file materialization or JSON decode.
    public static func make(
        finalShareJSON: Data,
        policy: TuyaCandidateFragmentReassemblyPolicy,
        maximumArtifactBytes: Int = PassiveBluetoothCaptureArtifactInputPolicy.defaultMaximumArtifactBytes
    ) throws -> PassiveBluetoothTuyaCaptureArtifactReport {
        try PassiveBluetoothCaptureArtifactInputPolicy.validateByteCount(
            finalShareJSON.count,
            maximumBytes: maximumArtifactBytes
        )

        // Possession of this package-owned report is the mechanical proof that the
        // exact bytes are analysis-ready under current final-Share semantics. Do
        // not replace this with caller-selected JSON fields or codec decode alone.
        let integrity = try PassiveBluetoothExperimentOneFinalShareIntegrity.inspect(finalShareJSON)
        let verifiedFinalShare = try PassiveBluetoothExperimentOneFinalShareArtifactCodec
            .decodeAndVerify(finalShareJSON)
        let softwareExport = verifiedFinalShare.softwareExport
        let captureJSON = softwareExport.captureJSON
        let manifest = try PassiveBluetoothStationaryCaptureManifestJSON.verifyCaptureBinding(
            manifestJSON: softwareExport.stationaryManifestJSON,
            captureJSON: captureJSON
        )

        let selectedPeripheralIdentifier = manifest.sourceArtifact.selectedPeripheralIdentifier
        let analysis = try PassiveBluetoothTuyaCaptureReportBuilder.make(
            session: PassiveBluetoothCaptureJSON.decode(captureJSON),
            peripheralIdentifier: selectedPeripheralIdentifier,
            policy: policy
        )

        return PassiveBluetoothTuyaCaptureArtifactReport(
            schemaVersion: PassiveBluetoothTuyaCaptureArtifactReport.currentSchemaVersion,
            sourceArtifact: .init(
                finalShareSHA256: integrity.finalShareSHA256,
                finalShareByteCount: integrity.finalShareByteCount,
                softwareExportSHA256: integrity.softwareExport.envelopeSHA256,
                captureSHA256: manifest.sourceArtifact.sha256,
                captureByteCount: manifest.sourceArtifact.byteCount,
                experimentID: integrity.experimentID,
                experimentRecipeID: integrity.experimentRecipeID.rawValue,
                procedureVersion: integrity.procedureVersion,
                buildInstanceID: integrity.buildInstanceID,
                sourceCommitSHA: softwareExport.build.sourceCommitSHA
            ),
            analysis: analysis
        )
    }

    public static func sha256Hex(of data: Data) -> String {
        SHA256.hash(data: data).map { byte in
            String(format: "%02x", byte)
        }.joined()
    }
}
