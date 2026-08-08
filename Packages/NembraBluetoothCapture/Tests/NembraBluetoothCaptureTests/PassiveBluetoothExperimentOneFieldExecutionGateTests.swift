import Testing
@testable import NembraBluetoothCapture

@Suite("Experiment One field execution gate")
struct PassiveBluetoothExperimentOneFieldExecutionGateTests {
    @Test("current V14 field execution is mechanically NO-GO without verified authority")
    func currentPolicyIsNoGo() {
        #expect(PassiveBluetoothExperimentOneFieldExecutionGate.recipeID == .es80FingerprintV1)
        #expect(
            PassiveBluetoothExperimentOneFieldExecutionGate.status
                == .noGo(.finalComposedBuildNotAuthorized)
        )
        #expect(!PassiveBluetoothExperimentOneFieldExecutionGate.permitsPhysicalProcedure)
    }

    @Test("default status cannot drift to GO just because GO vocabulary exists")
    func defaultStatusRemainsNoGo() {
        if case let .noGo(blocker) = PassiveBluetoothExperimentOneFieldExecutionGate.status {
            #expect(blocker == .finalComposedBuildNotAuthorized)
        } else {
            #expect(Bool(false), "Repository/default field status must remain NO-GO")
        }
    }
}
