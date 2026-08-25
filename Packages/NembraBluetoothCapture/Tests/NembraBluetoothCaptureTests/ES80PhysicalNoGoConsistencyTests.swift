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

    @Test("retired passive runbook cannot authorize the current physical experiment")
    func retiredPassiveRunbookRemainsATombstone() throws {
        let retired = try repositoryFile("docs/ES80_PHYSICAL_CAPTURE_RUNBOOK.md")

        #expect(retired.contains("RETIRED V14 LANE"))
        #expect(retired.contains("Status: **RETIRED / NON-AUTHORITATIVE / PHYSICAL NO-GO.**"))
        #expect(retired.contains("It is **not** the current physical-procedure gate"))
        #expect(retired.contains("ES80-AUTHENTICATED-STATIONARY-v1"))
        #expect(retired.contains("docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md"))
        #expect(retired.contains("must not be edited from NO-GO to GO for the current Capture product"))

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

    @Test("secure-link build provenance matches executable OFF1 admission")
    func secureLinkBuildProvenanceMatchesOFF1Gate() throws {
        let runbook = try repositoryFile("docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md")

        #expect(runbook.contains("`NembraCaptureBuildIdentity.isAuthoritativeFieldBuild` is a mandatory fail-closed build-provenance prerequisite"))
        #expect(runbook.contains("shipping `startBaseline()` rejects OFF1 before correlation when it is false"))
        #expect(runbook.contains("It is necessary but not sufficient field authority."))
        #expect(!runbook.contains("is not an OFF1 gate"))
        #expect(!runbook.contains("without treating the legacy authoritative-build Boolean as field authority"))
    }

    @Test("current authenticated gate requires repeated late application evidence and forty-five seconds")
    func currentRunbookAndPreflightAgreeOnAuthenticatedGate() throws {
        let runbook = try repositoryFile("docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md")
        let thirtySecondsInNanoseconds: UInt64 = 30_000_000_000
        let fortyFiveSecondsInNanoseconds: UInt64 = 45_000_000_000

        #expect(TuyaAuthenticatedReadOnlyPreflight.minimumAuthenticatedApplicationPayloadCount == 2)
        #expect(
            TuyaAuthenticatedReadOnlyPreflight.minimumPostAuthenticationPayloadSurvivalNanoseconds
                == thirtySecondsInNanoseconds
        )
        #expect(
            TuyaAuthenticatedReadOnlyPreflight.minimumAuthenticatedConnectionNanoseconds
                == fortyFiveSecondsInNanoseconds
        )
        #expect(runbook.contains("at least two genuine non-empty same-generation `ThingSmartDeviceDelegate.dpsUpdate` callbacks"))
        #expect(runbook.contains("latest application evidence occurs at least 30 seconds after SDK authentication"))
        #expect(runbook.contains("at least 45 seconds of canonical authenticated observation"))
        #expect(runbook.contains("The app must seal the canonical ready prefix before presenting success."))
    }

    @Test("supporting physical documents cannot weaken executable authenticated readiness")
    func supportingPhysicalDocsMatchCanonicalGate() throws {
        let physicalTruth = try repositoryFile("docs/ES80_PHYSICAL_TRUTH_C7D09A22.md")
        let stationaryGate = try repositoryFile("docs/ES80_AUTHENTICATED_STATIONARY_GATE_V14.md")

        #expect(physicalTruth.contains("at least **2** genuine, non-empty application updates"))
        #expect(physicalTruth.contains("at least **30.0 seconds after authentication**"))
        #expect(physicalTruth.contains("at least **45.0 seconds after authentication**"))
        #expect(physicalTruth.contains("produces only one application callback"))
        #expect(!physicalTruth.contains("acceptance boundary is strictly `>30.0 s` plus real notify payload evidence"))

        #expect(stationaryGate.contains("at least **two** genuine, non-empty application payloads"))
        #expect(stationaryGate.contains("at least **30 seconds after authentication**"))
        #expect(stationaryGate.contains("at least **45 seconds of accepted authenticated continuity after authentication**"))
        #expect(stationaryGate.contains("one/bootstrap-only application payload"))
        #expect(!stationaryGate.contains("at least **one genuine non-empty application notification payload**"))
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
        let retired = try repositoryFile("docs/ES80_PHYSICAL_CAPTURE_RUNBOOK.md")
        let runbook = try repositoryFile("docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md")

        #expect(
            retired.contains(
                "Queued, running, skipped, ancestor-green, package-only, Simulator-only, source-review-only, self-described, or historical passive evidence cannot authorize that experiment."
            )
        )
        #expect(runbook.contains("The historical CoreBluetooth UUID is **descriptive capture-local evidence only**."))
        #expect(runbook.contains("Nembra sends no scooter DP query/control command"))
        #expect(runbook.contains("opens no second CoreBluetooth connection"))
        #expect(runbook.contains("rawFD50BytesCaptured=false"))
        #expect(runbook.contains("dpQueriesSent=false"))
        #expect(runbook.contains("dpCommandsSent=false"))
    }
}
