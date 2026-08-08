import Foundation

/// Package-owned field-execution lock for the first physical ES80 experiment.
///
/// The production/release V14 policy remains mechanically NO-GO until the independently signed
/// `VerifiedAdmission` path is deliberately promoted. For the first private stationary artifact,
/// the active TODAY field-ready directive permits a narrower research-only route: an iOS Release
/// build produced with Nembra's dedicated signed-field metadata may unlock Experiment One when its
/// signed bundle carries the exact `ES80-FINGERPRINT-v1` recipe plus canonical source/build-instance
/// identity. Debug, Simulator, Settings, launch arguments, environment variables, and imported JSON
/// cannot mint that research admission.
///
/// The private research route is intentionally not the public-release trust model. It preserves the
/// stronger P-256 `VerifiedAdmission` path below rather than weakening or replacing it. The dedicated
/// signed-field producer already stamps the recipe, `Capture Build V14-<source-prefix>` identifier,
/// canonical source SHA, and per-build UUID into the signed app Info.plist; this gate requires that
/// exact build-time tuple and derives no authority from rider/operator input.
///
/// This is build/procedure authority only. Possession of either admission does not authenticate an
/// AOVOPRO ES80, prove RF completeness, establish GATT/Tuya/telemetry semantics, or turn a write
/// callback into physical acknowledgement.
public enum PassiveBluetoothExperimentOneFieldExecutionGate {
    public static let recipeID: PassiveBluetoothExperimentRecipeID = .es80FingerprintV1
    public static let status: Status = .noGo(.finalComposedBuildNotAuthorized)

    package static let researchFieldRecipeInfoDictionaryKey = "NembraCaptureFieldRecipe"
    package static let researchBuildIdentifierPrefix = "Capture Build V14-"

    /// Product-facing execution decision for the running app.
    ///
    /// Production authority still evaluates independently through `productionPermitsPhysicalProcedure`.
    /// The only additional TODAY route is the package-derived research admission from the signed
    /// running bundle on a real iOS Release build.
    public static var permitsPhysicalProcedure: Bool {
        currentResearchBuildAdmission != nil || productionPermitsPhysicalProcedure
    }

    /// Public-release policy remains NO-GO. A future accepted release transition can evolve the
    /// status vocabulary without coupling that work to the private first-artifact exception.
    public static var productionPermitsPhysicalProcedure: Bool {
        switch status {
        case .noGo:
            return false
        }
    }

    /// Package-only capability for the deliberately produced private research build.
    ///
    /// External app code cannot construct or receive this value. The canonical coordinator factory
    /// asks this gate to derive it directly from the running signed bundle.
    package struct ResearchBuildAdmission: Equatable, Sendable {
        package let buildIdentifier: String
        package let buildInstanceID: String
        package let sourceCommitSHA: String
        package let experimentRecipeID: PassiveBluetoothExperimentRecipeID

        fileprivate init(
            buildIdentifier: String,
            buildInstanceID: String,
            sourceCommitSHA: String,
            experimentRecipeID: PassiveBluetoothExperimentRecipeID
        ) {
            self.buildIdentifier = buildIdentifier
            self.buildInstanceID = buildInstanceID
            self.sourceCommitSHA = sourceCommitSHA
            self.experimentRecipeID = experimentRecipeID
        }
    }

    /// Derive the private research capability only from the running application's signed bundle.
    ///
    /// Debug and Simulator builds remain mechanically locked even if a developer manually injects
    /// matching metadata. The dedicated field producer archives Release for a physical iOS device.
    package static var currentResearchBuildAdmission: ResearchBuildAdmission? {
#if os(iOS) && !targetEnvironment(simulator) && !DEBUG
        return researchBuildAdmission(infoDictionary: Bundle.main.infoDictionary ?? [:])
#else
        return nil
#endif
    }

    /// Deterministic package seam used by tests to prove the exact build-time tuple.
    /// Production callers never supply this dictionary; `currentResearchBuildAdmission` owns the
    /// only live path and reads `Bundle.main` directly.
    package static func researchBuildAdmission(
        infoDictionary: [String: Any]
    ) -> ResearchBuildAdmission? {
        guard let rawRecipe = infoDictionary[researchFieldRecipeInfoDictionaryKey] as? String,
              rawRecipe == recipeID.rawValue,
              let rawBuildIdentifier = infoDictionary[
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
              let sourceCommitSHA = PassiveBluetoothCaptureRuntimeBuildIdentityReader
                .normalizedFullGitCommitSHA(rawSourceCommitSHA) else {
            return nil
        }

        let expectedBuildIdentifier = researchBuildIdentifierPrefix
            + String(sourceCommitSHA.prefix(12))
        guard rawBuildIdentifier == expectedBuildIdentifier else {
            return nil
        }

        return ResearchBuildAdmission(
            buildIdentifier: rawBuildIdentifier,
            buildInstanceID: buildInstanceID,
            sourceCommitSHA: sourceCommitSHA,
            experimentRecipeID: recipeID
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
        /// The final app-visible Capture composition has not yet earned the public/release GO record.
        case finalComposedBuildNotAuthorized
    }
}
