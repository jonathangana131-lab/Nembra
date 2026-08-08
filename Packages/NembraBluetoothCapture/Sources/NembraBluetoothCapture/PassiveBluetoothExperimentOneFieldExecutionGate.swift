import Foundation

/// Package-owned field-execution lock for the first physical ES80 experiment.
///
/// The default V14 product state remains mechanically NO-GO. The zero-argument status and Boolean
/// intentionally cannot be changed by app preferences, launch arguments, imported JSON, typed
/// identifiers, or caller-supplied flags.
///
/// There are two deliberately separate authority lanes:
/// 1. the release-grade independently signed `VerifiedAdmission` path; and
/// 2. the narrow private-research build path used only to collect the first stationary passive
///    ES80 artifact under `CAPTURE_TODAY_FIELD_READY_DIRECTIVE.md`.
///
/// The research lane is not a user setting. It can be minted only from the exact running app when
/// its signed-build metadata carries the canonical ES80 fingerprint recipe plus the producer-shaped
/// build identifier / instance / source tuple that the runtime identity reader independently binds
/// to the running executable and raw Info.plist bytes. A normal build, Debug launch flag, arbitrary
/// imported document, or caller-created Boolean cannot mint that capability.
///
/// This is build/procedure authority only. Possession of either capability does not authenticate an
/// AOVOPRO ES80, prove RF completeness, establish GATT/Tuya/telemetry semantics, or turn a write
/// callback into physical acknowledgement.
public enum PassiveBluetoothExperimentOneFieldExecutionGate {
    public static let recipeID: PassiveBluetoothExperimentRecipeID = .es80FingerprintV1
    public static let fieldRecipeInfoDictionaryKey = "NembraCaptureFieldRecipe"
    public static let status: Status = .noGo(.finalComposedBuildNotAuthorized)

    /// Default/public-release product state. This stays false until a later accepted release-grade
    /// transition deliberately changes the static gate. Private research admission is instance-bound
    /// and therefore never flips this process-global Boolean.
    public static var permitsPhysicalProcedure: Bool {
        permitsPhysicalProcedure(status: status)
    }

    static func permitsPhysicalProcedure(status: Status) -> Bool {
        switch status {
        case .noGo:
            return false
        case .goPrivateResearchBuild:
            return true
        }
    }

    /// Exact running-build identity retained by the private research GO status.
    ///
    /// Public consumers may inspect these values, but cannot construct this type directly. More
    /// importantly, constructing a `Status` value is never sufficient to create a live coordinator;
    /// only the module-owned research-admission producer can feed the capability-only live initializer.
    public struct ResearchBuild: Equatable, Sendable {
        public let buildIdentifier: String
        public let buildInstanceID: String
        public let sourceCommitSHA: String
        public let executableSHA256: String
        public let infoPlistSHA256: String

        fileprivate init(runtimeBuildIdentity: PassiveBluetoothCaptureRuntimeBuildIdentity) {
            buildIdentifier = runtimeBuildIdentity.buildIdentifier
            buildInstanceID = runtimeBuildIdentity.buildInstanceID
            sourceCommitSHA = runtimeBuildIdentity.sourceCommitSHA
            executableSHA256 = runtimeBuildIdentity.executableSHA256
            infoPlistSHA256 = runtimeBuildIdentity.infoPlistSHA256
        }
    }

    /// Module-private capability for the first private field artifact.
    ///
    /// No public/package initializer exists. The production producer below reads only `Bundle.main`
    /// plus the package runtime identity reader, so app/UI or sibling package targets cannot
    /// substitute caller-owned metadata into live coordinator construction.
    struct ResearchAdmission: Equatable, Sendable {
        let build: ResearchBuild

        fileprivate init(build: ResearchBuild) {
            self.build = build
        }

        var status: Status {
            .goPrivateResearchBuild(build)
        }
    }

    enum ResearchAdmissionError: Error, Equatable, Sendable {
        case missingFieldRecipe
        case unsupportedFieldRecipe
        case buildMetadataMismatch
        case nonCanonicalResearchBuildIdentifier
    }

    /// Production private-research admission for the app that is actually running.
    ///
    /// The exact executable and Info.plist hashes are computed by
    /// `PassiveBluetoothCaptureRuntimeBuildIdentityReader.currentApplication()`. The Info.plist
    /// recipe/build tuple is therefore only the mechanically identifiable build-time authorization;
    /// external signed-IPA acceptance still has to match these exact values before the runbook may
    /// authorize the physical procedure.
    static func researchAdmissionForCurrentApplication() throws -> ResearchAdmission {
        let bundle = Bundle.main
        let runtimeBuildIdentity = try PassiveBluetoothCaptureRuntimeBuildIdentityReader.currentApplication()
        return try researchAdmission(
            infoDictionary: bundle.infoDictionary ?? [:],
            runtimeBuildIdentity: runtimeBuildIdentity
        )
    }

    /// Deterministic module seam used by executable regression tests.
    ///
    /// Every embedded build field is re-compared with the already-validated runtime identity instead
    /// of trusting a second caller-provided spelling. Production invokes this only with Bundle.main.
    static func researchAdmission(
        infoDictionary: [String: Any],
        runtimeBuildIdentity: PassiveBluetoothCaptureRuntimeBuildIdentity
    ) throws -> ResearchAdmission {
        guard let fieldRecipe = infoDictionary[fieldRecipeInfoDictionaryKey] as? String else {
            throw ResearchAdmissionError.missingFieldRecipe
        }
        guard fieldRecipe == recipeID.rawValue else {
            throw ResearchAdmissionError.unsupportedFieldRecipe
        }

        guard infoDictionary[PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildIdentifierInfoDictionaryKey]
                as? String == runtimeBuildIdentity.buildIdentifier,
              infoDictionary[PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildInstanceIDInfoDictionaryKey]
                as? String == runtimeBuildIdentity.buildInstanceID,
              infoDictionary[PassiveBluetoothCaptureRuntimeBuildIdentityReader.sourceCommitSHAInfoDictionaryKey]
                as? String == runtimeBuildIdentity.sourceCommitSHA else {
            throw ResearchAdmissionError.buildMetadataMismatch
        }

        let expectedBuildIdentifier = "Capture Build V14-\(runtimeBuildIdentity.sourceCommitSHA.prefix(12))"
        guard runtimeBuildIdentity.buildIdentifier == expectedBuildIdentifier else {
            throw ResearchAdmissionError.nonCanonicalResearchBuildIdentifier
        }

        return ResearchAdmission(build: ResearchBuild(runtimeBuildIdentity: runtimeBuildIdentity))
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
        case goPrivateResearchBuild(ResearchBuild)
    }

    public enum NoGoBlocker: Equatable, Sendable {
        /// The final app-visible Capture composition has not yet earned release-grade physical GO.
        case finalComposedBuildNotAuthorized
    }
}
