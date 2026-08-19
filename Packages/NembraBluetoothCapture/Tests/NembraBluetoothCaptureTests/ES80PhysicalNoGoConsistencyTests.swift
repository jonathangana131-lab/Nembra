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

    private func repositoryFile(_ relativePath: String) throws -> String {
        try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    @Test("removed passive runbook cannot authorize the current physical experiment")
    func removedPassiveRunbookCannotReplaceCanonicalAuthority() throws {
        let removedRunbook = repositoryRoot
            .appendingPathComponent("docs/ES80_PHYSICAL_CAPTURE_RUNBOOK.md")
        let current = try repositoryFile("docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md")

        #expect(!FileManager.default.fileExists(atPath: removedRunbook.path))
        #expect(current.contains("PROCEDURE_ID: `ES80-AUTHENTICATED-STATIONARY-v1`"))
        #expect(current.contains("Current target authority is earned only by one package-owned, fresh-manager"))
        #expect(current.contains("The historical CoreBluetooth UUID is **descriptive capture-local evidence only**."))
        #expect(current.contains("Until all applicable software/private-device prerequisites are true"))
        #expect(current.contains("the repository explicitly records `GO`"))
        #expect(current.contains("the physical secure-link experiment is **NO-GO**"))

        // The historical passive package gate is still deliberately unable to authorize a run.
        // Its NO-GO state is not the current authenticated-stationary procedure contract.
        #expect(
            PassiveBluetoothExperimentOneFieldExecutionGate.status
                == .noGo(.finalComposedBuildNotAuthorized)
        )
        #expect(!PassiveBluetoothExperimentOneFieldExecutionGate.permitsPhysicalProcedure)
        #expect(PassiveBluetoothExperimentOneFieldExecutionGate.recipeID == .es80FingerprintV1)
    }

    @Test("current runbook delegates correlation duration to the accepted package policy")
    func currentRunbookAndPackageAgreeOnCorrelationAuthority() throws {
        let runbook = try repositoryFile("docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md")
        let tenSecondsInNanoseconds: UInt64 = 10_000_000_000

        #expect(
            PassiveBluetoothExperimentOneCapturePolicy
                .minimumPowerCycleWindowDurationNanoseconds
                == tenSecondsInNanoseconds
        )
        #expect(runbook.contains("OFF1 → ON1 → OFF2 → ON2"))
        #expect(runbook.contains("accepted receipt-bounded minimum duration"))
        #expect(runbook.contains("elapsed UI time is not evidence"))
        #expect(runbook.contains("exactly one repeatable full CoreBluetooth UUID"))
        #expect(runbook.contains("Confirm correlated Bluetooth target"))
        #expect(runbook.contains("There is no hint-based override."))
    }

    @Test("current authenticated evidence requires two callbacks, thirty seconds, and forty-five seconds")
    func currentRunbookAndPreflightAgreeOnAuthenticatedEvidenceThresholds() throws {
        let runbook = try repositoryFile("docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md")
        let thirtySecondsInNanoseconds: UInt64 = 30_000_000_000
        let fortyFiveSecondsInNanoseconds: UInt64 = 45_000_000_000

        #expect(
            TuyaAuthenticatedReadOnlyPreflight
                .minimumAuthenticatedApplicationPayloadCount
                == 2
        )
        #expect(
            TuyaAuthenticatedReadOnlyPreflight
                .minimumPostAuthenticationPayloadSurvivalNanoseconds
                == thirtySecondsInNanoseconds
        )
        #expect(
            TuyaAuthenticatedReadOnlyPreflight.minimumAuthenticatedConnectionNanoseconds
                == fortyFiveSecondsInNanoseconds
        )
        #expect(runbook.contains("at least 45 seconds of canonical authenticated observation"))
        #expect(runbook.contains("at least two genuine non-empty same-generation `ThingSmartDeviceDelegate.dpsUpdate` callbacks"))
        #expect(runbook.contains("latest application evidence occurs at least 30 seconds after SDK authentication"))
        #expect(runbook.contains("The app must seal the canonical ready prefix before presenting success."))
    }

    @Test("current physical procedure remains explicitly NO-GO")
    func currentSecureLinkProcedureRemainsNoGo() throws {
        let runbook = try repositoryFile("docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md")

        #expect(runbook.contains("PROCEDURE_ID: `ES80-AUTHENTICATED-STATIONARY-v1`"))
        #expect(runbook.contains("Until all applicable software/private-device prerequisites are true"))
        #expect(runbook.contains("the repository explicitly records `GO`"))
        #expect(runbook.contains("the physical secure-link experiment is **NO-GO**"))
        #expect(runbook.contains("Smallest physical test — only after repository status explicitly flips to GO"))
        #expect(runbook.contains("**Do not repeat the completed 17-step ride capture.**"))
    }

    @Test("NO-GO cannot be bypassed by simulator or stale physical evidence")
    func currentRunbookPinsEvidenceBoundaries() throws {
        let runbook = try repositoryFile("docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md")

        #expect(runbook.contains("The historical CoreBluetooth UUID is **descriptive capture-local evidence only**."))
        #expect(runbook.contains("Exact-head standalone Xcode 27 / iPhone-12-class Simulator gates are terminal green on the unchanged final candidate."))
        #expect(runbook.contains("Public no-secret CI is software evidence only; it cannot prove the privately provisioned SDK path or physical scooter behavior."))
        #expect(runbook.contains("the physical secure-link experiment is **NO-GO**"))
        #expect(runbook.contains("Nembra sends no scooter DP query/control command"))
        #expect(runbook.contains("opens no second CoreBluetooth connection"))
        #expect(runbook.contains("rawFD50BytesCaptured=false"))
        #expect(runbook.contains("dpQueriesSent=false"))
        #expect(runbook.contains("dpCommandsSent=false"))
    }
}
