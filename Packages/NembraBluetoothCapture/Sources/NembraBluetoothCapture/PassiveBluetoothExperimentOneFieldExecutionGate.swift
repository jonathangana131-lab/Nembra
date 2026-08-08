import Foundation

/// Package-owned field-execution policy for the first physical ES80 experiment.
///
/// Ordinary, Debug, Simulator, and package-test builds remain mechanically NO-GO. The active TODAY
/// field-ready directive permits one narrower private-research exception: the exact physical-iOS
/// Release field build may run `ES80-FINGERPRINT-v1` when the package itself proves the complete
/// canonical build-time tuple against the exact runtime build identity read from Bundle.main.
///
/// That research capability cannot be minted by Settings, UserDefaults, launch arguments,
/// environment variables, caller Booleans, or imported JSON. It is derived once per process from
/// the code-signed app bundle metadata already emitted by the canonical signed-field producer, plus
/// SHA-256 identity of the exact running executable and raw Info.plist.
///
/// The stronger independently signed `VerifiedAdmission` path remains intact for later release-grade
/// authorization. TODAY's research exception does not authenticate an AOVOPRO ES80, prove RF
/// completeness, establish GATT/Tuya/telemetry semantics, authorize writes, or replace the final
/// signed-installable/intended-device/runbook acceptance gates.
public enum PassiveBluetoothExperimentOneFieldExecutionGate {
    public static let recipeID: PassiveBluetoothExperimentRecipeID = .es80FingerprintV1

    package static let researchFieldRecipeInfoDictionaryKey = "NembraCaptureFieldRecipe"
    private static let researchBuildIdentifierPrefix = "Capture Build V14-"

    /// One process-lifetime package-owned admission for the running application.
    ///
    /// The compile-time platform fence matters: even correctly shaped metadata cannot make Debug or
    /// Simulator builds physical-research authority. The canonical producer archives Release for a
    /// physical iOS target, so this restriction matches the intended private field artifact exactly.
    package static let currentResearchBuildAdmission: ResearchBuildAdmission? = {
#if os(iOS) && !targetEnvironment(simulator) && !DEBUG
        let infoDictionary = Bundle.main.infoDictionary ?? [:]
        guard let recipe = infoDictionary[researchFieldRecipeInfoDictionaryKey] as? String,
              recipe == recipeID.rawValue,
              let runtimeBuildIdentity = try? PassiveBluetoothCaptureRuntimeBuildIdentityReader
                .currentApplication() else {
            return nil
        }

        return resolveResearchBuildAdmission(
            infoDictionary: infoDictionary,
            runtimeBuildIdentity: runtimeBuildIdentity
        )
#else
        return nil
#endif
    }()

    /// Runtime truth for the app process that is actually executing.
    ///
    /// `.researchBuildAuthorized` is deliberately not the final public/release GO record. It means
    /// only that this process is the narrowly admitted TODAY Research Field Build. The durable
    /// physical runbook must still name and accept the exact signed installable before the operator
    /// may perform the experiment.
    public static let status: Status = {
        currentResearchBuildAdmission == nil
            ? .noGo(.finalComposedBuildNotAuthorized)
            : .researchBuildAuthorized
    }()

    public static var permitsPhysicalProcedure: Bool {
        switch status {
        case .noGo:
            return false
        case .researchBuildAuthorized:
            return true
        }
    }

    /// Package-only capability for TODAY's exact running Research Field Build.
    ///
    /// The exact executable + raw Info.plist hashes are retained through the runtime identity rather
    /// than collapsing authorization to a Boolean. App/UI callers cannot construct this value.
    package struct ResearchBuildAdmission: Equatable, Sendable {
        let recipeID: PassiveBluetoothExperimentRecipeID
        let runtimeBuildIdentity: PassiveBluetoothCaptureRuntimeBuildIdentity

        fileprivate init(
            recipeID: PassiveBluetoothExperimentRecipeID,
            runtimeBuildIdentity: PassiveBluetoothCaptureRuntimeBuildIdentity
        ) {
            self.recipeID = recipeID
            self.runtimeBuildIdentity = runtimeBuildIdentity
        }
    }

    /// Pure resolver used by the running-app producer above and deterministic package tests.
    ///
    /// Production never accepts caller-supplied dictionaries: the only live producer reads
    /// `Bundle.main` and `currentApplication()`. Requiring the complete raw embedded tuple to equal
    /// the runtime identity also prevents a recipe marker paired with stale/mismatched build metadata
    /// from becoming authority in tests or a future refactor.
    package static func resolveResearchBuildAdmission(
        infoDictionary: [String: Any],
        runtimeBuildIdentity: PassiveBluetoothCaptureRuntimeBuildIdentity
    ) -> ResearchBuildAdmission? {
        guard let embeddedRecipe = infoDictionary[researchFieldRecipeInfoDictionaryKey] as? String,
              embeddedRecipe == recipeID.rawValue,
              let embeddedBuildIdentifier = infoDictionary[
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildIdentifierInfoDictionaryKey
              ] as? String,
              let embeddedBuildInstanceID = infoDictionary[
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildInstanceIDInfoDictionaryKey
              ] as? String,
              let embeddedSourceCommitSHA = infoDictionary[
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.sourceCommitSHAInfoDictionaryKey
              ] as? String,
              embeddedBuildIdentifier == runtimeBuildIdentity.buildIdentifier,
              embeddedBuildInstanceID == runtimeBuildIdentity.buildInstanceID,
              embeddedSourceCommitSHA == runtimeBuildIdentity.sourceCommitSHA else {
            return nil
        }

        let expectedBuildIdentifier = researchBuildIdentifierPrefix
            + String(runtimeBuildIdentity.sourceCommitSHA.prefix(12))
        guard runtimeBuildIdentity.buildIdentifier == expectedBuildIdentifier else {
            return nil
        }

        return ResearchBuildAdmission(
            recipeID: recipeID,
            runtimeBuildIdentity: runtimeBuildIdentity
        )
    }

    /// Non-forgeable package capability derived only from a verified signed field authorization.
    ///
    /// Its initializer is private to this source file. Public callers can obtain an instance only by
    /// first producing a `PassiveBluetoothCaptureVerifiedFieldAuthorization` through the package's
    /// public production verifier. This remains the release-grade direction after the private TODAY
    /// data-unlock artifact is collected.
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

    /// Convert only already-verified external authority into a package-owned release-grade execution
    /// capability. The verifier currently enforces these relationships too; the gate repeats the
    /// final recipe, procedure and exact-rendezvous checks so a later verifier evolution cannot
    /// silently broaden physical execution policy.
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
        case researchBuildAuthorized
    }

    public enum NoGoBlocker: Equatable, Sendable {
        /// The running app is not the exact admitted private Research Field Build.
        case finalComposedBuildNotAuthorized
    }
}
