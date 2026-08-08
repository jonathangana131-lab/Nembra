import Foundation

/// Package-owned field-execution lock for the first physical ES80 experiment.
///
/// The release-grade V14 product state remains mechanically NO-GO. The zero-argument production
/// status and Boolean intentionally cannot be changed by app preferences, launch arguments, typed
/// identifiers, caller-supplied flags, Settings, or imported JSON.
///
/// TODAY's private Research Field Build is a deliberately separate, narrower authority lane. The
/// package may mint `ResearchBuildAdmission` only from the current installed application's signed
/// Info.plist when all exact producer metadata is present and the build-time recipe is exactly
/// `ES80-FINGERPRINT-v1`. There is no public initializer and no API that accepts caller-provided
/// metadata, so app code cannot turn a preference or arbitrary JSON object into this capability.
///
/// The existing release-grade `VerifiedAdmission` path remains independently signature-bound and
/// fail-closed while its trust root/policy is not configured. Research admission does not weaken or
/// substitute for that future release path.
///
/// Both forms are build/procedure authority only. Possession of an admission does not authenticate an
/// AOVOPRO ES80, prove RF completeness, establish GATT/Tuya/telemetry semantics, or turn a write
/// callback into physical acknowledgement. Stationary + charger-disconnected preflight, deterministic
/// target correlation, explicit operator action, and the no-application-write invariant remain owned
/// by the downstream Experiment One workflow.
public enum PassiveBluetoothExperimentOneFieldExecutionGate {
    public static let recipeID: PassiveBluetoothExperimentRecipeID = .es80FingerprintV1
    public static let status: Status = .noGo(.finalComposedBuildNotAuthorized)

    private static let fieldRecipeInfoPlistKey = "NembraCaptureFieldRecipe"
    private static let buildIdentifierInfoPlistKey = "NembraCaptureBuildIdentifier"
    private static let buildInstanceIDInfoPlistKey = "NembraCaptureBuildInstanceID"
    private static let sourceCommitSHAInfoPlistKey = "NembraCaptureBuildCommitSHA"
    private static let expectedBuildIdentifierPrefix = "Capture Build V14-"

    /// Release-grade production policy remains NO-GO. A research build must use the separate
    /// current-application admission path below rather than silently broadening this authority.
    public static var permitsPhysicalProcedure: Bool {
        switch status {
        case .noGo:
            return false
        }
    }

    /// Whether this exact running application can mint TODAY's narrow private-research capability.
    ///
    /// This reads only `Bundle.main`; callers cannot supply an alternate dictionary or Settings value.
    public static var permitsCurrentApplicationResearchProcedure: Bool {
        admitCurrentApplicationResearchBuild() != nil
    }

    /// Non-forgeable package capability for TODAY's exact-source private Research Field Build.
    ///
    /// The capability is intentionally smaller than release-grade signed-field authority: it binds
    /// the recipe and exact producer build identity carried by the installed app's signed Info.plist.
    /// It is sufficient only for the first private stationary passive capture under the active TODAY
    /// freeze directive; it must not be promoted to general/public release authorization.
    public struct ResearchBuildAdmission: Equatable, Sendable {
        public let recipeID: PassiveBluetoothExperimentRecipeID
        public let buildIdentifier: String
        public let buildInstanceID: String
        public let sourceCommitSHA: String

        fileprivate init(
            recipeID: PassiveBluetoothExperimentRecipeID,
            buildIdentifier: String,
            buildInstanceID: String,
            sourceCommitSHA: String
        ) {
            self.recipeID = recipeID
            self.buildIdentifier = buildIdentifier
            self.buildInstanceID = buildInstanceID
            self.sourceCommitSHA = sourceCommitSHA
        }
    }

    /// Mint TODAY's narrow research capability only from the current installed app's build metadata.
    ///
    /// The canonical signed-field producer already stamps all four required values into the archive's
    /// Info.plist at build time. Code signing covers the installed app bundle; the normal app has no
    /// runtime Settings/import path that can add these members. Exact retained IPA/signing acceptance
    /// remains a separate final field-run prerequisite rather than being claimed by this runtime gate.
    public static func admitCurrentApplicationResearchBuild() -> ResearchBuildAdmission? {
        researchBuildAdmission(infoDictionary: Bundle.main.infoDictionary ?? [:])
    }

    /// Pure parser used only by package tests. It is internal so app clients cannot feed arbitrary
    /// dictionaries into the authority minting path.
    static func researchBuildAdmission(
        infoDictionary: [String: Any]
    ) -> ResearchBuildAdmission? {
        guard let rawRecipe = infoDictionary[fieldRecipeInfoPlistKey] as? String,
              rawRecipe == recipeID.rawValue,
              let buildIdentifier = infoDictionary[buildIdentifierInfoPlistKey] as? String,
              let buildInstanceID = infoDictionary[buildInstanceIDInfoPlistKey] as? String,
              UUID(uuidString: buildInstanceID) != nil,
              let sourceCommitSHA = infoDictionary[sourceCommitSHAInfoPlistKey] as? String,
              isExactGitCommitSHA(sourceCommitSHA),
              buildIdentifier == expectedBuildIdentifierPrefix + sourceCommitSHA.prefix(12) else {
            return nil
        }

        return ResearchBuildAdmission(
            recipeID: recipeID,
            buildIdentifier: buildIdentifier,
            buildInstanceID: buildInstanceID,
            sourceCommitSHA: sourceCommitSHA
        )
    }

    private static func isExactGitCommitSHA(_ value: String) -> Bool {
        value.count == 40 && value.allSatisfy { character in
            ("0"..."9").contains(character) || ("a"..."f").contains(character)
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
        /// The release-grade final app-visible Capture composition has not yet earned V14 physical GO.
        case finalComposedBuildNotAuthorized
    }
}
