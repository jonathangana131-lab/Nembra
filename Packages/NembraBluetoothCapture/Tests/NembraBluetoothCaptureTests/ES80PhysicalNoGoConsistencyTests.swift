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

    @Test("historical next-gate documents cannot compete with the single current procedure")
    func historicalNextGateDocumentsAreExplicitlySuperseded() throws {
        let physicalTruth = try repositoryFile("docs/ES80_PHYSICAL_TRUTH_C7D09A22.md")
        let historicalGate = try repositoryFile("docs/ES80_AUTHENTICATED_STATIONARY_GATE_V14.md")

        #expect(physicalTruth.contains("Historical next-gate note — superseded for execution"))
        #expect(physicalTruth.contains("SUPERSEDED / NON-AUTHORITATIVE FOR EXECUTION"))
        #expect(physicalTruth.contains("docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md"))
        #expect(physicalTruth.contains("structured SmartLife SDK `dpsUpdate` observations are application-level evidence"))
        #expect(physicalTruth.contains("must not be relabeled as byte-exact FD50/ATT notification evidence or telemetry semantics"))

        #expect(historicalGate.contains("Status: **SUPERSEDED / NON-AUTHORITATIVE FOR EXECUTION / PHYSICAL NO-GO.**"))
        #expect(historicalGate.contains("Current procedure authority: `docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md`"))
        #expect(historicalGate.contains("Only `docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md` may define the current next physical procedure."))
        #expect(historicalGate.contains("may not independently flip to GO/PASS"))
        #expect(historicalGate.contains("structured SDK `dpsUpdate` values as byte-exact FD50/ATT notification bytes"))
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
        #expect(runbook.contains("Exactly one repeatable full CoreBluetooth UUID") || runbook.contains("exactly one repeatable full CoreBluetooth UUID"))
        #expect(runbook.contains("Confirm this scooter signal"))
        #expect(runbook.contains("There is no hint-based override."))
    }

    @Test("operator correlation recipe uses the literal shipping controls")
    func currentRunbookMatchesShippingCorrelationControls() throws {
        let runbook = try repositoryFile("docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md")
        let app = try repositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        for control in [
            "Start with scooter OFF",
            "Finish OFF1",
            "Start ON1",
            "Finish ON1",
            "Start OFF2",
            "Finish OFF2",
            "Start ON2",
            "Finish ON2",
            "Confirm this scooter signal",
        ] {
            #expect(runbook.contains("`\(control)`"))
        }

        #expect(!runbook.contains("Confirm correlated Bluetooth target"))
        #expect(!runbook.contains("seal OFF1"))
        #expect(!runbook.contains("seal ON1"))
        #expect(!runbook.contains("seal OFF2"))
        #expect(!runbook.contains("seal ON2"))

        #expect(app.contains("Label(\"Start with scooter OFF\""))
        #expect(app.contains("Label(\"Start \\(test.correlationWindowLabel)\""))
        #expect(app.contains("Label(\"Finish \\(test.correlationWindowLabel)\""))
        #expect(app.contains("Label(\"Confirm this scooter signal\""))
    }

    @Test("current account lease does not overclaim home identity continuity")
    func currentRunbookMatchesAccountAndDeviceLeaseAuthority() throws {
        let runbook = try repositoryFile("docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md")

        #expect(runbook.contains("complete enumeration of the current SDK account's homes"))
        #expect(runbook.contains("same current account UID and exact device ID"))
        #expect(runbook.contains("does not currently retain a home-ID continuity lease"))
        #expect(!runbook.contains("same current SDK account/home"))
        #expect(!runbook.contains("current account/home"))
    }

    @Test("current authenticated readiness pins repeated payload, survival, stability, and retirement horizons")
    func currentRunbookAndPreflightAgreeOnAuthenticatedReadiness() throws {
        let runbook = try repositoryFile("docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md")

        #expect(TuyaAuthenticatedReadOnlyPreflight.minimumAuthenticatedApplicationPayloadCount == 2)
        #expect(TuyaAuthenticatedReadOnlyPreflight.minimumPostAuthenticationPayloadSurvivalNanoseconds == 30_000_000_000)
        #expect(TuyaAuthenticatedReadOnlyPreflight.minimumAuthenticatedConnectionNanoseconds == 45_000_000_000)
        #expect(TuyaAuthenticatedReadOnlyPreflight.maximumIncompleteObservationNanoseconds == 60_000_000_000)

        #expect(runbook.contains("at least **two** genuine non-empty same-generation application observations"))
        #expect(runbook.contains("at least **30 seconds after authentication**"))
        #expect(runbook.contains("at least **45 seconds of canonical authenticated observation**"))
        #expect(runbook.contains("**60 seconds after authentication** without earning canonical readiness is retired fail-closed"))
        #expect(runbook.contains("The app must seal the canonical ready prefix before presenting success."))
    }

    @Test("field authority requires exact source attribution and non-forgeable ordered delivery chronology")
    func currentRunbookPinsApplicationEvidenceCustody() throws {
        let runbook = try repositoryFile("docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md")

        #expect(runbook.contains("fail-closed source-attributed to the exact selected SmartLife device ID"))
        #expect(runbook.contains("Nil/wrong-device source cannot mint application chronology or acceptance"))
        #expect(runbook.contains("non-caller-mintable, one-shot/order-preserving admission"))
        #expect(runbook.contains("one callback cannot be replayed as repeated evidence"))
        #expect(runbook.contains("watchdog cannot overtake an already-delivered pending prefix"))
        #expect(runbook.contains("Independent task execution order is not delivery-order proof."))
        #expect(runbook.contains("without leaving tokenless `.observing` UI"))
    }

    @Test("current physical procedure remains explicitly NO-GO")
    func currentSecureLinkProcedureRemainsNoGo() throws {
        let runbook = try repositoryFile("docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md")

        #expect(runbook.contains("PROCEDURE_ID: `ES80-AUTHENTICATED-STATIONARY-v1`"))
        #expect(runbook.contains("single current next-physical-procedure authority"))
        #expect(runbook.contains("Until all applicable software/private-device prerequisites are true"))
        #expect(runbook.contains("repository explicitly records `GO`"))
        #expect(runbook.contains("the physical secure-link experiment is **NO-GO**"))
        #expect(runbook.contains("Smallest physical test — only after repository status explicitly flips to GO"))
        #expect(runbook.contains("**Do not repeat the completed 17-step ride capture.**"))
        #expect(runbook.contains("Accepted exact source commit: **NOT YET AUTHORIZED**"))
        #expect(runbook.contains("Accepted evidence-admission/source-attribution subject: **NOT YET AUTHORIZED**"))
        #expect(runbook.contains("Accepted administrator-trusted signing/bootstrap subject: **NOT YET AUTHORIZED**"))
        #expect(runbook.contains("Physical execution state: **NO-GO / NOT YET AUTHORIZED**"))
    }

    @Test("NO-GO cannot be bypassed by simulator, stale evidence, candidate bootstrap, or command authority")
    func currentRunbookPinsEvidenceBoundaries() throws {
        let retired = try repositoryFile("docs/ES80_PHYSICAL_CAPTURE_RUNBOOK.md")
        let runbook = try repositoryFile("docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md")

        #expect(
            retired.contains(
                "Queued, running, skipped, ancestor-green, package-only, Simulator-only, source-review-only, self-described, or historical passive evidence cannot authorize that experiment."
            )
        )
        #expect(runbook.contains("historical CoreBluetooth UUID is **descriptive capture-local evidence only**"))
        #expect(runbook.contains("Nembra sends no scooter DP query/control command"))
        #expect(runbook.contains("opens no second CoreBluetooth connection"))
        #expect(runbook.contains("rawFD50BytesCaptured=false"))
        #expect(runbook.contains("dpQueriesSent=false"))
        #expect(runbook.contains("dpCommandsSent=false"))
        #expect(runbook.contains("Candidate-controlled PR bytes may not become their own privileged/root trust anchor."))
        #expect(runbook.contains("validation-only oracle"))
        #expect(runbook.contains("candidate-controlled bootstrap"))
    }
}
