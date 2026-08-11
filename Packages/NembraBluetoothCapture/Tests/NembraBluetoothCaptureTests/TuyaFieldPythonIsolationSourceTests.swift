import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture field Python interpreter isolation")
struct TuyaFieldPythonIsolationSourceTests {
    @Test("private Tuya input snapshot and verification ignore caller Python environment")
    func privateInputProvenanceUsesIsolatedSystemPython() throws {
        let bootstrap = try readRepositoryFile("Scripts/bootstrap_capture_tuya_sdk.sh")
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")
        #expect(bootstrap.contains("/usr/bin/python3 -I -c \"$PROVENANCE_SOURCE\" snapshot"))
        #expect(installer.contains("/usr/bin/python3 -I \"$TUYA_PROVENANCE_HELPER\" verify"))
        #expect(!bootstrap.contains("/usr/bin/python3 -I \"$PROVENANCE_HELPER\" snapshot"))
        #expect(!bootstrap.contains("/usr/bin/python3 -c \"$PROVENANCE_SOURCE\" snapshot"))
        #expect(!bootstrap.contains("/usr/bin/python3 \"$PROVENANCE_HELPER\" snapshot"))
        #expect(!installer.contains("/usr/bin/python3 \"$TUYA_PROVENANCE_HELPER\" verify"))
    }

    @Test("every installer system-Python execution is isolated")
    func intendedDeviceAndDiagnosticParsersCannotImportFromCallerPythonPath() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")
        let executablePythonLines = installer.split(separator: "\n").filter { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            return line.contains("/usr/bin/python3") && !line.hasPrefix("[[ -x /usr/bin/python3 ]]")
        }
        #expect(!executablePythonLines.isEmpty)
        for line in executablePythonLines { #expect(line.contains("/usr/bin/python3 -I")) }
        #expect(!installer.contains("/usr/bin/python3 -c"))
        #expect(installer.contains("/usr/bin/python3 -I -B - \"$PRIVATE_DEVICE_RUNNER\" \"$NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE\" \"$ROOT\""))
        #expect(!installer.contains("/usr/bin/python3 -I - \"$PRIVATE_DEVICE_RUNNER\""))
        #expect(installer.contains("DEVICE_ROWS=\"$(xcrun xctrace list devices 2>/dev/null | /usr/bin/python3 -I -c"))
        #expect(installer.contains("COREDEVICE_MATCH=\"$(printf '%s\\0%s' \"$DEVICE_UDID\" \"$COREDEVICE_ROWS\" | /usr/bin/python3 -I -c"))
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
