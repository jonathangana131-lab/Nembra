import Testing
@testable import NembraBluetoothCapture

@Suite("Experiment One field execution gate")
struct PassiveBluetoothExperimentOneFieldExecutionGateTests {
    @Test("ordinary test/product host remains mechanically NO-GO")
    func currentPolicyIsNoGoWithoutResearchBuildMetadata() {
        #expect(PassiveBluetoothExperimentOneFieldExecutionGate.recipeID == .es80FingerprintV1)
        #expect(
            PassiveBluetoothExperimentOneFieldExecutionGate.status
                == .noGo(.finalComposedBuildNotAuthorized)
        )
        #expect(!PassiveBluetoothExperimentOneFieldExecutionGate.permitsPhysicalProcedure)
    }

    @Test("public release status vocabulary exposes no caller-constructible GO state")
    func statusVocabularyIsNoGoOnly() {
        switch PassiveBluetoothExperimentOneFieldExecutionGate.status {
        case .noGo(let blocker):
            #expect(blocker == .finalComposedBuildNotAuthorized)
        }
    }

    @Test("TODAY research admission requires the exact canonical producer metadata tuple")
    func researchBuildAdmissionRequiresExactProducerMetadata() throws {
        let sourceSHA = "abcdef0123456789abcdef0123456789abcdef01"
        let buildInstanceID = "a1b2c3d4-e5f6-47a8-90bc-def123456789"
        let expectedBuildIdentifier = "Capture Build V14-abcdef012345"
        let recipeKey = PassiveBluetoothExperimentOneFieldExecutionGate.fieldRecipeInfoDictionaryKey
        let buildIdentifierKey = PassiveBluetoothCaptureRuntimeBuildIdentityReader
            .buildIdentifierInfoDictionaryKey
        let buildInstanceKey = PassiveBluetoothCaptureRuntimeBuildIdentityReader
            .buildInstanceIDInfoDictionaryKey
        let sourceSHAKey = PassiveBluetoothCaptureRuntimeBuildIdentityReader
            .sourceCommitSHAInfoDictionaryKey

        let canonical: [String: Any] = [
            recipeKey: PassiveBluetoothExperimentOneFieldExecutionGate.recipeID.rawValue,
            buildIdentifierKey: expectedBuildIdentifier,
            buildInstanceKey: buildInstanceID,
            sourceSHAKey: sourceSHA,
        ]

        let admission = try #require(
            PassiveBluetoothExperimentOneFieldExecutionGate.researchBuildAdmission(
                infoDictionary: canonical
            )
        )
        #expect(admission.buildIdentifier == expectedBuildIdentifier)
        #expect(admission.buildInstanceID == buildInstanceID)
        #expect(admission.sourceCommitSHA == sourceSHA)

        for missingKey in [recipeKey, buildIdentifierKey, buildInstanceKey, sourceSHAKey] {
            var malformed = canonical
            malformed.removeValue(forKey: missingKey)
            #expect(
                PassiveBluetoothExperimentOneFieldExecutionGate.researchBuildAdmission(
                    infoDictionary: malformed
                ) == nil
            )
        }

        var wrongRecipe = canonical
        wrongRecipe[recipeKey] = "ES80-FINGERPRINT-v2"
        #expect(
            PassiveBluetoothExperimentOneFieldExecutionGate.researchBuildAdmission(
                infoDictionary: wrongRecipe
            ) == nil
        )

        var mismatchedBuildIdentifier = canonical
        mismatchedBuildIdentifier[buildIdentifierKey] = "Capture Build V14-000000000000"
        #expect(
            PassiveBluetoothExperimentOneFieldExecutionGate.researchBuildAdmission(
                infoDictionary: mismatchedBuildIdentifier
            ) == nil
        )

        var uppercaseSourceSHA = canonical
        uppercaseSourceSHA[sourceSHAKey] = sourceSHA.uppercased()
        #expect(
            PassiveBluetoothExperimentOneFieldExecutionGate.researchBuildAdmission(
                infoDictionary: uppercaseSourceSHA
            ) == nil
        )

        var uppercaseBuildInstance = canonical
        uppercaseBuildInstance[buildInstanceKey] = buildInstanceID.uppercased()
        #expect(
            PassiveBluetoothExperimentOneFieldExecutionGate.researchBuildAdmission(
                infoDictionary: uppercaseBuildInstance
            ) == nil
        )
    }
}
