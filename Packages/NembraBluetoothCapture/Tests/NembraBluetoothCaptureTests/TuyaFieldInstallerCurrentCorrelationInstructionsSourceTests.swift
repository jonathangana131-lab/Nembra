import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture field installer current correlation instructions")
struct TuyaFieldInstallerCurrentCorrelationInstructionsSourceTests {
    @Test("post-install guidance matches the package-owned four-window correlation flow")
    func installerUsesCurrentFourWindowCorrelationProcedure() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")

        #expect(installer.contains("OFF1→ON1→OFF2→ON2"))
        #expect(installer.contains("Confirm correlated Bluetooth target"))
        #expect(installer.contains("Keep the scooter stationary"))
        #expect(installer.contains("Do NOT repeat the old 17-step ride capture"))
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
