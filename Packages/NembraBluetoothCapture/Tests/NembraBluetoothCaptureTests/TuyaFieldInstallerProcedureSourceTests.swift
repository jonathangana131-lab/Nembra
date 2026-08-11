import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture field installer procedure authority")
struct TuyaFieldInstallerProcedureSourceTests {
    @Test("installer launch instructions match the accepted four-window correlation procedure")
    func installerUsesFourWindowCorrelationAndExplicitConfirmation() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")

        #expect(installer.contains("OFF1 -> ON1 -> OFF2 -> ON2"))
        #expect(installer.contains("fresh-manager scanner to report Live"))
        #expect(installer.contains("explicitly confirm the single repeatable correlated target"))
        #expect(installer.contains("current-session evidence only"))
        #expect(installer.contains("not permanent scooter identity"))
        #expect(installer.contains("name/RSSI/FD50/Tuya-company/historical UUID hints never substitute"))
    }

    @Test("installer cannot authorize the superseded one-baseline physical shortcut")
    func installerRejectsSupersededShortcut() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")

        #expect(!installer.contains("run the scooter-OFF baseline, power it ON, select the authoritative target"))
    }

    @Test("installer keeps physical stop conditions and sealed-readiness truth")
    func installerFailsClosedAtPhysicalBoundary() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")

        #expect(installer.contains("field-build provenance is not proven, STOP"))
        #expect(installer.contains("a genuine same-generation dpsUpdate"))
        #expect(installer.contains("canonical continuity of at least 45 seconds"))
        #expect(installer.contains("a sealed accepted prefix"))
        #expect(installer.contains("No outdoor ride is authorized by this installer"))
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
