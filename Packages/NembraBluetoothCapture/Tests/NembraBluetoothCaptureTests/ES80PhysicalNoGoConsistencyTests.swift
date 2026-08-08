import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("ES80 physical NO-GO consistency")
struct ES80PhysicalNoGoConsistencyTests {
    private var repositoryRoot: URL {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 {
            root.deleteLastPathComponent()
        }
        return root
    }

    private func physicalRunbook() throws -> String {
        try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("docs")
                .appendingPathComponent("ES80_PHYSICAL_CAPTURE_RUNBOOK.md"),
            encoding: .utf8
        )
    }

    @Test("durable runbook and compiled field gate remain locked together")
    func runbookAndCompiledGateAreBothNoGo() throws {
        let runbook = try physicalRunbook()

        #expect(
            runbook.contains(
                "Status: **NO-GO — PHYSICAL EXPERIMENT ONE MUST NOT RUN FROM THE CURRENT SOFTWARE LINEAGE.**"
            )
        )
        #expect(
            PassiveBluetoothExperimentOneFieldExecutionGate.status
                == .noGo(.finalComposedBuildNotAuthorized)
        )
        #expect(!PassiveBluetoothExperimentOneFieldExecutionGate.permitsPhysicalProcedure)
        #expect(PassiveBluetoothExperimentOneFieldExecutionGate.recipeID == .es80FingerprintV1)
    }

    @Test("final physical GO record remains intentionally unissued")
    func finalGoRecordIsBlankWhileGateIsNoGo() throws {
        let runbook = try physicalRunbook()
        let requiredBlankRecordLines = [
            "- Accepted exact build/commit: **NOT YET AUTHORIZED**",
            "- Accepted signed-device/installable artifact identity/digest: **NOT YET AUTHORIZED**",
            "- Independent field-build acceptance / attestation subject: **NOT YET AUTHORIZED**",
            "- Package field-execution gate state: **NO-GO / NOT YET AUTHORIZED**",
            "- Procedure version: **V14 / NOT YET AUTHORIZED**",
            "- Expected artifact: **NOT YET AUTHORIZED**",
            "- Physical result collected: **NO**",
        ]

        for line in requiredBlankRecordLines {
            #expect(runbook.contains(line))
        }
    }

    @Test("future GO must update package authority and runbook in one accepted change")
    func runbookPinsJointGoTransition() throws {
        let runbook = try physicalRunbook()

        #expect(
            runbook.contains(
                "replace this section in the same acceptance change that flips the status above to `GO`"
            )
        )
        #expect(
            runbook.contains(
                "a deliberate package-owned `PassiveBluetoothExperimentOneFieldExecutionGate` GO state"
            )
        )
    }
}
