import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture stationary field runbook current authority")
struct TuyaStationaryRunbookCurrentAuthoritySourceTests {
    @Test("secure-link procedure requires four fresh package-owned windows and explicit confirmation")
    func secureLinkRunbookCannotRegressToHistoricalHintAuthority() throws {
        let runbook = try readRepositoryFile("docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md")

        #expect(runbook.contains("OFF1 → ON1 → OFF2 → ON2"))
        #expect(runbook.contains("fresh CoreBluetooth manager"))
        #expect(runbook.contains("exactly one repeatable full CoreBluetooth UUID"))
        #expect(runbook.contains("Confirm correlated Bluetooth target"))
        #expect(runbook.contains("historical C7D09A22 UUID"))
        #expect(runbook.contains("descriptive only"))
        #expect(runbook.contains("cannot mint target authority"))
        #expect(runbook.contains("rawFD50BytesCaptured=false"))
        #expect(runbook.contains("dpQueriesSent=false"))
        #expect(runbook.contains("dpCommandsSent=false"))

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

    @Test("field installer cannot instruct an obsolete two-window target flow")
    func fieldInstallerPrintsCurrentFourWindowAuthority() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")

        #expect(installer.contains("OFF1 → ON1 → OFF2 → ON2"))
        #expect(installer.contains("every window must reach scan liveness"))
        #expect(installer.contains("exactly one repeatable full CoreBluetooth UUID"))
        #expect(installer.contains("Confirm correlated Bluetooth target"))
        #expect(installer.contains("Historical UUID/name/RSSI/FD50/Tuya hints cannot override the package result"))
        #expect(installer.contains("Tuya's SDK remains the sole authenticated BLE owner"))
        #expect(installer.contains("Nembra sends no DP query or command"))

        #expect(!installer.contains("run the scooter-OFF baseline, power it ON, select the authoritative target"))
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