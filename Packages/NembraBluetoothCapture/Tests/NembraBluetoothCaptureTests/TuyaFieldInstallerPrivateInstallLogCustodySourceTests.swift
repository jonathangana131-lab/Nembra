import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture field installer private install-log custody")
struct TuyaFieldInstallerPrivateInstallLogCustodySourceTests {
    @Test("raw devicectl diagnostics use a unique private file with guaranteed cleanup")
    func installLogCannotPersistAsPredictableWorldReadableTemporaryState() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")

        #expect(installer.contains("mktemp \"${TMPDIR:-/tmp}/nembra-authenticated-capture-install.XXXXXX\""))
        #expect(installer.contains("chmod 600 \"$INSTALL_LOG\""))
        #expect(installer.contains("trap 'rm -f -- \"$INSTALL_LOG\"' EXIT"))
        #expect(installer.contains("rm -f -- \"$INSTALL_LOG\""))
        #expect(installer.contains("trap - EXIT"))
        #expect(!installer.contains("nembra-authenticated-capture-install.log"))
    }

    @Test("diagnostic replay redacts case and canonical separator variants without putting the secret in argv")
    func diagnosticReplayCannotDependOnCaseSensitiveShellSubstitution() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")

        #expect(installer.contains("printf '%s' \"$DEVICE_UDID\" | /usr/bin/python3 -I -c"))
        #expect(installer.contains("secret = sys.stdin.read()"))
        #expect(installer.contains("secret.replace(\"-\", \"\")"))
        #expect(installer.contains("flags=re.IGNORECASE"))
        #expect(installer.contains("<redacted-device>"))
        #expect(!installer.contains("INSTALL_DIAGNOSTIC=\"${INSTALL_DIAGNOSTIC//$DEVICE_UDID/<redacted-device>}\""))
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
