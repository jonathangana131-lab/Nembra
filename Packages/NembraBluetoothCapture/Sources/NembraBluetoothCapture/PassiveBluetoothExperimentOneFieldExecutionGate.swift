import Foundation

/// Package-owned field-execution lock for the first physical ES80 experiment.
///
/// Ordinary/debug/release product builds remain mechanically NO-GO. The temporary TODAY research
/// path is deliberately narrower than the future release-grade P-256 authorization path: only the
/// exact signed field-candidate build shape produced by Nembra's accepted build pipeline may become
/// a `.researchBuildAuthorized` runtime status. A normal Settings preference, launch argument,
/// environment variable, or imported unsigned JSON cannot mint this status.
///
/// The current research admission is intentionally tied to Bundle.main build metadata plus hashes of
/// the exact running executable and raw Info.plist. It is suitable only for the private stationary,
/// charger-disconnected, read-only `ES80-FINGERPRINT-v1` data-unlock procedure described by
/// CAPTURE_TODAY_FIELD_READY_DIRECTIVE.md. It is not public-release authorization and must be removed
/// or subordinated to the external verifier after the first physical artifact is retained.
///
/// Separately, a future release build may present a `PassiveBluetoothCaptureVerifiedFieldAuthorization`
/// minted by the package's independent-signature verifier. `admit(verifiedAuthorization:)` turns only
/// that non-forgeable verifier output into a package-owned `VerifiedAdmission` capability.
///
/// This is build/procedure authority only. Possession of any admission does not authenticate an
/// AOVOPRO ES80, prove RF completeness, establish GATT/Tuya/telemetry semantics, or turn a write
/// callback into physical acknowledgement.
public enum PassiveBluetoothExperimentOneFieldExecutionGate {
    public static let recipeID: PassiveBluetoothExperimentRecipeID = .es80FingerprintV1
    public static let researchFieldRecipeInfoDictionaryKey = "NembraCaptureFieldRecipe"
    private static let acceptedResearchBuildIdentifierPrefix = "Capture Build V14-"

    /// Runtime field status for the exact application that is currently executing.
    ///
    /// Unit-test hosts and ordinary app builds do not carry the complete signed field-candidate
    /// metadata shape, so they remain NO-GO. The status is intentionally recomputed rather than
    /// cached so tests and future relaunch/recovery behavior cannot preserve stale authority.
    public static var status: Status {
        guard let researchAuthorization = currentResearchFieldAuthorization() else {
            return .noGo(.finalComposedBuildNotAuthorized)
        }
        return .researchBuildAuthorized(researchAuthorization)
    }

    public static var permitsPhysicalProcedure: Bool {
        switch status {
        case .noGo:
            return false
        case .researchBuildAuthorized:
            return true
        }
    }

    /// Exact runtime identity admitted for the temporary private research-build path.
    public struct ResearchFieldAuthorization: Equatable, Sendable {
        public let buildIdentifier: String
        public let buildInstanceID: String
        public let sourceCommitSHA: String
        public let executableSHA256: String
        public let infoPlistSHA256: String
        public let experimentRecipeID: PassiveBluetoothExperimentRecipeID

        fileprivate init(
            identity: PassiveBluetoothCaptureRuntimeBuildIdentity,
            experimentRecipeID: PassiveBluetoothExperimentRecipeID
        ) {
            buildIdentifier = identity.buildIdentifier
            buildInstanceID = identity.buildInstanceID
            sourceCommitSHA = identity.sourceCommitSHA
            executableSHA256 = identity.executableSHA256
            infoPlistSHA256 = identity.infoPlistSHA256
            self.experimentRecipeID = experimentRecipeID
        }
    }

    /// Non-forgeable package capability derived only from a verified signed field authorization.
    ///
    /// Its initializer is private to this source file. Public callers can obtain an instance only by
    /// first producing a `PassiveBluetoothCaptureVerifiedFieldAuthorization` through the package's
    /// public production verifier. This remains the release-grade direction after the TODAY research
    /// build unlock is retired.
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

    /// Pure resolver used by the runtime producer and package tests.
    ///
    /// The recipe marker alone is never enough. The build must also expose the complete validated
    /// runtime identity and use the exact signed-field producer naming convention that mechanically
    /// binds the human-readable build identifier to the embedded full source commit.
    package static func resolveResearchFieldAuthorization(
        infoDictionary: [String: Any],
        runtimeBuildIdentity: PassiveBluetoothCaptureRuntimeBuildIdentity?
    ) -> ResearchFieldAuthorization? {
        guard let runtimeBuildIdentity else { return nil }
        guard let recipe = infoDictionary[researchFieldRecipeInfoDictionaryKey] as? String,
              recipe == recipeID.rawValue else {
            return nil
        }

        let expectedBuildIdentifier = acceptedResearchBuildIdentifierPrefix
            + String(runtimeBuildIdentity.sourceCommitSHA.prefix(12))
        guard runtimeBuildIdentity.buildIdentifier == expectedBuildIdentifier else {
            return nil
        }

        return ResearchFieldAuthorization(
            identity: runtimeBuildIdentity,
            experimentRecipeID: recipeID
        )
    }

    public enum Status: Equatable, Sendable {
        case noGo(NoGoBlocker)
        case researchBuildAuthorized(ResearchFieldAuthorization)
    }

    public enum NoGoBlocker: Equatable, Sendable {
        /// The final app-visible Capture composition has not yet earned the V14 physical GO record.
        case finalComposedBuildNotAuthorized
    }

    private static func currentResearchFieldAuthorization() -> ResearchFieldAuthorization? {
        let infoDictionary = Bundle.main.infoDictionary ?? [:]
        guard let runtimeBuildIdentity = try? PassiveBluetoothCaptureRuntimeBuildIdentityReader.currentApplication() else {
            return nil
        }
        return resolveResearchFieldAuthorization(
            infoDictionary: infoDictionary,
            runtimeBuildIdentity: runtimeBuildIdentity
        )
    }
}
