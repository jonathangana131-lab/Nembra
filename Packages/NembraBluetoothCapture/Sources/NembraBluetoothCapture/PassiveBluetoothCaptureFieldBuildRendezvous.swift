import Foundation

/// Runtime-bound build rendezvous produced only after three independent software identities agree:
/// the exact signed-field companion evidence bytes, the exact schema-v3 external build record, and
/// the executable plus raw Info.plist bytes that Nembra is actually running.
///
/// Possession of this value is still **not field acceptance or GO**. It proves only exact equality
/// across those software/build evidence sources. A later independently trusted acceptance layer must
/// verify/attest the exact retained IPA plus evidence subjects before it can evolve the physical gate.
public struct PassiveBluetoothCaptureFieldBuildRendezvous: Equatable, Sendable {
    public let exactEvidenceRecordSHA256: String
    public let externalBuildRecordSHA256: String
    public let ipaSHA256: String
    public let ipaByteCount: Int
    public let buildIdentifier: String
    public let buildInstanceID: String
    public let sourceCommitSHA: String
    public let executableSHA256: String
    public let infoPlistSHA256: String
    public let teamIdentifier: String
    public let experimentRecipeID: PassiveBluetoothExperimentRecipeID
    public let procedureVersion: String

    fileprivate init(
        evidence: PassiveBluetoothCaptureFieldBuildEvidenceRecord
    ) {
        exactEvidenceRecordSHA256 = evidence.exactEvidenceRecordSHA256
        externalBuildRecordSHA256 = evidence.externalBuildRecordSHA256
        ipaSHA256 = evidence.ipaSHA256
        ipaByteCount = evidence.ipaByteCount
        buildIdentifier = evidence.buildIdentifier
        buildInstanceID = evidence.buildInstanceID
        sourceCommitSHA = evidence.sourceCommitSHA
        executableSHA256 = evidence.executableSHA256
        infoPlistSHA256 = evidence.infoPlistSHA256
        teamIdentifier = evidence.teamIdentifier
        experimentRecipeID = evidence.experimentRecipeID
        procedureVersion = evidence.procedureVersion
    }

    /// Existing exact build reference used for SoftwareExport comparison. This projection does not
    /// add trust; it only reuses the tuple already proven equal by this runtime rendezvous. The
    /// rendezvous itself must remain available to future field acceptance because the older
    /// SoftwareExport reference does not carry Info.plist or retained-IPA identity.
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
    /// executable and raw Info.plist currently running. `PassiveBluetoothCaptureRuntimeBuildIdentity`
    /// cannot be caller-constructed by app code; production obtains it from `currentApplication()`.
    func makeRuntimeBoundRendezvous(
        matching externalRecord: PassiveBluetoothCaptureExternalBuildRecord,
        running runtimeIdentity: PassiveBluetoothCaptureRuntimeBuildIdentity
    ) throws -> PassiveBluetoothCaptureFieldBuildRendezvous {
        do {
            _ = try makeSoftwareExportBuildReference(matching: externalRecord)
        } catch {
            throw PassiveBluetoothCaptureFieldBuildRendezvousError.externalBuildRecordMismatch
        }

        do {
            try externalRecord.validateRuntimeBinding(to: runtimeIdentity)
        } catch {
            throw PassiveBluetoothCaptureFieldBuildRendezvousError.runningBuildMismatch
        }

        return PassiveBluetoothCaptureFieldBuildRendezvous(evidence: self)
    }
}
