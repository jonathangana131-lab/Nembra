import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture stationary field runbook current authority")
struct TuyaStationaryRunbookCurrentAuthoritySourceTests {
    @Test("canonical stationary runbook cannot regress to historical target authority")
    func secureLinkRunbookCannotRegressToHistoricalHintAuthority() throws {
        let runbook = try readRepositoryFile("docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md")

        #expect(runbook.contains("PROCEDURE_ID: `ES80-AUTHENTICATED-STATIONARY-v1`"))
        #expect(runbook.contains("Status: **PHYSICAL NO-GO.**"))
        #expect(runbook.contains("single current next-physical-procedure authority"))
        #expect(runbook.contains("OFF1 → ON1 → OFF2 → ON2"))
        #expect(runbook.contains("package-owned, fresh-manager"))
        #expect(
            runbook.contains("Exactly one repeatable full CoreBluetooth UUID")
                || runbook.contains("exactly one repeatable full CoreBluetooth UUID")
        )
        #expect(runbook.contains("`Confirm this scooter signal`"))
        #expect(runbook.contains("historical CoreBluetooth UUID is **descriptive capture-local evidence only**"))
        #expect(runbook.contains("There is no hint-based override."))
        #expect(runbook.contains("Nembra must not open a second independent CoreBluetooth connection"))

        #expect(!runbook.contains("Confirm correlated Bluetooth target"))
        #expect(!runbook.contains("use the best accepted evidence"))
        #expect(!runbook.contains("known first-capture peripheral, FD50 advertisement evidence"))
        #expect(!runbook.contains("OFF baseline then ON correlation"))
    }

    @Test("current stationary runbook keeps structured observations below telemetry and raw-byte authority")
    func supportedSDKObservationBoundaryRemainsReadOnlyAndOpaque() throws {
        let runbook = try readRepositoryFile("docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md")

        #expect(runbook.contains("Structured `dpsUpdate` observations are application-level evidence only."))
        #expect(runbook.contains("do **not** establish raw authenticated FD50/ATT bytes"))
        #expect(runbook.contains("at least **two** genuine non-empty same-generation application observations"))
        #expect(runbook.contains("at least **30 seconds after authentication**"))
        #expect(runbook.contains("at least **45 seconds of canonical authenticated observation**"))
        #expect(runbook.contains("**60 seconds after authentication** without earning canonical readiness is retired fail-closed"))
        #expect(runbook.contains("rawFD50BytesCaptured=false"))
        #expect(runbook.contains("dpQueriesSent=false"))
        #expect(runbook.contains("dpCommandsSent=false"))
        #expect(runbook.contains("sends no scooter DP query/control command and opens no second CoreBluetooth connection"))
    }

    @Test("durable Capture routing points to the same current procedure without minting GO")
    func durableAuthorityPointerAgreesWithCurrentRunbook() throws {
        let pointer = try readRepositoryFile("CAPTURE_HARD_FREEZE_ACTIVE.md")

        #expect(pointer.contains("feature: Nembra Capture / authenticated stationary ES80 physical truth"))
        #expect(pointer.contains("docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md"))
        #expect(pointer.contains("The canonical current physical procedure is:"))
        #expect(pointer.contains("OFF1 → ON1 → OFF2 → ON2"))
        #expect(pointer.contains("physical status: **NO-GO / DO NOT SCAN / DO NOT RUN / DO NOT REPEAT THE OLD 17-STEP RIDE**"))
        #expect(pointer.contains("Only the final composed exact build plus the required private intended-device/runtime gates can authorize the next physical experiment."))
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
