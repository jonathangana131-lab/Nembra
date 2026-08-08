import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Experiment One field execution gate")
struct PassiveBluetoothExperimentOneFieldExecutionGateTests {
    private let sourceCommitSHA = "abcdef0123456789abcdef0123456789abcdef01"
    private let buildInstanceID = "a1b2c3d4-e5f6-47a8-90bc-def123456789"
    private let buildIdentifier = "Capture Build V14-abcdef012345"

    @Test("ordinary package-test host remains mechanically NO-GO")
    func currentPolicyIsNoGo() {
        #expect(PassiveBluetoothExperimentOneFieldExecutionGate.recipeID == .es80FingerprintV1)
        #expect(
            PassiveBluetoothExperimentOneFieldExecutionGate.status
                == .noGo(.finalComposedBuildNotAuthorized)
        )
        #expect(!PassiveBluetoothExperimentOneFieldExecutionGate.permitsPhysicalProcedure)
        #expect(PassiveBluetoothExperimentOneFieldExecutionGate.currentResearchBuildAdmission == nil)
    }

    @Test("public status reports research authority distinctly from final release GO")
    func statusVocabularyKeepsResearchAuthorityExplicit() {
        switch PassiveBluetoothExperimentOneFieldExecutionGate.status {
        case .noGo(let blocker):
            #expect(blocker == .finalComposedBuildNotAuthorized)
        case .researchBuildAuthorized:
            Issue.record("package-test host must not become a physical Research Field Build")
        }
    }

    @Test("exact recipe and exact runtime-bound canonical tuple admit TODAY research build")
    func exactResearchBuildTupleIsAdmitted() throws {
        let runtimeIdentity = try makeRuntimeIdentity()
        let admission = try #require(
            PassiveBluetoothExperimentOneFieldExecutionGate.resolveResearchBuildAdmission(
                infoDictionary: canonicalInfoDictionary(),
                runtimeBuildIdentity: runtimeIdentity
            )
        )

        #expect(admission.recipeID == .es80FingerprintV1)
        #expect(admission.runtimeBuildIdentity == runtimeIdentity)
        #expect(admission.runtimeBuildIdentity.executableSHA256.count == 64)
        #expect(admission.runtimeBuildIdentity.infoPlistSHA256.count == 64)
    }

    @Test("recipe marker alone and every build-tuple drift fail closed")
    func researchBuildTupleDriftIsRejected() throws {
        let runtimeIdentity = try makeRuntimeIdentity()
        let gate = PassiveBluetoothExperimentOneFieldExecutionGate.self
        let buildIdentifierKey = PassiveBluetoothCaptureRuntimeBuildIdentityReader
            .buildIdentifierInfoDictionaryKey
        let buildInstanceKey = PassiveBluetoothCaptureRuntimeBuildIdentityReader
            .buildInstanceIDInfoDictionaryKey
        let sourceSHAKey = PassiveBluetoothCaptureRuntimeBuildIdentityReader
            .sourceCommitSHAInfoDictionaryKey

        #expect(
            gate.resolveResearchBuildAdmission(
                infoDictionary: [
                    gate.researchFieldRecipeInfoDictionaryKey: gate.recipeID.rawValue,
                ],
                runtimeBuildIdentity: runtimeIdentity
            ) == nil
        )

        var wrongRecipe = canonicalInfoDictionary()
        wrongRecipe[gate.researchFieldRecipeInfoDictionaryKey] = "ES80-ELECTRICAL-CORRELATION-v1"
        #expect(
            gate.resolveResearchBuildAdmission(
                infoDictionary: wrongRecipe,
                runtimeBuildIdentity: runtimeIdentity
            ) == nil
        )

        var wrongBuild = canonicalInfoDictionary()
        wrongBuild[buildIdentifierKey] = "Capture Build V14-000000000000"
        #expect(
            gate.resolveResearchBuildAdmission(
                infoDictionary: wrongBuild,
                runtimeBuildIdentity: runtimeIdentity
            ) == nil
        )

        var wrongInstance = canonicalInfoDictionary()
        wrongInstance[buildInstanceKey] = "11111111-2222-4333-8444-555555555555"
        #expect(
            gate.resolveResearchBuildAdmission(
                infoDictionary: wrongInstance,
                runtimeBuildIdentity: runtimeIdentity
            ) == nil
        )

        var wrongSource = canonicalInfoDictionary()
        wrongSource[sourceSHAKey] = String(repeating: "0", count: 40)
        #expect(
            gate.resolveResearchBuildAdmission(
                infoDictionary: wrongSource,
                runtimeBuildIdentity: runtimeIdentity
            ) == nil
        )

        var uppercaseSource = canonicalInfoDictionary()
        uppercaseSource[sourceSHAKey] = sourceCommitSHA.uppercased()
        #expect(
            gate.resolveResearchBuildAdmission(
                infoDictionary: uppercaseSource,
                runtimeBuildIdentity: runtimeIdentity
            ) == nil
        )

        let noncanonicalRuntimeIdentity = try PassiveBluetoothCaptureRuntimeBuildIdentityReader
            .resolveEmbeddedMetadata(
                infoDictionary: [
                    buildIdentifierKey: "Capture Build V14-manual",
                    buildInstanceKey: buildInstanceID,
                    sourceSHAKey: sourceCommitSHA,
                ],
                executableData: Data("research-gate-executable".utf8),
                infoPlistData: Data("research-gate-info-plist".utf8)
            )
        var noncanonicalInfo = canonicalInfoDictionary()
        noncanonicalInfo[buildIdentifierKey] = noncanonicalRuntimeIdentity.buildIdentifier
        #expect(
            gate.resolveResearchBuildAdmission(
                infoDictionary: noncanonicalInfo,
                runtimeBuildIdentity: noncanonicalRuntimeIdentity
            ) == nil
        )
    }

    private func canonicalInfoDictionary() -> [String: Any] {
        [
            PassiveBluetoothExperimentOneFieldExecutionGate.researchFieldRecipeInfoDictionaryKey:
                PassiveBluetoothExperimentOneFieldExecutionGate.recipeID.rawValue,
            PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildIdentifierInfoDictionaryKey:
                buildIdentifier,
            PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildInstanceIDInfoDictionaryKey:
                buildInstanceID,
            PassiveBluetoothCaptureRuntimeBuildIdentityReader.sourceCommitSHAInfoDictionaryKey:
                sourceCommitSHA,
        ]
    }

    private func makeRuntimeIdentity() throws -> PassiveBluetoothCaptureRuntimeBuildIdentity {
        try PassiveBluetoothCaptureRuntimeBuildIdentityReader.resolveEmbeddedMetadata(
            infoDictionary: canonicalInfoDictionary(),
            executableData: Data("research-gate-executable".utf8),
            infoPlistData: Data("research-gate-info-plist".utf8)
        )
    }
}
