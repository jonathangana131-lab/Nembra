import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Experiment One field execution gate")
struct PassiveBluetoothExperimentOneFieldExecutionGateTests {
    private typealias Gate = PassiveBluetoothExperimentOneFieldExecutionGate
    private typealias Reader = PassiveBluetoothCaptureRuntimeBuildIdentityReader

    private let sourceCommit = "0123456789abcdef0123456789abcdef01234567"
    private let buildInstanceID = "12345678-90ab-cdef-1234-567890abcdef"

    @Test("ordinary package/test build remains mechanically NO-GO")
    func ordinaryBuildIsNoGo() {
        #expect(Gate.recipeID == .es80FingerprintV1)
        #expect(Gate.status == .noGo(.finalComposedBuildNotAuthorized))
        #expect(!Gate.permitsPhysicalProcedure)
    }

    @Test("canonical exact-source signed research metadata admits the compiled passive recipe")
    func canonicalResearchBuildAdmits() throws {
        let info = researchInfoDictionary()
        let identity = try runtimeIdentity(infoDictionary: info)
        let admission = Gate.researchAdmission(
            infoDictionary: info,
            runtimeBuildIdentity: identity
        )

        #expect(admission?.experimentRecipeID == .es80FingerprintV1)
        #expect(admission?.buildIdentifier == "Capture Build V14-0123456789ab")
        #expect(admission?.buildInstanceID == buildInstanceID)
        #expect(admission?.sourceCommitSHA == sourceCommit)
    }

    @Test("missing or wrong field recipe marker fails closed")
    func recipeMarkerMustMatchExactly() throws {
        var missing = researchInfoDictionary()
        missing.removeValue(forKey: Gate.researchRecipeInfoDictionaryKey)
        let missingIdentity = try runtimeIdentity(infoDictionary: missing)
        #expect(
            Gate.researchAdmission(
                infoDictionary: missing,
                runtimeBuildIdentity: missingIdentity
            ) == nil
        )

        var wrong = researchInfoDictionary()
        wrong[Gate.researchRecipeInfoDictionaryKey] = "ES80-ELECTRICAL-CORRELATION-v1"
        let wrongIdentity = try runtimeIdentity(infoDictionary: wrong)
        #expect(
            Gate.researchAdmission(
                infoDictionary: wrong,
                runtimeBuildIdentity: wrongIdentity
            ) == nil
        )
    }

    @Test("generic build label cannot turn the recipe marker into research authority")
    func producerBuildIdentityIsRequired() throws {
        var info = researchInfoDictionary()
        info[Reader.buildIdentifierInfoDictionaryKey] = "Local Debug Build"
        let identity = try runtimeIdentity(infoDictionary: info)

        #expect(
            Gate.researchAdmission(
                infoDictionary: info,
                runtimeBuildIdentity: identity
            ) == nil
        )
    }

    @Test("research admission rendezvous follows the validated runtime source commit")
    func buildIdentifierMustMatchRuntimeSource() throws {
        var info = researchInfoDictionary()
        info[Reader.sourceCommitSHAInfoDictionaryKey] = "abcdef0123456789abcdef0123456789abcdef01"
        let identity = try runtimeIdentity(infoDictionary: info)

        #expect(
            Gate.researchAdmission(
                infoDictionary: info,
                runtimeBuildIdentity: identity
            ) == nil
        )
    }

    @Test("release status vocabulary still exposes no caller-constructible GO state")
    func releaseStatusVocabularyIsNoGoOnly() {
        switch Gate.status {
        case .noGo(let blocker):
            #expect(blocker == .finalComposedBuildNotAuthorized)
        }
    }

    private func researchInfoDictionary() -> [String: Any] {
        [
            Reader.buildIdentifierInfoDictionaryKey: "Capture Build V14-0123456789ab",
            Reader.buildInstanceIDInfoDictionaryKey: buildInstanceID,
            Reader.sourceCommitSHAInfoDictionaryKey: sourceCommit,
            Gate.researchRecipeInfoDictionaryKey: Gate.recipeID.rawValue,
        ]
    }

    private func runtimeIdentity(
        infoDictionary: [String: Any]
    ) throws -> PassiveBluetoothCaptureRuntimeBuildIdentity {
        try Reader.resolveEmbeddedMetadata(
            infoDictionary: infoDictionary,
            executableData: Data("signed research executable fixture".utf8),
            infoPlistData: Data("signed research info plist fixture".utf8)
        )
    }
}
