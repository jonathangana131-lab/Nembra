/// Package-owned field-execution lock for the first physical ES80 experiment.
///
/// The default V14 product state remains mechanically NO-GO. The zero-argument status and Boolean
/// intentionally cannot be changed by app preferences, launch markers, Info.plist values, typed
/// identifiers, or caller-supplied flags.
///
/// Public/release authorization remains the independent P-256 path: a verified signed envelope may
/// be converted into `VerifiedAdmission` only after the package trust root is configured.
///
/// TODAY's first private research artifact has a separate, deliberately narrower admission path.
/// `PrivateResearchAdmission` can be minted only from
/// `PassiveBluetoothCaptureVerifiedPrivateResearchAuthorization`, which is derived from the exact
/// running build identity and a recipe/source/build-instance marker embedded at build time. This
/// does not change the public `status` or `permitsPhysicalProcedure` values and is not a Settings or
/// imported-JSON escape hatch.
///
/// Both capabilities are build/procedure authority only. Neither authenticates an AOVOPRO ES80,
/// proves RF completeness, establishes GATT/Tuya/telemetry semantics, or authorizes a write.
public enum PassiveBluetoothExperimentOneFieldExecutionGate {
    public static let recipeID: PassiveBluetoothExperimentRecipeID = .es80FingerprintV1
    public static let status: Status = .noGo(.finalComposedBuildNotAuthorized)

    /// Public/release product state. Private research admission does not mutate this global value.
    public static var permitsPhysicalProcedure: Bool {
        switch status {
        case .noGo:
            return false
        }
    }

    /// Non-forgeable package capability derived only from a verified signed field authorization.
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

    /// Non-caller-constructible capability for the first private stationary read-only research run.
    ///
    /// Its initializer is private to this source file. App code can receive one only after the
    /// package verifies the exact running build's embedded private-research marker.
    public struct PrivateResearchAdmission: Equatable, Sendable {
        public let recipeID: PassiveBluetoothExperimentRecipeID
        public let buildIdentifier: String
        public let buildInstanceID: String
        public let sourceCommitSHA: String
        public let executableSHA256: String
        public let infoPlistSHA256: String

        fileprivate init(authorization: PassiveBluetoothCaptureVerifiedPrivateResearchAuthorization) {
            let identity = authorization.runtimeBuildIdentity
            recipeID = authorization.recipeID
            buildIdentifier = identity.buildIdentifier
            buildInstanceID = identity.buildInstanceID
            sourceCommitSHA = identity.sourceCommitSHA
            executableSHA256 = identity.executableSHA256
            infoPlistSHA256 = identity.infoPlistSHA256
        }
    }

    /// Convert only already-verified external authority into a package-owned release capability.
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

    /// Convert only the package-verified exact running private research build into an admission.
    ///
    /// Repeating recipe/build-identifier binding here keeps the coordinator seam fail-closed if the
    /// build-time reader is ever broadened. The production gate remains NO-GO throughout.
    public static func admit(
        privateResearchAuthorization authorization: PassiveBluetoothCaptureVerifiedPrivateResearchAuthorization
    ) -> PrivateResearchAdmission? {
        let identity = authorization.runtimeBuildIdentity
        let expectedBuildIdentifier = "Capture Build V14-\(identity.sourceCommitSHA.prefix(12))"

        guard authorization.recipeID == recipeID,
              identity.buildIdentifier == expectedBuildIdentifier else {
            return nil
        }

        return PrivateResearchAdmission(authorization: authorization)
    }

    public enum Status: Equatable, Sendable {
        case noGo(NoGoBlocker)
    }

    public enum NoGoBlocker: Equatable, Sendable {
        /// The final app-visible Capture composition has not yet earned the V14 public/release GO record.
        case finalComposedBuildNotAuthorized
    }
}
