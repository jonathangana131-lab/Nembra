/// Package-owned field-execution lock for the first physical ES80 experiment.
///
/// The default V14 product state remains mechanically NO-GO. The zero-argument status and Boolean
/// intentionally cannot be changed by app preferences, launch markers, Info.plist values, typed
/// identifiers, or caller-supplied flags.
///
/// A future accepted field build may present a `PassiveBluetoothCaptureVerifiedFieldAuthorization`
/// minted by the package's independent-signature verifier. `admit(verifiedAuthorization:)` turns
/// only that non-forgeable verifier output into a package-owned `VerifiedAdmission` capability.
/// The capability has no public initializer and is the only value a future live-controller factory
/// may accept. Production cannot mint one today because the package trust root is deliberately
/// unconfigured.
///
/// This is build/procedure authority only. Possession of a valid admission does not authenticate an
/// AOVOPRO ES80, prove RF completeness, establish GATT/Tuya/telemetry semantics, or turn a write
/// callback into physical acknowledgement.
public enum PassiveBluetoothExperimentOneFieldExecutionGate {
    public static let recipeID: PassiveBluetoothExperimentRecipeID = .es80FingerprintV1
    public static let status: Status = .noGo(.finalComposedBuildNotAuthorized)

    /// Current product state. This deliberately remains false until the app is explicitly wired to
    /// consume a separately verified field-authorization capability in a later accepted change.
    public static var permitsPhysicalProcedure: Bool {
        switch status {
        case .noGo:
            return false
        }
    }

    /// Non-forgeable package capability derived only from a verified signed field authorization.
    ///
    /// Its initializer is private to this source file. Public callers can obtain an instance only by
    /// first producing a `PassiveBluetoothCaptureVerifiedFieldAuthorization` through the package's
    /// public production verifier, which currently fails closed while the trust anchor is nil.
    public struct VerifiedAdmission: Equatable, Sendable {
        public let buildIdentifier: String
        public let buildInstanceID: String
        public let sourceCommitSHA: String
        public let signedInstallableSHA256: String
        public let fieldEvidenceRecordSHA256: String
        public let authorizationPayloadSHA256: String

        fileprivate init(authorization: PassiveBluetoothCaptureVerifiedFieldAuthorization) {
            let evidence = authorization.fieldBuildEvidenceRecord
            buildIdentifier = authorization.externalBuildRecord.buildIdentifier
            buildInstanceID = authorization.externalBuildRecord.buildInstanceID
            sourceCommitSHA = authorization.externalBuildRecord.sourceCommitSHA
            signedInstallableSHA256 = evidence.signedInstallableSHA256
            fieldEvidenceRecordSHA256 = evidence.exactEvidenceRecordSHA256
            authorizationPayloadSHA256 = authorization.authorizationPayloadSHA256
        }
    }

    /// Convert only already-verified external authority into a package-owned execution capability.
    ///
    /// The verifier currently enforces these relationships too; the gate repeats the final recipe,
    /// procedure and exact-rendezvous checks so a later verifier evolution cannot silently broaden
    /// physical execution policy.
    public static func admit(
        verifiedAuthorization authorization: PassiveBluetoothCaptureVerifiedFieldAuthorization
    ) -> VerifiedAdmission? {
        let record = authorization.externalBuildRecord
        let evidence = authorization.fieldBuildEvidenceRecord

        guard record.experimentRecipeID == recipeID,
              record.procedureVersion == PassiveBluetoothCaptureExternalBuildRecord.requiredProcedureVersion,
              evidence.experimentRecipeID == recipeID,
              evidence.procedureVersion == PassiveBluetoothCaptureExternalBuildRecord.requiredProcedureVersion,
              evidence.externalBuildRecordSHA256 == record.exactRecordSHA256,
              evidence.buildIdentifier == record.buildIdentifier,
              evidence.buildInstanceID == record.buildInstanceID,
              evidence.sourceCommitSHA == record.sourceCommitSHA,
              evidence.executableSHA256 == record.executableSHA256,
              evidence.infoPlistSHA256 == record.infoPlistSHA256,
              evidence.signedInstallableKind == PassiveBluetoothCaptureFieldBuildEvidenceRecord.requiredInstallableKind else {
            return nil
        }

        return VerifiedAdmission(authorization: authorization)
    }

    public enum Status: Equatable, Sendable {
        case noGo(NoGoBlocker)
    }

    public enum NoGoBlocker: Equatable, Sendable {
        /// The final app-visible Capture composition has not yet earned the V14 physical GO record.
        case finalComposedBuildNotAuthorized
    }
}
