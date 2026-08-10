from pathlib import Path

installer_path = Path("scripts/field/install_one_time_capture.command")
installer = installer_path.read_text()

old = r'''INSTALL_LOG="${TMPDIR:-/tmp}/nembra-authenticated-capture-install.log"
rm -f "$INSTALL_LOG"
INSTALLED=0
for ATTEMPT in $(seq 1 60); do
    if xcrun devicectl device install app --device "$DEVICE_UDID" "$APP" >"$INSTALL_LOG" 2>&1; then
        INSTALLED=1
        break
    fi
    if [[ "$ATTEMPT" == "1" ]]; then
        printf '%s\n' "Xcode still appears to be preparing the intended iPhone. Keep it plugged in and unlocked; installation will retry automatically."
    fi
    sleep 3
done

if [[ "$INSTALLED" != "1" ]]; then
    if [[ -f "$INSTALL_LOG" ]]; then
        INSTALL_DIAGNOSTIC="$(<"$INSTALL_LOG")"
        INSTALL_DIAGNOSTIC="${INSTALL_DIAGNOSTIC//$DEVICE_UDID/<redacted-device>}"
        printf '%s\n' "$INSTALL_DIAGNOSTIC" >&2
        unset INSTALL_DIAGNOSTIC
    fi
    die "The app built successfully, but the intended iPhone never became ready for installation. Keep it unlocked and connected, wait for Xcode to finish Preparing/Connecting, then run this installer again."
fi
'''

new = r'''INSTALL_LOG="$(mktemp "${TMPDIR:-/tmp}/nembra-authenticated-capture-install.XXXXXX")"
chmod 600 "$INSTALL_LOG"
trap 'rm -f -- "$INSTALL_LOG"' EXIT
INSTALLED=0
for ATTEMPT in $(seq 1 60); do
    if xcrun devicectl device install app --device "$DEVICE_UDID" "$APP" >"$INSTALL_LOG" 2>&1; then
        INSTALLED=1
        break
    fi
    if [[ "$ATTEMPT" == "1" ]]; then
        printf '%s\n' "Xcode still appears to be preparing the intended iPhone. Keep it plugged in and unlocked; installation will retry automatically."
    fi
    sleep 3
done

if [[ "$INSTALLED" != "1" ]]; then
    if [[ -s "$INSTALL_LOG" ]]; then
        INSTALL_DIAGNOSTIC="$(
            printf '%s' "$DEVICE_UDID" | /usr/bin/python3 -I -c '
import re
import sys
from pathlib import Path
secret = sys.stdin.read()
text = Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")
variants = sorted({secret, secret.replace("-", "")}, key=len, reverse=True)
for variant in variants:
    if variant:
        text = re.sub(re.escape(variant), "<redacted-device>", text, flags=re.IGNORECASE)
sys.stdout.write(text)
' "$INSTALL_LOG"
        )"
        printf '%s\n' "$INSTALL_DIAGNOSTIC" >&2
        unset INSTALL_DIAGNOSTIC
    fi
    die "The app built successfully, but the intended iPhone never became ready for installation. Keep it unlocked and connected, wait for Xcode to finish Preparing/Connecting, then run this installer again."
fi
'''

if installer.count(old) != 1:
    raise SystemExit(f"install-log custody block match count={installer.count(old)}")
installer = installer.replace(old, new, 1)

old_success = '''unset DEVICE_UDID\nrm -f "$INSTALL_LOG"\n'''
new_success = '''unset DEVICE_UDID\nrm -f -- "$INSTALL_LOG"\ntrap - EXIT\n'''
if installer.count(old_success) != 1:
    raise SystemExit(f"success cleanup block match count={installer.count(old_success)}")
installer = installer.replace(old_success, new_success, 1)
installer_path.write_text(installer)

test_path = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaFieldInstallerPrivateInstallLogCustodySourceTests.swift")
test_path.write_text(r'''import Foundation
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
''')
