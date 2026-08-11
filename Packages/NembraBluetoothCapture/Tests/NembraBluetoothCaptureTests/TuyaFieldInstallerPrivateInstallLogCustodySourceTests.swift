import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture field installer private install-log custody")
struct TuyaFieldInstallerPrivateInstallLogCustodySourceTests {
    @Test("signed app and raw devicectl log use distinct private custody with one cleanup lifecycle")
    func installLogCannotPersistAsPredictableTemporaryState() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")

        #expect(installer.contains("cleanup_install_subject()"))
        #expect(installer.contains("trap cleanup_install_subject EXIT"))
        #expect(installer.contains("APP_INSTALL_STAGE_ROOT=\"$(/usr/bin/sudo /usr/bin/mktemp -d /private/tmp/nembra-authenticated-capture-install.XXXXXX)\""))
        #expect(installer.contains("APP_INSTALL_STAGE=\"$APP_INSTALL_STAGE_ROOT/Nembra Capture.app\""))
        #expect(installer.contains("INSTALL_LOG=\"$(mktemp \"${TMPDIR:-/tmp}/nembra-authenticated-capture-install-log.XXXXXX\")\""))
        #expect(installer.contains("chmod 600 \"$INSTALL_LOG\""))
        #expect(installer.contains("/bin/rm -f -- \"$INSTALL_LOG\" || true"))
        #expect(installer.contains("/usr/bin/sudo -n /bin/rm -rf -- \"$APP_INSTALL_STAGE_ROOT\""))
        #expect(installer.contains("rm -f -- \"$INSTALL_LOG\""))
        #expect(installer.contains("INSTALL_LOG=\"\""))
        #expect(installer.contains("APP_INSTALL_STAGE_ROOT=\"\""))
        #expect(installer.contains("trap - EXIT"))
        #expect(!installer.contains("nembra-authenticated-capture-install.log"))
        #expect(!installer.contains("trap 'rm -f -- \"$INSTALL_LOG\"' EXIT"))
    }

    @Test("diagnostic replay redacts private and selector variants without putting either value in child argv")
    func diagnosticReplayUsesStdinBoundRedaction() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")

        #expect(installer.contains("printf '%s\\0%s' \"$DEVICE_UDID\" \"$COREDEVICE_ID\" | /usr/bin/python3 -I -c"))
        #expect(installer.contains("payload = sys.stdin.buffer.read()"))
        #expect(installer.contains("private_udid_raw, selector_raw = payload.split(b\"\\0\", 1)"))
        #expect(installer.contains("secret.replace(\"-\", \"\")"))
        #expect(installer.contains("flags=re.IGNORECASE"))
        #expect(installer.contains("<redacted-device>"))
        #expect(installer.contains("<redacted-device-selector>"))
        #expect(!installer.contains("INSTALL_DIAGNOSTIC=\"${INSTALL_DIAGNOSTIC//$DEVICE_UDID/<redacted-device>}\""))
        #expect(!installer.contains("INSTALL_DIAGNOSTIC=\"${INSTALL_DIAGNOSTIC//$COREDEVICE_ID/<redacted-device-selector>}\""))
    }

    @Test("strong intended-device, protected signed-artifact, and V14 baseline custody remain intact")
    func hardeningDoesNotRegressCurrentFieldAuthority() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")

        #expect(installer.contains("iPhone13,2"))
        #expect(installer.contains("$DEVICE_OS_VERSION\" == 27.*"))
        #expect(installer.contains("APP=\"$APP_INSTALL_STAGE\""))
        #expect(installer.contains("devicectl device install app --device \"$COREDEVICE_ID\" \"$APP\""))
        #expect(!installer.contains("devicectl device install app --device \"$DEVICE_UDID\""))
        #expect(installer.contains("APP_INFO_PLIST=\"$APP/Info.plist\""))
        #expect(installer.contains("$BUILT_BUILD_IDENTIFIER\" == \"$BUILD_LABEL"))
        #expect(installer.contains("$BUILT_SOURCE_SHA\" == \"$SOURCE_SHA"))
        #expect(installer.contains("$BUILT_BUNDLE_ID\" == \"$BUNDLE_ID"))
        #expect(installer.contains("OFF1 -> ON1 -> OFF2 -> ON2"))
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