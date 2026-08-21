import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture field Python interpreter isolation")
struct TuyaFieldPythonIsolationSourceTests {
    @Test("accepted-source Tuya provenance adapter ignores caller Python environment")
    func acceptedProvenanceUsesIsolatedInMemoryPython() throws {
        let bootstrap = try readRepositoryFile("Scripts/bootstrap_capture_tuya_sdk.sh")
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")

        #expect(bootstrap.contains("/usr/bin/python3 -I \"$PROVENANCE_HELPER\" snapshot"))
        #expect(installer.contains("/usr/bin/python3 -I -B - \"$TUYA_PROVENANCE_SOURCE_B64\" \"$operation\""))
        #expect(installer.contains("exec(compile(source, namespace[\"__file__\"], \"exec\", dont_inherit=True), namespace)"))
        #expect(!installer.contains("/usr/bin/python3 -I \"$TUYA_PROVENANCE_HELPER\" verify"))
        #expect(!installer.contains("/usr/bin/python3 \"$TUYA_PROVENANCE_HELPER\" verify"))
    }

    @Test("every pre-install system-Python execution is isolated")
    func retainedSubjectAndAcceptedSourceParsersCannotImportCallerPythonPath() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")
        let executablePythonLines = installer.split(separator: "\n").filter { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            return line.contains("/usr/bin/python3") && !line.hasPrefix("[[ -x /usr/bin/python3 ]]")
        }

        #expect(!executablePythonLines.isEmpty)
        for line in executablePythonLines { #expect(line.contains("/usr/bin/python3 -I")) }
        #expect(!installer.contains("/usr/bin/python3 -c"))
        #expect(installer.contains("/usr/bin/python3 -I -B -c 'import base64,sys;"))
        #expect(installer.contains("/usr/bin/python3 -I -B - \"$PRIVATE_DEVICE_RUNNER\" \"$@\""))
        #expect(installer.contains("/usr/bin/env -i \\\"))
        #expect(installer.contains("/usr/bin/python3 -I -B - \\\"))
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
