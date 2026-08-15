import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture stationary field runbook current authority")
struct TuyaStationaryRunbookCurrentAuthoritySourceTests {
    @Test("secure-link procedure requires four fresh package-owned windows, literal confirmation, and structured-only evidence")
    func secureLinkRunbookCannotRegressToHistoricalHintOrRawByteAuthority() throws {
        let runbook = try readRepositoryFile("docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md")

        #expect(runbook.contains("OFF1 → ON1 → OFF2 → ON2"))
        #expect(runbook.contains("package-owned, fresh-manager"))
        #expect(runbook.contains("Exactly one repeatable full CoreBluetooth UUID") || runbook.contains("exactly one repeatable full CoreBluetooth UUID"))
        #expect(runbook.contains("Confirm this scooter signal"))
        #expect(runbook.contains("historical CoreBluetooth UUID"))
        #expect(runbook.contains("descriptive capture-local evidence only"))
        #expect(runbook.contains("cannot mint target authority"))
        #expect(runbook.contains("Nembra must not open a second independent CoreBluetooth connection"))
        #expect(runbook.contains("Structured `dpsUpdate` observations are application-level evidence only"))
        #expect(runbook.contains("do **not** establish raw authenticated FD50/ATT bytes"))
        #expect(runbook.contains("rawFD50BytesCaptured=false"))
        #expect(runbook.contains("dpQueriesSent=false"))
        #expect(runbook.contains("dpCommandsSent=false"))

        #expect(!runbook.contains("Confirm correlated Bluetooth target"))
        #expect(!runbook.contains("use the best accepted evidence"))
        #expect(!runbook.contains("known first-capture peripheral, FD50 advertisement evidence"))
        #expect(!runbook.contains("OFF baseline then ON correlation"))
    }

    @Test("private SDK provisioning pins dependency and target-correlation provenance")
    func privateProvisioningCannotFloatSDKOrRestoreTwoWindowAuthority() throws {
        let provisioning = try readRepositoryFile("docs/CAPTURE_TUYA_OFFICIAL_SDK_PROVISIONING.md")

        #expect(provisioning.contains("ThingSmartHomeKit` **7.8.0**"))
        #expect(provisioning.contains("ThingSmartBusinessExtensionKit` **7.8.0**"))
        #expect(provisioning.contains("pod install --repo-update"))
        #expect(provisioning.contains("ResolvedTuyaDependencyProvenance.txt"))
        #expect(provisioning.contains("OFF1 → ON1 → OFF2 → ON2"))
        #expect(provisioning.contains("explicitly confirm"))
        #expect(provisioning.contains("historical C7D09A22 UUID"))
        #expect(provisioning.contains("descriptive only"))
        #expect(provisioning.contains("rawFD50BytesCaptured: false"))
        #expect(provisioning.contains("dpQueriesSent: false"))
        #expect(provisioning.contains("dpCommandsSent: false"))

        #expect(!provisioning.contains("pins the SmartLife 7.8.x line"))
        #expect(!provisioning.contains("OFF baseline then ON correlation"))
    }

    @Test("legacy secure-link runbook is a tombstone and cannot remain executable")
    func legacySecureLinkRunbookCannotCarryStalePhysicalInstructions() throws {
        let legacy = try readRepositoryFile("docs/CAPTURE_NEXT_TUYA_SECURE_LINK_TEST.md")

        #expect(legacy.contains("DEPRECATED / DO NOT USE"))
        #expect(legacy.contains("docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md"))
        #expect(legacy.contains("OFF1 → ON1 → OFF2 → ON2"))
        #expect(legacy.contains("no historical UUID/name/RSSI/FD50/Tuya-hint fallback authority"))
        #expect(legacy.contains("PHYSICAL STATUS: NO-GO"))

        #expect(!legacy.contains("With scooter OFF, collect a short local Bluetooth baseline"))
        #expect(!legacy.contains("previous CoreBluetooth UUID plus FD50 / Tuya company-ID / power-on-delta evidence"))
        #expect(!legacy.contains("NEMBRA_TUYA_APP_KEY"))
        #expect(!legacy.contains("NEMBRA_TUYA_APP_SECRET"))
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
