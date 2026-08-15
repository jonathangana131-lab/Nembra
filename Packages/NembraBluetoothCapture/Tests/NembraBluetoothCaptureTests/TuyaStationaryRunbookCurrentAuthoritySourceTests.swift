import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture stationary field runbook current authority")
struct TuyaStationaryRunbookCurrentAuthoritySourceTests {
    @Test("current procedure requires four fresh package-owned windows, literal confirmation, and structured-only evidence")
    func currentProcedureCannotRegressToHistoricalHintOrRawByteAuthority() throws {
        let runbook = try readRepositoryFile("docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md")

        #expect(runbook.contains("OFF1 → ON1 → OFF2 → ON2"))
        #expect(runbook.contains("package-owned, fresh-manager"))
        #expect(runbook.contains("Exactly one repeatable full CoreBluetooth UUID") || runbook.contains("exactly one repeatable full CoreBluetooth UUID"))
        #expect(runbook.contains("Confirm this scooter signal"))
        #expect(runbook.contains("historical CoreBluetooth UUID"))
        #expect(runbook.contains("descriptive capture-local evidence only"))
        #expect(runbook.contains("cannot mint target authority"))
        #expect(runbook.contains("There is no hint-based override"))
        #expect(runbook.contains("Nembra must not open a second independent CoreBluetooth connection"))
        #expect(runbook.contains("Structured `dpsUpdate` observations are application-level evidence only"))
        #expect(runbook.contains("do **not** establish raw authenticated FD50/ATT bytes"))
        #expect(runbook.contains("rawFD50BytesCaptured=false"))
        #expect(runbook.contains("dpQueriesSent=false"))
        #expect(runbook.contains("dpCommandsSent=false"))

        #expect(!runbook.contains("Confirm correlated Bluetooth target"))
        #expect(!runbook.contains("use the best accepted evidence"))
        #expect(!runbook.contains("known first-capture peripheral, FD50 advertisement evidence"))
        #expect(!runbook.contains("combined FD50 + Tuya-company evidence"))
        #expect(!runbook.contains("OFF baseline then ON correlation"))
    }

    @Test("one current procedure owns execution authority and remains explicit NO-GO")
    func currentProcedureIsSingleFailClosedAuthority() throws {
        let runbook = try readRepositoryFile("docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md")

        #expect(runbook.contains("PROCEDURE_ID: `ES80-AUTHENTICATED-STATIONARY-v1`"))
        #expect(runbook.contains("single current next-physical-procedure authority"))
        #expect(runbook.contains("Older passive/authenticated gate documents are historical only and cannot authorize execution"))
        #expect(runbook.contains("physical secure-link experiment is **NO-GO**"))
        #expect(runbook.contains("Accepted exact source commit: **NOT YET AUTHORIZED**"))
        #expect(runbook.contains("Accepted signed field build / install evidence: **NOT YET AUTHORIZED**"))
        #expect(runbook.contains("Accepted visual/runtime exact-head subject: **NOT YET AUTHORIZED**"))
        #expect(runbook.contains("Physical execution state: **NO-GO / NOT YET AUTHORIZED**"))
        #expect(runbook.contains("Only a final composed exact build may replace the NOT YET AUTHORIZED fields and change this document to GO"))
    }

    @Test("durable routing follows live GitHub and cannot revive a retired flagship")
    func durableRoutingCannotFreezeStaleCurrentAuthority() throws {
        let pointer = try readRepositoryFile("CAPTURE_HARD_FREEZE_ACTIVE.md")

        #expect(pointer.contains("**Live GitHub is authoritative.**"))
        #expect(pointer.contains("feature: Nembra Capture / authenticated stationary ES80 physical truth"))
        #expect(pointer.contains("accepted public-software checkpoint: PR #3316 exact `ba615954b2afdf2e011f485c0ecbc9152614d21e`"))
        #expect(pointer.contains("software evidence only"))
        #expect(pointer.contains("signed/private-field closure must be discovered from live GitHub"))
        #expect(pointer.contains("docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md"))
        #expect(pointer.contains("Queued/running/skipped/cancelled/ancestor workflow results are non-evidence."))
        #expect(pointer.contains("This pointer cannot mint GO."))
        #expect(pointer.contains("physical status: **NO-GO / DO NOT INSTALL / DO NOT SCAN / DO NOT RUN BLE / DO NOT RIDE**"))

        #expect(!pointer.contains("PR #2178"))
        #expect(!pointer.contains("df30de17"))
        #expect(!pointer.contains("integration/v14-capture-final-stationary-convergence-sol"))
        #expect(!pointer.contains("31366062131"))
        #expect(!pointer.contains("31366062142"))
        #expect(!pointer.contains("Always re-read live PR #"))
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