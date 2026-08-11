#!/usr/bin/env python3
"""The exact signed app verified for field authority must be the app installed.

This regression executes the real post-verification install section. A controlled
same-UID `open` replacement mutates the reviewed app immediately before the install
attempt. Production must reject that drift before fake `devicectl` can consume the
substituted bytes.
"""

from __future__ import annotations

from pathlib import Path
import subprocess
import tempfile
import textwrap
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
INSTALLER = REPOSITORY / "scripts/field/install_one_time_capture.command"
INSTALL_GUARD = REPOSITORY / "Scripts/capture_signed_app_install_guard.py"


class CaptureSignedAppInstallSubjectTests(unittest.TestCase):
    def test_verified_bundle_swap_is_rejected_before_devicectl_consumes_it(self) -> None:
        source = INSTALLER.read_text(encoding="utf-8")
        verification_marker = '/usr/bin/codesign --verify --deep --strict "$APP"'
        install_start_marker = 'say "Installing SDK-integrated Capture on the intended iPhone"'
        launch_marker = 'say "Launching privately provisioned Capture on the intended iPhone"'
        install_call_marker = 'xcrun devicectl device install app --device "$COREDEVICE_ID" "$APP"'

        verification_index = source.find(verification_marker)
        start_index = source.find(install_start_marker)
        launch_index = source.find(launch_marker)
        self.assertGreaterEqual(verification_index, 0)
        self.assertGreater(start_index, verification_index)
        self.assertGreater(launch_index, start_index)

        install_section = source[start_index:launch_index]
        self.assertIn(install_call_marker, install_section)
        self.assertIn('--expected-sha256 "$SIGNED_APP_SUBJECT_SHA256"', install_section)

        with tempfile.TemporaryDirectory(prefix="nembra-signed-app-install-subject-") as temporary:
            root = Path(temporary)
            app = root / "Derived/Build/Products/Debug-iphoneos/Nembra Capture.app"
            app.mkdir(parents=True)
            payload = app / "subject.txt"
            payload.write_text("ACCEPTED_SIGNED_SUBJECT\n", encoding="utf-8")

            installed_subject = root / "installed-subject.txt"
            fake_bin = root / "fake-bin"
            fake_bin.mkdir()

            fake_open = fake_bin / "open"
            fake_open.write_text(
                "#!/bin/bash\n"
                "set -euo pipefail\n"
                "printf 'SUBSTITUTED_AFTER_VERIFICATION\\n' > \"${NEMBRA_REDTEAM_APP:?}/subject.txt\"\n",
                encoding="utf-8",
            )
            fake_open.chmod(0o755)

            fake_xcrun = fake_bin / "xcrun"
            fake_xcrun.write_text(
                "#!/bin/bash\n"
                "set -euo pipefail\n"
                "if [[ ${1:-} == 'devicectl' && ${2:-} == 'device' && ${3:-} == 'install' && ${4:-} == 'app' ]]; then\n"
                "  /bin/cat -- \"${NEMBRA_REDTEAM_APP:?}/subject.txt\" > \"${NEMBRA_REDTEAM_INSTALLED_SUBJECT:?}\"\n"
                "  exit 0\n"
                "fi\n"
                "exit 97\n",
                encoding="utf-8",
            )
            fake_xcrun.chmod(0o755)

            harness = root / "install-boundary-harness.sh"
            harness.write_text(
                textwrap.dedent(
                    f"""\
                    #!/bin/bash
                    set -euo pipefail
                    ROOT={self._shell_quote(str(root))}
                    DERIVED="$ROOT/Derived"
                    APP={self._shell_quote(str(app))}
                    SIGNED_APP_INSTALL_GUARD={self._shell_quote(str(INSTALL_GUARD))}
                    SIGNED_APP_SUBJECT_SHA256="$(/usr/bin/python3 -I "$SIGNED_APP_INSTALL_GUARD" --digest-only --app "$APP")"
                    COREDEVICE_ID='redteam-coredevice'
                    DEVICE_UDID='redteam-private-udid'
                    TMPDIR="$ROOT/tmp"
                    /bin/mkdir -p "$TMPDIR"
                    say() {{ builtin printf '%s\\n' "$*"; }}
                    die() {{ builtin printf 'ERROR: %s\\n' "$*" >&2; exit 88; }}
                    {install_section}
                    exit 0
                    """
                ),
                encoding="utf-8",
            )
            harness.chmod(0o755)

            environment = {
                "PATH": f"{fake_bin}:/usr/bin:/bin",
                "HOME": str(root),
                "LANG": "C.UTF-8",
                "LC_ALL": "C.UTF-8",
                "NEMBRA_REDTEAM_APP": str(app),
                "NEMBRA_REDTEAM_INSTALLED_SUBJECT": str(installed_subject),
            }
            result = subprocess.run(
                ["/bin/bash", str(harness)],
                cwd=root,
                env=environment,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                check=False,
            )

            self.assertNotEqual(result.returncode, 0, result.stdout)
            self.assertFalse(
                installed_subject.exists(),
                "devicectl consumed substituted app bytes; detecting drift after the physical install side effect is too late",
            )
            self.assertEqual(payload.read_text(encoding="utf-8"), "SUBSTITUTED_AFTER_VERIFICATION\n")

    @staticmethod
    def _shell_quote(value: str) -> str:
        return "'" + value.replace("'", "'\\''") + "'"


if __name__ == "__main__":
    unittest.main(verbosity=2)
