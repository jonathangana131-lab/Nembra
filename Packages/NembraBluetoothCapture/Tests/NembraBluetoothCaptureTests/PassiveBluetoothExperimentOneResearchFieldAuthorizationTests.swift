import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Experiment One TODAY research field authorization")
struct PassiveBluetoothExperimentOneResearchFieldAuthorizationTests {
    private let sourceSHA = "0123456789abcdef0123456789abcdef01234567"
    private let buildInstanceID = "11111111-2222-3333-4444-555555555555"

    @Test("exact signed-field build metadata shape admits the stationary research recipe")
    func exactFieldCandidateMetadataAdmitsResearchRecipe() throws {
        let identity = try makeRuntimeIdentity(
            buildIdentifier: "Capture Build V14-0123456789ab"
        )
        var infoDictionary = identityInfoDictionary(
            buildIdentifier: "Capture Build V14-0123456789ab"
        )
        infoDictionary[PassiveBluetoothExperimentOneFieldExecutionGate.researchFieldRecipeInfoDictionaryKey]
            = PassiveBluetoothExperimentOneFieldExecutionGate.recipeID.rawValue

        let authorization = PassiveBluetoothExperimentOneFieldExecutionGate.resolveResearchFieldAuthorization(
            infoDictionary: infoDictionary,
            runtimeBuildIdentity: identity
        )

        #expect(authorization != nil)
        #expect(authorization?.buildIdentifier == "Capture Build V14-0123456789ab")
        #expect(authorization?.buildInstanceID == buildInstanceID)
        #expect(authorization?.sourceCommitSHA == sourceSHA)
        #expect(authorization?.experimentRecipeID == .es80FingerprintV1)
        #expect(authorization?.executableSHA256.count == 64)
        #expect(authorization?.infoPlistSHA256.count == 64)
    }

    @Test("recipe marker alone cannot authorize a build without exact runtime identity")
    func recipeMarkerAloneFailsClosed() {
        let infoDictionary: [String: Any] = [
            PassiveBluetoothExperimentOneFieldExecutionGate.researchFieldRecipeInfoDictionaryKey:
                PassiveBluetoothExperimentOneFieldExecutionGate.recipeID.rawValue
        ]

        #expect(
            PassiveBluetoothExperimentOneFieldExecutionGate.resolveResearchFieldAuthorization(
                infoDictionary: infoDictionary,
                runtimeBuildIdentity: nil
            ) == nil
        )
    }

    @Test("ordinary exact-runtime build without research recipe stays locked")
    func missingResearchRecipeFailsClosed() throws {
        let identity = try makeRuntimeIdentity(
            buildIdentifier: "Capture Build V14-0123456789ab"
        )

        #expect(
            PassiveBluetoothExperimentOneFieldExecutionGate.resolveResearchFieldAuthorization(
                infoDictionary: identityInfoDictionary(
                    buildIdentifier: "Capture Build V14-0123456789ab"
                ),
                runtimeBuildIdentity: identity
            ) == nil
        )
    }

    @Test("build identifier must mechanically match embedded full source commit")
    func mismatchedBuildIdentifierFailsClosed() throws {
        let identity = try makeRuntimeIdentity(
            buildIdentifier: "Capture Build V14-deadbeefdead"
        )
        var infoDictionary = identityInfoDictionary(
            buildIdentifier: "Capture Build V14-deadbeefdead"
        )
        infoDictionary[PassiveBluetoothExperimentOneFieldExecutionGate.researchFieldRecipeInfoDictionaryKey]
            = PassiveBluetoothExperimentOneFieldExecutionGate.recipeID.rawValue

        #expect(
            PassiveBluetoothExperimentOneFieldExecutionGate.resolveResearchFieldAuthorization(
                infoDictionary: infoDictionary,
                runtimeBuildIdentity: identity
            ) == nil
        )
    }

    @Test("wrong recipe cannot authorize an otherwise exact field-candidate build")
    func wrongRecipeFailsClosed() throws {
        let identity = try makeRuntimeIdentity(
            buildIdentifier: "Capture Build V14-0123456789ab"
        )
        var infoDictionary = identityInfoDictionary(
            buildIdentifier: "Capture Build V14-0123456789ab"
        )
        infoDictionary[PassiveBluetoothExperimentOneFieldExecutionGate.researchFieldRecipeInfoDictionaryKey]
            = "NOT-ES80-FINGERPRINT-v1"

        #expect(
            PassiveBluetoothExperimentOneFieldExecutionGate.resolveResearchFieldAuthorization(
                infoDictionary: infoDictionary,
                runtimeBuildIdentity: identity
            ) == nil
        )
    }

    private func makeRuntimeIdentity(
        buildIdentifier: String
    ) throws -> PassiveBluetoothCaptureRuntimeBuildIdentity {
        try PassiveBluetoothCaptureRuntimeBuildIdentityReader.resolveEmbeddedMetadata(
            infoDictionary: identityInfoDictionary(buildIdentifier: buildIdentifier),
            executableData: Data("exact-running-executable".utf8),
            infoPlistData: Data("exact-raw-info-plist".utf8)
        )
    }

    private func identityInfoDictionary(
        buildIdentifier: String
    ) -> [String: Any] {
        [
            PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildIdentifierInfoDictionaryKey:
                buildIdentifier,
            PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildInstanceIDInfoDictionaryKey:
                buildInstanceID,
            PassiveBluetoothCaptureRuntimeBuildIdentityReader.sourceCommitSHAInfoDictionaryKey:
                sourceSHA
        ]
    }
}
