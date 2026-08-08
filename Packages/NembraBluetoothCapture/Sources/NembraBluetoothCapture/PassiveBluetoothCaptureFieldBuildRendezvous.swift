import Foundation

/// Runtime-bound build rendezvous produced only after three independent software identities agree:
/// the exact field-build evidence bytes, the exact external build record, and the installed bundle
/// Nembra is actually running.
///
/// Possession of this value is still **not field acceptance or GO**. It proves only exact equality
/// across those software/build evidence sources. A later independently trusted acceptance layer must
/// verify the attested signed installable/evidence bytes before it can evolve the physical gate.
public struct PassiveBluetoothCaptureFieldBuildRendezvous: Equatable, Sendable {
    public let exactEvidenceRecordSHA256: String
    public let externalBuildRecordSHA256: String
    public let signedInstallableSHA256: String
    public let buildIdentifier: String
    public let buildInstanceID: String
    public let sourceCommitSHA: String
    public let executableSHA256: String
    public let infoPlistSHA256: String
    public let experimentRecipeID: PassiveBluetoothExperimentRecipeID
    public let procedureVersion: String

    fileprivate init(
        evidence: PassiveBluetoothCaptureFieldBuildEvidenceRecord
    ) {
        exactEvidenceRecordSHA256 = evidence.exactEvidenceRecordSHA256
        externalBuildRecordSHA256 = evidence.externalBuildRecordSHA256
        signedInstallableSHA256 = evidence.signedInstallableSHA256
        buildIdentifier = evidence.buildIdentifier
        buildInstanceID = evidence.buildInstanceID
        sourceCommitSHA = evidence.sourceCommitSHA
        executableSHA256 = evidence.executableSHA256
        infoPlistSHA256 = evidence.infoPlistSHA256
        experimentRecipeID = evidence.experimentRecipeID
        procedureVersion = evidence.procedureVersion
    }

    /// Existing exact build reference used for SoftwareExport comparison. This projection does not
    /// add trust; it only reuses the exact tuple already proven equal by this runtime rendezvous.
    public func makeSoftwareExportBuildReference() throws
        -> PassiveBluetoothExperimentOneSoftwareExportBuildReference
    {
        try .init(
            buildIdentifier: buildIdentifier,
            buildInstanceID: buildInstanceID,
            sourceCommitSHA: sourceCommitSHA,
            executableSHA256: executableSHA256
        )
    }
}

public enum PassiveBluetoothCaptureFieldBuildRendezvousError: Error, Equatable, Sendable {
    case externalBuildRecordMismatch
    case runningBuildMismatch
}

public extension PassiveBluetoothCaptureFieldBuildEvidenceRecord {
    /// Requires exact byte/build agreement with the external build record and exact identity of the
    /// installed bundle currently running. `PassiveBluetoothCaptureRuntimeBuildIdentity` cannot be
    /// caller-constructed by app code; production obtains it from `currentApplication()`.
    func makeRuntimeBoundRendezvous(
        matching externalRecord: PassiveBluetoothCaptureExternalBuildRecord,
        running runtimeIdentity: PassiveBluetoothCaptureRuntimeBuildIdentity
    ) throws -> PassiveBluetoothCaptureFieldBuildRendezvous {
        guard externalBuildRecordSHA256 == externalRecord.exactRecordSHA256,
              buildIdentifier == externalRecord.buildIdentifier,
              buildInstanceID == externalRecord.buildInstanceID,
              sourceCommitSHA == externalRecord.sourceCommitSHA,
              executableSHA256 == externalRecord.executableSHA256,
              infoPlistSHA256 == externalRecord.infoPlistSHA256,
              experimentRecipeID == externalRecord.experimentRecipeID,
              procedureVersion == externalRecord.procedureVersion else {
            throw PassiveBluetoothCaptureFieldBuildRendezvousError.externalBuildRecordMismatch
        }

        guard buildIdentifier == runtimeIdentity.buildIdentifier,
              buildInstanceID == runtimeIdentity.buildInstanceID,
              sourceCommitSHA == runtimeIdentity.sourceCommitSHA,
              executableSHA256 == runtimeIdentity.executableSHA256,
              infoPlistSHA256 == runtimeIdentity.infoPlistSHA256 else {
            throw PassiveBluetoothCaptureFieldBuildRendezvousError.runningBuildMismatch
        }

        return PassiveBluetoothCaptureFieldBuildRendezvous(evidence: self)
    }
}
