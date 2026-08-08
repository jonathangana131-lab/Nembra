import Testing
@testable import NembraBluetoothCapture

@Suite("Experiment One field execution gate")
struct PassiveBluetoothExperimentOneFieldExecutionGateTests {
    @Test("default public V14 field execution remains mechanically NO-GO")
    func currentPolicyIsNoGo() {
        #expect(PassiveBluetoothExperimentOneFieldExecutionGate.recipeID == .es80FingerprintV1)
        #expect(
            PassiveBluetoothExperimentOneFieldExecutionGate.status
                == .noGo(.finalComposedBuildNotAuthorized)
        )
        #expect(!PassiveBluetoothExperimentOneFieldExecutionGate.permitsPhysicalProcedure)
    }

    @Test("status vocabulary distinguishes default NO-GO from instance-bound private research GO")
    func statusVocabularyPreservesDefaultFailClosedBoundary() {
        switch PassiveBluetoothExperimentOneFieldExecutionGate.status {
        case .noGo(let blocker):
            #expect(blocker == .finalComposedBuildNotAuthorized)
            #expect(!PassiveBluetoothExperimentOneFieldExecutionGate.permitsPhysicalProcedure)
        case .goPrivateResearchBuild(let build):
            #expect(!build.buildIdentifier.isEmpty)
            #expect(!build.buildInstanceID.isEmpty)
            #expect(!build.sourceCommitSHA.isEmpty)
            #expect(
                PassiveBluetoothExperimentOneFieldExecutionGate.permitsPhysicalProcedure(
                    status: .goPrivateResearchBuild(build)
                )
            )
        }
    }
}
