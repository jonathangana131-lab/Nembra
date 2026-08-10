import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture field installer procedure authority")
struct TuyaFieldInstallerProcedureAuthoritySourceTests {
    @Test("post-install operator instructions require the accepted four-window flow")
    func installerCannotRegressToTwoWindowTargetSelection() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")

        #expect(installer.contains("complete OFF1 -> ON1 -> OFF2 -> ON2 exactly as Capture prompts"))
        #expect(installer.contains("require one repeatable full CoreBluetooth UUID"))
        #expect(installer.contains("Confirm correlated Bluetooth target"))
        #expect(installer.contains("Start secure read-only test"))

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
