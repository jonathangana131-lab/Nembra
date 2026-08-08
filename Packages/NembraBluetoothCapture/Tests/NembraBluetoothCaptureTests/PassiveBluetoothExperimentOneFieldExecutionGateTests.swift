import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Experiment One field execution gate")
struct PassiveBluetoothExperimentOneFieldExecutionGateTests {
    private let sourceCommitSHA = "0123456789abcdef0123456789abcdef01234567"
    private let buildInstanceID = "2C2E24A0-41FB-40A9-8D17-B37BE33B6FB9"

    @Test("current normal build remains mechanically NO-GO")
    func currentPolicyIsNoGo() {
        #expect(PassiveBluetoothExperimentOneFieldExecutionGate.recipeID == .es80FingerprintV1)
        #expect(
            PassiveBluetoothExperimentOneFieldExecutionGate.status
                == .noGo(.finalComposedBuildNotAuthorized)
        )
        #expect(!PassiveBluetoothExperimentOneFieldExecutionGate.permitsPhysicalProcedure)
        #expect(!PassiveBluetoothExperimentOneFieldExecutionGate.permitsCurrentApplicationResearchProcedure)
    }

    @Test("public status vocabulary exposes no caller-constructible release GO state")
    func statusVocabularyIsNoGoOnly() {
        switch PassiveBluetoothExperimentOneFieldExecutionGate.status {
        case .noGo(let blocker):
            #expect(blocker == .finalComposedBuildNotAuthorized)
        }
    }

    @Test("exact producer-style build metadata mints the narrow research capability")
    func exactResearchBuildMetadataIsAdmitted() throws {
        let admission = try #require(
            PassiveBluetoothExperimentOneFieldExecutionGate.researchBuildAdmission(
                infoDictionary: validResearchBuildInfo()
            )
        )

        #expect(admission.recipeID == .es80FingerprintV1)
        #expect(admission.buildIdentifier == "Capture Build V14-0123456789ab")
        #expect(admission.buildInstanceID == buildInstanceID)
        #expect(admission.sourceCommitSHA == sourceCommitSHA)
    }

    @Test(
        "research capability rejects missing or malformed signed build metadata",
        arguments: [
            "NembraCaptureFieldRecipe",
            "NembraCaptureBuildIdentifier",
            "NembraCaptureBuildInstanceID",
            "NembraCaptureBuildCommitSHA",
        ]
    )
    func missingRequiredMemberIsRejected(key: String) {
        var info = validResearchBuildInfo()
        info.removeValue(forKey: key)

        #expect(
            PassiveBluetoothExperimentOneFieldExecutionGate.researchBuildAdmission(
                infoDictionary: info
            ) == nil
        )
    }

    @Test("recipe marker is authority only for the exact Experiment One recipe")
    func wrongRecipeIsRejected() {
        var info = validResearchBuildInfo()
        info["NembraCaptureFieldRecipe"] = "ES80-ELECTRICAL-CORRELATION-v1"

        #expect(
            PassiveBluetoothExperimentOneFieldExecutionGate.researchBuildAdmission(
                infoDictionary: info
            ) == nil
        )
    }

    @Test("build identifier must be derived from the exact source commit")
    func mismatchedBuildIdentifierIsRejected() {
        var info = validResearchBuildInfo()
        info["NembraCaptureBuildIdentifier"] = "Capture Build V14-deadbeefdead"

        #expect(
            PassiveBluetoothExperimentOneFieldExecutionGate.researchBuildAdmission(
                infoDictionary: info
            ) == nil
        )
    }

    @Test("build instance must remain a real UUID")
    func malformedBuildInstanceIsRejected() {
        var info = validResearchBuildInfo()
        info["NembraCaptureBuildInstanceID"] = "field-build"

        #expect(
            PassiveBluetoothExperimentOneFieldExecutionGate.researchBuildAdmission(
                infoDictionary: info
            ) == nil
        )
    }

    @Test("source authority rejects uppercase, short, padded, and non-hex commit identities")
    func malformedSourceCommitIsRejected() {
        let invalidValues = [
            sourceCommitSHA.uppercased(),
            String(sourceCommitSHA.dropLast()),
            " \(sourceCommitSHA)",
            "g" + String(sourceCommitSHA.dropFirst()),
        ]

        for value in invalidValues {
            var info = validResearchBuildInfo()
            info["NembraCaptureBuildCommitSHA"] = value
            info["NembraCaptureBuildIdentifier"] = "Capture Build V14-\(value.prefix(12))"

            #expect(
                PassiveBluetoothExperimentOneFieldExecutionGate.researchBuildAdmission(
                    infoDictionary: info
                ) == nil
            )
        }
    }

    @Test("non-string Info.plist values cannot impersonate research authority")
    func nonStringValuesAreRejected() {
        for key in [
            "NembraCaptureFieldRecipe",
            "NembraCaptureBuildIdentifier",
            "NembraCaptureBuildInstanceID",
            "NembraCaptureBuildCommitSHA",
        ] {
            var info = validResearchBuildInfo()
            info[key] = true

            #expect(
                PassiveBluetoothExperimentOneFieldExecutionGate.researchBuildAdmission(
                    infoDictionary: info
                ) == nil
            )
        }
    }

    private func validResearchBuildInfo() -> [String: Any] {
        [
            "NembraCaptureFieldRecipe": PassiveBluetoothExperimentOneFieldExecutionGate.recipeID.rawValue,
            "NembraCaptureBuildIdentifier": "Capture Build V14-\(sourceCommitSHA.prefix(12))",
            "NembraCaptureBuildInstanceID": buildInstanceID,
            "NembraCaptureBuildCommitSHA": sourceCommitSHA,
        ]
    }
}
