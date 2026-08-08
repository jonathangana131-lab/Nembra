import Testing
@testable import NembraBluetoothCapture

@Suite("Experiment One field execution gate")
struct PassiveBluetoothExperimentOneFieldExecutionGateTests {
    private let sourceCommitSHA = "abcdef0123456789abcdef0123456789abcdef01"
    private let buildInstanceID = "a1b2c3d4-e5f6-47a8-90bc-def123456789"

    @Test("ordinary test build remains mechanically NO-GO")
    func currentPolicyIsNoGo() {
        #expect(PassiveBluetoothExperimentOneFieldExecutionGate.recipeID == .es80FingerprintV1)
        #expect(
            PassiveBluetoothExperimentOneFieldExecutionGate.status
                == .noGo(.finalComposedBuildNotAuthorized)
        )
        #expect(!PassiveBluetoothExperimentOneFieldExecutionGate.productionPermitsPhysicalProcedure)
        #expect(!PassiveBluetoothExperimentOneFieldExecutionGate.permitsPhysicalProcedure)
    }

    @Test("public production status vocabulary exposes no caller-constructible GO state")
    func statusVocabularyIsNoGoOnly() {
        switch PassiveBluetoothExperimentOneFieldExecutionGate.status {
        case .noGo(let blocker):
            #expect(blocker == .finalComposedBuildNotAuthorized)
        }
    }

    @Test("dedicated signed-field metadata mints the narrow research admission")
    func exactResearchBuildTupleIsAdmitted() throws {
        let admission = try #require(
            PassiveBluetoothExperimentOneFieldExecutionGate.researchBuildAdmission(
                infoDictionary: validResearchInfoDictionary()
            )
        )

        #expect(admission.experimentRecipeID == .es80FingerprintV1)
        #expect(admission.sourceCommitSHA == sourceCommitSHA)
        #expect(admission.buildInstanceID == buildInstanceID)
        #expect(admission.buildIdentifier == "Capture Build V14-abcdef012345")
    }

    @Test("recipe marker is exact and cannot be omitted or generalized")
    func researchRecipeMustBeExact() {
        var missing = validResearchInfoDictionary()
        missing.removeValue(
            forKey: PassiveBluetoothExperimentOneFieldExecutionGate
                .researchFieldRecipeInfoDictionaryKey
        )
        #expect(
            PassiveBluetoothExperimentOneFieldExecutionGate.researchBuildAdmission(
                infoDictionary: missing
            ) == nil
        )

        var wrong = validResearchInfoDictionary()
        wrong[
            PassiveBluetoothExperimentOneFieldExecutionGate.researchFieldRecipeInfoDictionaryKey
        ] = "ES80-ELECTRICAL-CORRELATION-v1"
        #expect(
            PassiveBluetoothExperimentOneFieldExecutionGate.researchBuildAdmission(
                infoDictionary: wrong
            ) == nil
        )
    }

    @Test("research build identifier must bind the exact source prefix")
    func researchBuildIdentifierBindsSource() {
        var stale = validResearchInfoDictionary()
        stale[
            PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildIdentifierInfoDictionaryKey
        ] = "Capture Build V14-000000000000"

        #expect(
            PassiveBluetoothExperimentOneFieldExecutionGate.researchBuildAdmission(
                infoDictionary: stale
            ) == nil
        )
    }

    @Test("malformed source or build-instance metadata fails closed")
    func malformedBuildMetadataFailsClosed() {
        var badSource = validResearchInfoDictionary()
        badSource[
            PassiveBluetoothCaptureRuntimeBuildIdentityReader.sourceCommitSHAInfoDictionaryKey
        ] = "abcdef012345"
        #expect(
            PassiveBluetoothExperimentOneFieldExecutionGate.researchBuildAdmission(
                infoDictionary: badSource
            ) == nil
        )

        var badInstance = validResearchInfoDictionary()
        badInstance[
            PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildInstanceIDInfoDictionaryKey
        ] = "not-a-build-instance"
        #expect(
            PassiveBluetoothExperimentOneFieldExecutionGate.researchBuildAdmission(
                infoDictionary: badInstance
            ) == nil
        )
    }

    private func validResearchInfoDictionary() -> [String: Any] {
        [
            PassiveBluetoothExperimentOneFieldExecutionGate.researchFieldRecipeInfoDictionaryKey:
                "ES80-FINGERPRINT-v1",
            PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildIdentifierInfoDictionaryKey:
                "Capture Build V14-abcdef012345",
            PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildInstanceIDInfoDictionaryKey:
                buildInstanceID,
            PassiveBluetoothCaptureRuntimeBuildIdentityReader.sourceCommitSHAInfoDictionaryKey:
                sourceCommitSHA,
        ]
    }
}
