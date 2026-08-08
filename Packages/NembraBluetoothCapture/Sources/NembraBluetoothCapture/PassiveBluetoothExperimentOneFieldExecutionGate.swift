import Foundation

/// Package-owned field-execution lock for the first physical ES80 experiment.
///
/// The default V14 product state remains mechanically NO-GO. The zero-argument `status` is the
/// release/public-authorization status and intentionally cannot be changed by app preferences,
/// launch arguments, environment variables, imported JSON, typed identifiers, or caller flags.
///
/// TODAY's private stationary research build has one narrower exception: the package may admit the
/// exact build metadata stamped into the signed app by the canonical field-candidate producer. The
/// admission is derived directly from `Bundle.main` inside this package; app/UI code cannot submit an
/// arbitrary dictionary to the production path. Missing, malformed, or non-canonical metadata fails
/// closed. This is deliberately not the future public-release authorization model.
///
/// A future release field build may instead present a
/// `PassiveBluetoothCaptureVerifiedFieldAuthorization` minted by the package's independent-signature
/// verifier. `admit(verifiedAuthorization:)` turns only that verifier output into `VerifiedAdmission`.
/// Production cannot mint that release capability today because the package trust root remains
/// deliberately unconfigured.
///
/// This is build/procedure authority only. Possession of either capability does not authenticate an
/// AOVOPRO ES80, prove RF completeness, establish GATT/Tuya/telemetry semantics, or turn a write
/// callback into physical acknowledgement.
public enum PassiveBluetoothExperimentOneFieldExecutionGate {
    public static let recipeID: PassiveBluetoothExperimentRecipeID = .es80FingerprintV1
    public static let status: Status = .noGo(.finalComposedBuildNotAuthorized)

    static let fieldRecipeInfoDictionaryKey = "NembraCaptureFieldRecipe"

    /// The current executable may proceed only when it is the mechanically identifiable research
    /// field build produced with exact canonical metadata. Ordinary builds and all test hosts remain
    /// false. The public release status above deliberately remains NO-GO until independent signed
    /// authorization is accepted in a later closure rung.
    public static var permitsPhysicalProcedure: Bool {
        currentResearchBuildAdmission() != nil
    }

    /// Narrow package-only capability for TODAY's exact-source signed research build.
    /// There is no public initializer and no production API accepting caller-supplied metadata.
    struct ResearchBuildAdmission: Equatable, Sendable {
        let buildIdentifier: String
        let buildInstanceID: String
        let sourceCommitSHA: String

        fileprivate init(
            buildIdentifier: String,
            buildInstanceID: String,
            sourceCommitSHA: String
        ) {
            self.buildIdentifier = buildIdentifier
            self.buildInstanceID = buildInstanceID
            self.sourceCommitSHA = sourceCommitSHA
        }
    }

    static func currentResearchBuildAdmission() -> ResearchBuildAdmission? {
        researchBuildAdmission(infoDictionary: Bundle.main.infoDictionary ?? [:])
    }

    /// Deterministic package seam for validation. The running-app path above always supplies
    /// `Bundle.main`; normal app code cannot call this package-internal resolver with imported JSON.
    package static func researchBuildAdmission(
        infoDictionary: [String: Any]
    ) -> ResearchBuildAdmission? {
        guard let recipe = infoDictionary[fieldRecipeInfoDictionaryKey] as? String,
              recipe == recipeID.rawValue,
              let buildIdentifier = infoDictionary[
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildIdentifierInfoDictionaryKey
              ] as? String,
              let rawBuildInstanceID = infoDictionary[
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildInstanceIDInfoDictionaryKey
              ] as? String,
              let rawSourceCommitSHA = infoDictionary[
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.sourceCommitSHAInfoDictionaryKey
              ] as? String,
              let buildInstanceID = PassiveBluetoothCaptureRuntimeBuildIdentityReader
                .normalizedBuildInstanceID(rawBuildInstanceID),
              buildInstanceID == rawBuildInstanceID,
              let sourceCommitSHA = PassiveBluetoothCaptureRuntimeBuildIdentityReader
                .normalizedFullGitCommitSHA(rawSourceCommitSHA),
              sourceCommitSHA == rawSourceCommitSHA,
              buildIdentifier == "Capture Build V14-\(sourceCommitSHA.prefix(12))" else {
            return nil
        }

        return ResearchBuildAdmission(
            buildIdentifier: buildIdentifier,
            buildInstanceID: buildInstanceID,
            sourceCommitSHA: sourceCommitSHA
        )
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
        /// The public/release authorization model has not yet earned the V14 physical GO record.
        case finalComposedBuildNotAuthorized
    }
}
