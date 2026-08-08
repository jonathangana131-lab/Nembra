import Testing
@testable import NembraBluetoothCapture

@Suite("Experiment One field execution gate")
struct PassiveBluetoothExperimentOneFieldExecutionGateTests {
    @Test("ordinary V14 test host remains mechanically NO-GO")
    func ordinaryHostPolicyIsNoGo() {
        #expect(PassiveBluetoothExperimentOneFieldExecutionGate.recipeID == .es80FingerprintV1)
        #expect(
            PassiveBluetoothExperimentOneFieldExecutionGate.status
                == .noGo(.finalComposedBuildNotAuthorized)
        )
        #expect(!PassiveBluetoothExperimentOneFieldExecutionGate.permitsPhysicalProcedure)
    }

    @Test("status vocabulary separates locked hosts from exact research-build authority")
    func statusVocabularyPreservesFailClosedBoundary() {
        switch PassiveBluetoothExperimentOneFieldExecutionGate.status {
        case .noGo(let blocker):
            #expect(blocker == .finalComposedBuildNotAuthorized)
            #expect(!PassiveBluetoothExperimentOneFieldExecutionGate.permitsPhysicalProcedure)
        case .researchBuildAuthorized(let authorization):
            #expect(authorization.experimentRecipeID == .es80FingerprintV1)
            #expect(PassiveBluetoothExperimentOneFieldExecutionGate.permitsPhysicalProcedure)
        }
    }
}
