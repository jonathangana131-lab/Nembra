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

    @Test("historical passive package gate cannot authorize the current physical experiment")
    func historicalPassivePackageGateRemainsNoGo() throws {
        let runbook = try repositoryFile("docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md")

        #expect(runbook.contains("PROCEDURE_ID: `ES80-AUTHENTICATED-STATIONARY-v1`"))
        #expect(runbook.contains("the physical secure-link experiment is **NO-GO**"))
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

    @Test("current runbook preserves exact build provenance as necessary but insufficient OFF1 authority")
    func currentRunbookPreservesBuildGate() throws {
        let runbook = try repositoryFile("docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md")

        #expect(runbook.contains("`NembraCaptureBuildIdentity.isAuthoritativeFieldBuild` is a **necessary OFF1 build-provenance prerequisite, but never sufficient field authority by itself**"))
        #expect(runbook.contains("require `NembraCaptureBuildIdentity.isAuthoritativeFieldBuild == true` as a necessary build-provenance prerequisite without treating it as sufficient OFF1 authority"))
        #expect(runbook.contains("package-owned one-time signed authorization session is freshly `.armed`"))
        #expect(!runbook.contains("is not an OFF1 gate"))
        #expect(!runbook.contains("without treating the legacy authoritative-build Boolean as field authority"))
    }

    @Test("current authenticated procedure matches the canonical 2 / 30 / 45 gate")
    func currentRunbookAndPreflightAgreeOnAuthenticatedGate() throws {
        let runbook = try repositoryFile("docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md")

        #expect(TuyaAuthenticatedReadOnlyPreflight.minimumAuthenticatedApplicationPayloadCount == 2)
        #expect(
            TuyaAuthenticatedReadOnlyPreflight.minimumPostAuthenticationPayloadSurvivalNanoseconds
                == 30_000_000_000
        )
        #expect(
            TuyaAuthenticatedReadOnlyPreflight.minimumAuthenticatedConnectionNanoseconds
                == 45_000_000_000
        )
        #expect(runbook.contains("at least two genuine non-empty same-generation `ThingSmartDeviceDelegate.dpsUpdate` callbacks"))
        #expect(runbook.contains("latest application evidence occurs at least 30 seconds after SDK authentication"))
        #expect(runbook.contains("at least 45 seconds of canonical authenticated observation"))
        #expect(runbook.contains("The app must seal the canonical ready prefix before presenting success."))
    }

    @Test("physical handoff documents cannot weaken shipping authenticated readiness")
    func physicalHandoffDocumentsMatchShippingPreflight() throws {
        let physicalTruth = try repositoryFile("docs/ES80_PHYSICAL_TRUTH_C7D09A22.md")
        let stationaryGate = try repositoryFile("docs/ES80_AUTHENTICATED_STATIONARY_GATE_V14.md")

        #expect(TuyaAuthenticatedReadOnlyPreflight.minimumAuthenticatedApplicationPayloadCount == 2)
        #expect(
            TuyaAuthenticatedReadOnlyPreflight.minimumPostAuthenticationPayloadSurvivalNanoseconds
                == 30_000_000_000
        )
        #expect(
            TuyaAuthenticatedReadOnlyPreflight.minimumAuthenticatedConnectionNanoseconds
                == 45_000_000_000
        )

        #expect(physicalTruth.contains("at least **2** genuine, non-empty application updates"))
        #expect(physicalTruth.contains("at least **30.0 seconds after authentication**"))
        #expect(physicalTruth.contains("at least **45.0 seconds after authentication**"))
        #expect(physicalTruth.contains("produces only one application callback"))
        #expect(physicalTruth.contains("intentionally no weaker than shipping `TuyaAuthenticatedReadOnlyPreflight`"))
        #expect(!physicalTruth.contains("acceptance boundary is strictly `>30.0 s` plus real notify payload evidence"))

        #expect(stationaryGate.contains("at least **two** admitted non-empty application updates"))
        #expect(stationaryGate.contains("at least **30 seconds after authentication**"))
        #expect(stationaryGate.contains("at least **45 seconds** of accepted authenticated observation continuity"))
        #expect(stationaryGate.contains("Older one-payload / merely-`>30 s` wording is superseded"))
        #expect(stationaryGate.contains("One bootstrap/state replay"))
    }

    @Test("current stationary gate keeps structured SDK evidence separate from raw FD50")
    func currentStationaryGateSeparatesStructuredAndRawEvidence() throws {
        let stationaryGate = try repositoryFile("docs/ES80_AUTHENTICATED_STATIONARY_GATE_V14.md")

        #expect(stationaryGate.contains("`ThingSmartDeviceDelegate.dpsUpdate`"))
        #expect(stationaryGate.contains("structured SDK application evidence"))
        #expect(stationaryGate.contains("does **not** establish raw FD50/ATT bytes"))
        #expect(stationaryGate.contains("Raw byte-exact authenticated FD50 evidence remains a separate unresolved evidence rung"))
        #expect(!stationaryGate.contains("The original authenticated raw-evidence experiment may be classified `PASS`"))
        #expect(!stationaryGate.contains("authenticated raw FD50 evidence-ledger donor"))
    }

    @Test("current physical procedure remains explicitly NO-GO")
    func currentSecureLinkProcedureRemainsNoGo() throws {
        let runbook = try repositoryFile("docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md")
        let stationaryGate = try repositoryFile("docs/ES80_AUTHENTICATED_STATIONARY_GATE_V14.md")

        #expect(runbook.contains("PROCEDURE_ID: `ES80-AUTHENTICATED-STATIONARY-v1`"))
        #expect(runbook.contains("Until all applicable software/private-device prerequisites are true"))
        #expect(runbook.contains("the repository explicitly records `GO`"))
        #expect(runbook.contains("the physical secure-link experiment is **NO-GO**"))
        #expect(runbook.contains("Smallest physical test — only after repository status explicitly flips to GO"))
        #expect(runbook.contains("**Do not repeat the completed 17-step ride capture.**"))
        #expect(stationaryGate.contains("Status: **NO-GO — DO NOT RUN THE NEXT PHYSICAL SESSION YET.**"))
    }

    @Test("NO-GO cannot be bypassed by simulator, stale evidence, or causal inference")
    func currentRunbookPinsEvidenceBoundaries() throws {
        let pointer = try repositoryFile("CAPTURE_HARD_FREEZE_ACTIVE.md")
        let runbook = try repositoryFile("docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md")
        let stationaryGate = try repositoryFile("docs/ES80_AUTHENTICATED_STATIONARY_GATE_V14.md")

        #expect(pointer.contains("Queued, running, skipped, cancelled, ancestor-green, package-only, Simulator-only, source-review-only"))
        #expect(pointer.contains("not final product/physical acceptance"))
        #expect(runbook.contains("The historical CoreBluetooth UUID is **descriptive capture-local evidence only**."))
        #expect(runbook.contains("while no application characteristic-value frames were observed; C7D09A22 does not establish the cause of that disconnect cadence"))
        #expect(!runbook.contains("disconnected around 30 seconds because the required Tuya application session was not established"))
        #expect(runbook.contains("Nembra sends no scooter DP query/control command"))
        #expect(runbook.contains("opens no second CoreBluetooth connection"))
        #expect(runbook.contains("rawFD50BytesCaptured=false"))
        #expect(runbook.contains("dpQueriesSent=false"))
        #expect(runbook.contains("dpCommandsSent=false"))
        #expect(stationaryGate.contains("Queued, running, skipped, ancestor-green, package-only, Simulator-only, source-review-only, or historical evidence cannot authorize the physical session."))
    }
}
