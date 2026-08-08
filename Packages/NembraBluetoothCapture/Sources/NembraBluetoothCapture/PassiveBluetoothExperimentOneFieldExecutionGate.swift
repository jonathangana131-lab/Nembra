import Foundation

/// Package-owned field-execution lock for the first physical ES80 experiment.
///
/// Release-grade authorization remains fail-closed behind the independent-signature verifier below.
/// For the private first Capture only, the TODAY field-ready directive also permits a deliberately
/// produced signed developer/research build to carry one build-time authorization marker. That marker
/// is accepted only when it names the compiled passive recipe and rendezvous-binds the exact source
/// commit plus per-build instance ID measured from the running signed application.
///
/// No Settings preference, launch argument, environment variable, typed identifier, or imported JSON
/// can mint the research admission. Removing or changing the signed Info.plist marker after production
/// changes the signed application subject; the runtime build identity also hashes the executable and
/// raw Info.plist bytes for downstream artifact provenance.
///
/// This is build/procedure authority only. Possession of any admission does not authenticate an
/// AOVOPRO ES80, prove RF completeness, establish GATT/Tuya/telemetry semantics, or turn a write
/// callback into physical acknowledgement.
public enum PassiveBluetoothExperimentOneFieldExecutionGate {
    public static let recipeID: PassiveBluetoothExperimentRecipeID = .es80FingerprintV1

    /// Release/public field authority remains deliberately NO-GO until the independent trust-root
    /// path is explicitly accepted. Private research admission is a separate, narrower TODAY path.
    public static let status: Status = .noGo(.finalComposedBuildNotAuthorized)

    public static let researchAuthorizationInfoDictionaryKey = "NembraCaptureResearchFieldAuthorization"
    public static let researchAuthorizationVersion = "v1"

    /// True only for the running application when its signed build metadata carries the exact
    /// research rendezvous marker for this compiled recipe/source/build instance.
    public static var permitsPhysicalProcedure: Bool {
        currentResearchAdmission() != nil
    }

    /// Non-forgeable package capability derived only from a verified signed release authorization.
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

    /// Package-internal capability for the narrow private TODAY research path. There is deliberately
    /// no public initializer or public admission API; live coordinator construction asks the package
    /// to resolve this from `Bundle.main` itself.
    struct ResearchAdmission: Equatable, Sendable {
        let experimentRecipeID: PassiveBluetoothExperimentRecipeID
        let buildIdentifier: String
        let buildInstanceID: String
        let sourceCommitSHA: String

        fileprivate init(runtimeBuildIdentity: PassiveBluetoothCaptureRuntimeBuildIdentity) {
            experimentRecipeID = PassiveBluetoothExperimentOneFieldExecutionGate.recipeID
            buildIdentifier = runtimeBuildIdentity.buildIdentifier
            buildInstanceID = runtimeBuildIdentity.buildInstanceID
            sourceCommitSHA = runtimeBuildIdentity.sourceCommitSHA
        }
    }

    /// Convert only already-verified external authority into a package-owned release execution
    /// capability. The release verifier remains intentionally separate from private research mode.
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

    /// Deterministic package seam used by tests and by `currentResearchAdmission()`. Admission is
    /// exact-string, fail-closed, and bound to the validated runtime source/build rendezvous.
    static func researchAdmission(
        infoDictionary: [String: Any],
        runtimeBuildIdentity: PassiveBluetoothCaptureRuntimeBuildIdentity
    ) -> ResearchAdmission? {
        guard let recipeMarker = infoDictionary["NembraCaptureFieldRecipe"] as? String,
              recipeMarker == recipeID.rawValue else {
            return nil
        }

        let expectedBuildIdentifier = "Capture Build V14-\(runtimeBuildIdentity.sourceCommitSHA.prefix(12))"
        guard runtimeBuildIdentity.buildIdentifier == expectedBuildIdentifier else {
            return nil
        }

        let expectedAuthorization = researchAuthorizationMarker(
            sourceCommitSHA: runtimeBuildIdentity.sourceCommitSHA,
            buildInstanceID: runtimeBuildIdentity.buildInstanceID
        )
        guard let authorization = infoDictionary[researchAuthorizationInfoDictionaryKey] as? String,
              authorization == expectedAuthorization else {
            return nil
        }

        return ResearchAdmission(runtimeBuildIdentity: runtimeBuildIdentity)
    }

    /// Production-only authority resolution. Build metadata comes from the running signed app and
    /// the runtime identity reader independently hashes its executable and raw Info.plist.
    static func currentResearchAdmission() -> ResearchAdmission? {
        guard let runtimeBuildIdentity = try? PassiveBluetoothCaptureRuntimeBuildIdentityReader
            .currentApplication() else {
            return nil
        }
        return researchAdmission(
            infoDictionary: Bundle.main.infoDictionary ?? [:],
            runtimeBuildIdentity: runtimeBuildIdentity
        )
    }

    static func researchAuthorizationMarker(
        sourceCommitSHA: String,
        buildInstanceID: String
    ) -> String {
        "\(researchAuthorizationVersion):\(recipeID.rawValue):\(sourceCommitSHA):\(buildInstanceID)"
    }

    public enum Status: Equatable, Sendable {
        case noGo(NoGoBlocker)
    }

    public enum NoGoBlocker: Equatable, Sendable {
        /// Release/public authorization is not configured. This does not describe the narrower
        /// exact-build private research admission permitted by the TODAY field-ready directive.
        case finalComposedBuildNotAuthorized
    }
}
