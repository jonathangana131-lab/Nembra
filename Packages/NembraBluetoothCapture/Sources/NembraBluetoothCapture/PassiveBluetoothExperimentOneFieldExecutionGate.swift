import Foundation

/// Package-owned field-execution policy for the first physical ES80 experiment.
///
/// V14's normal product/test state remains mechanically NO-GO. For the private first-capture field
/// window, the active TODAY directive permits one narrower authority: an exact build-time research
/// configuration for `ES80-FINGERPRINT-v1`. That configuration is admitted only when the running
/// application's embedded recipe marker and complete embedded build tuple agree with the exact
/// runtime build identity read from the running executable + raw Info.plist.
///
/// The research path cannot be toggled by app preferences, launch arguments, environment variables,
/// or imported JSON. It is a build-time property of the installed app. Signed-installable and
/// intended-device acceptance remain separate required field/runbook gates; this package check does
/// not pretend to verify an IPA signature by itself.
///
/// The stronger release-grade path remains available: a future accepted release may present a
/// `PassiveBluetoothCaptureVerifiedFieldAuthorization` minted by the package's independent-signature
/// verifier. `admit(verifiedAuthorization:)` still turns only that verifier output into a
/// `VerifiedAdmission` capability. The external P-256 trust root may remain unconfigured while the
/// private TODAY research path is used; that does not weaken the later release-grade boundary.
///
/// This is build/procedure authority only. A permitted build does not authenticate an AOVOPRO ES80,
/// prove RF completeness, establish GATT/Tuya/telemetry semantics, or turn a write callback into
/// physical acknowledgement.
public enum PassiveBluetoothExperimentOneFieldExecutionGate {
    public static let recipeID: PassiveBluetoothExperimentRecipeID = .es80FingerprintV1

    /// The exact Info.plist build-time marker already stamped by the canonical field-build producer.
    /// Normal Settings/preferences and imported artifacts cannot create or mutate this value.
    public static let researchFieldRecipeInfoDictionaryKey = "NembraCaptureFieldRecipe"

    /// One process-lifetime admission for the app that is actually running.
    ///
    /// The live authority lane is mechanically absent from Debug, Simulator, and non-iOS builds even
    /// if matching metadata is injected. The canonical producer archives Release for physical iOS;
    /// only that build class may pay the runtime hashing cost and attempt exact-build admission.
    package static let currentResearchBuildAdmission: ResearchBuildAdmission? = {
#if os(iOS) && !targetEnvironment(simulator) && !DEBUG
        let infoDictionary = Bundle.main.infoDictionary ?? [:]
        guard let fieldRecipe = infoDictionary[researchFieldRecipeInfoDictionaryKey] as? String,
              fieldRecipe == recipeID.rawValue,
              let runtimeBuildIdentity = try? PassiveBluetoothCaptureRuntimeBuildIdentityReader
                .currentApplication() else {
            return nil
        }

        return researchBuildAdmission(
            infoDictionary: infoDictionary,
            runtimeBuildIdentity: runtimeBuildIdentity
        )
#else
        return nil
#endif
    }()

    public static let status: Status = {
        if currentResearchBuildAdmission != nil {
            return .go(.buildTimeResearchConfiguration)
        }
        return .noGo(.finalComposedBuildNotAuthorized)
    }()

    public static var permitsPhysicalProcedure: Bool {
        switch status {
        case .noGo:
            return false
        case .go:
            return true
        }
    }

    /// Package-only capability for the TODAY private research build.
    ///
    /// It deliberately carries the exact runtime identity instead of a Boolean. The live controller
    /// factory can therefore require that this process actually passed the package's build-time
    /// research admission rather than trusting a caller-supplied `true` value.
    package struct ResearchBuildAdmission: Equatable, Sendable {
        let recipeID: PassiveBluetoothExperimentRecipeID
        let runtimeBuildIdentity: PassiveBluetoothCaptureRuntimeBuildIdentity
    }

    /// Deterministic admission logic shared by the running-app producer and package tests.
    ///
    /// The canonical producer names builds `Capture Build V14-<first 12 source SHA>` and stamps the
    /// same build identifier, build-instance UUID and full source SHA into Info.plist. Requiring the
    /// complete tuple here prevents a recipe marker copied onto an ordinary/mismatched build from
    /// becoming research authority.
    package static func researchBuildAdmission(
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

        let expectedBuildIdentifier = "Capture Build V14-\(runtimeBuildIdentity.sourceCommitSHA.prefix(12))"
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
    /// public production verifier.
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
        case go(GoAuthority)
    }

    public enum GoAuthority: Equatable, Sendable {
        /// Private first-capture authority allowed by `CAPTURE_TODAY_FIELD_READY_DIRECTIVE.md`.
        /// Signed-installable acceptance and the final runbook still gate whether the operator may
        /// actually perform the experiment.
        case buildTimeResearchConfiguration
    }

    public enum NoGoBlocker: Equatable, Sendable {
        /// The running app is not the exact canonical build-time research configuration.
        case finalComposedBuildNotAuthorized
    }
}
