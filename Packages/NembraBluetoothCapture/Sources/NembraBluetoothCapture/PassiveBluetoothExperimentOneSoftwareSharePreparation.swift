import Foundation

/// One package-owned Share payload prepared from a finalized Experiment One evidence life.
///
/// The encoded bytes are a self-consistency-checked `PassiveBluetoothExperimentOneSoftwareExport`,
/// not raw controller capture JSON. They remain software evidence only: an independently accepted
/// external field-build / GO record is still required before a physical experiment may be authorized.
public struct PassiveBluetoothExperimentOnePreparedSoftwareShare: Equatable, Sendable {
    /// Exact bytes that product UI may stage into a temporary Share file.
    public let softwareExportJSON: Data
    /// Byte count of the immutable controller capture nested inside the software export.
    public let captureByteCount: Int
    /// Stable package-owned procedure identity carried by the export.
    public let experimentRecipeID: PassiveBluetoothExperimentRecipeID
    /// Human-readable produced-build declaration carried by the runtime identity.
    public let buildIdentifier: String
    /// Opaque produced-build rendezvous identifier. This is correlation evidence, never GO authority.
    public let buildInstanceID: String
    /// Exact source commit declaration carried by the running build.
    public let sourceCommitSHA: String
    /// SHA-256 of the runtime executable bytes measured by the running application.
    /// This value is software evidence and is not independently trusted merely because it appears here.
    public let executableSHA256: String

    fileprivate init(
        softwareExportJSON: Data,
        captureByteCount: Int,
        experimentRecipeID: PassiveBluetoothExperimentRecipeID,
        buildIdentifier: String,
        buildInstanceID: String,
        sourceCommitSHA: String,
        executableSHA256: String
    ) {
        self.softwareExportJSON = softwareExportJSON
        self.captureByteCount = captureByteCount
        self.experimentRecipeID = experimentRecipeID
        self.buildIdentifier = buildIdentifier
        self.buildInstanceID = buildInstanceID
        self.sourceCommitSHA = sourceCommitSHA
        self.executableSHA256 = executableSHA256
    }
}

public enum PassiveBluetoothExperimentOneSoftwareSharePreparationError: Error, Equatable, Sendable {
    case roundTripVerificationMismatch
}

/// Product-facing preparation boundary for Experiment One Share.
///
/// Public app callers provide only the package-finalized evidence life plus the operator-declared
/// stationary setup. Target identity, recipe identity, and runtime build provenance are derived by
/// package-owned producers. The final encoded bytes are round-trip self-consistency checked before
/// they are returned to the app for file staging; that check is not external build attestation.
public enum PassiveBluetoothExperimentOneSoftwareSharePreparation {
    @MainActor
    public static func prepare(
        finalizedArtifact: PassiveBluetoothExperimentOneCoordinator.FinalizedArtifact,
        setup: PassiveBluetoothStationaryCaptureSetup,
        prettyPrinted: Bool = true
    ) throws -> PassiveBluetoothExperimentOnePreparedSoftwareShare {
        let softwareExport = try PassiveBluetoothExperimentOneSoftwareExportCodec.makeForCurrentApplication(
            finalizedArtifact: finalizedArtifact,
            setup: setup
        )
        return try prepareVerified(softwareExport, prettyPrinted: prettyPrinted)
    }

    /// Deterministic package-test seam. Production app/UI targets cannot inject raw correlation or
    /// build identity through the public Share-preparation API.
    package static func prepare(
        captureJSON: Data,
        powerCycleResult: PassiveBluetoothPowerCycleObservationResult,
        runtimeBuildIdentity: PassiveBluetoothCaptureRuntimeBuildIdentity,
        setup: PassiveBluetoothStationaryCaptureSetup,
        prettyPrinted: Bool = true
    ) throws -> PassiveBluetoothExperimentOnePreparedSoftwareShare {
        let softwareExport = try PassiveBluetoothExperimentOneSoftwareExportCodec.make(
            captureJSON: captureJSON,
            powerCycleResult: powerCycleResult,
            runtimeBuildIdentity: runtimeBuildIdentity,
            setup: setup
        )
        return try prepareVerified(softwareExport, prettyPrinted: prettyPrinted)
    }

    private static func prepareVerified(
        _ softwareExport: PassiveBluetoothExperimentOneSoftwareExport,
        prettyPrinted: Bool
    ) throws -> PassiveBluetoothExperimentOnePreparedSoftwareShare {
        let encoded = try PassiveBluetoothExperimentOneSoftwareExportCodec.encode(
            softwareExport,
            prettyPrinted: prettyPrinted
        )
        let verified = try PassiveBluetoothExperimentOneSoftwareExportCodec.decodeAndVerify(encoded)
        guard verified == softwareExport else {
            throw PassiveBluetoothExperimentOneSoftwareSharePreparationError.roundTripVerificationMismatch
        }

        return .init(
            softwareExportJSON: encoded,
            captureByteCount: verified.captureJSON.count,
            experimentRecipeID: verified.experimentRecipeID,
            buildIdentifier: verified.build.buildIdentifier,
            buildInstanceID: verified.build.buildInstanceID,
            sourceCommitSHA: verified.build.sourceCommitSHA,
            executableSHA256: verified.build.executableSHA256
        )
    }
}
