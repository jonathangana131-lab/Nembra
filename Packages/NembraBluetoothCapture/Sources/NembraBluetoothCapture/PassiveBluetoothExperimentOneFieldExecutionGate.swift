import Foundation

/// Package-owned field-execution lock for the first physical ES80 experiment.
///
/// Release-grade authorization remains fail-closed behind the independent-signature verifier below.
/// For the private first Capture only, the TODAY field-ready directive also permits the canonical
/// signed developer/research producer's existing build-time recipe marker to become a narrow research
/// admission when it matches the package's compiled passive recipe and the running app's validated
/// exact-source build identity.
///
/// No Settings preference, launch argument, environment variable, typed identifier, or imported JSON
/// can mint this admission. The marker is part of the signed app Info.plist, while source commit,
/// build-instance ID, executable bytes, and raw Info.plist bytes are read/measured from the running
/// application by `PassiveBluetoothCaptureRuntimeBuildIdentityReader`.
///
/// This is build/procedure authority only. Possession of any admission does not authenticate an
/// AOVOPRO ES80, prove RF completeness, establish GATT/Tuya/telemetry semantics, or turn a write
/// callback into physical acknowledgement.
public enum PassiveBluetoothExperimentOneFieldExecutionGate {
    public static let recipeID: PassiveBluetoothExperimentRecipeID = .es80FingerprintV1
    public static let researchRecipeInfoDictionaryKey = "NembraCaptureFieldRecipe"

    /// Release/public field authority remains deliberately NO-GO until the independent trust-root
    /// path is explicitly accepted. Private research admission is a separate, narrower TODAY path.
    public static let status: Status = .noGo(.finalComposedBuildNotAuthorized)

    /// True only for the running application when its signed field-recipe declaration and exact
    /// runtime build identity match the canonical private research-build contract.
    public static var permitsPhysicalProcedure: Bool {
        currentResearchAdmission() != nil
    }

    /// Non-forgeable package capability derived only from a verified signed release authorization.
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

    /// Deterministic package seam used by tests and by `currentResearchAdmission()`. The canonical
    /// signed field producer already stamps all of these values at archive time; ordinary application
    /// state cannot synthesize them after signing.
    static func researchAdmission(
        infoDictionary: [String: Any],
        runtimeBuildIdentity: PassiveBluetoothCaptureRuntimeBuildIdentity
    ) -> ResearchAdmission? {
        guard let recipeMarker = infoDictionary[researchRecipeInfoDictionaryKey] as? String,
              recipeMarker == recipeID.rawValue else {
            return nil
        }

        let expectedBuildIdentifier = "Capture Build V14-\(runtimeBuildIdentity.sourceCommitSHA.prefix(12))"
        guard runtimeBuildIdentity.buildIdentifier == expectedBuildIdentifier else {
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

    public enum Status: Equatable, Sendable {
        case noGo(NoGoBlocker)
    }

    public enum NoGoBlocker: Equatable, Sendable {
        /// Release/public authorization is not configured. This does not describe the narrower
        /// exact-build private research admission permitted by the TODAY field-ready directive.
        case finalComposedBuildNotAuthorized
    }
}
