import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture field installer Python bytecode custody")
struct TuyaFieldInstallerPythonBytecodeCustodySourceTests {
    @Test("private intended-device reader cannot dirty accepted source with Python bytecode")
    func privateReaderDisablesBytecodeWritesBeforeBootstrapCleanTreeGate() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")

        let hardenedInvocation = "/usr/bin/python3 -I -B - \"$PRIVATE_DEVICE_RUNNER\" \"$NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE\" \"$ROOT\""
        let bytecodeWritingInvocation = "/usr/bin/python3 -I - \"$PRIVATE_DEVICE_RUNNER\" \"$NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE\" \"$ROOT\""

        #expect(installer.contains(hardenedInvocation))
        #expect(!installer.contains(bytecodeWritingInvocation))
        #expect(installer.contains("Private intended-device admission validated"))
        #expect(installer.contains("Private workspace bootstrap changed tracked or unignored accepted-source inputs"))
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
