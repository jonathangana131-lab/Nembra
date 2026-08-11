#!/usr/bin/env python3
"""Expected-red: the exact signed app verified for field authority must be the app installed.

The field installer verifies one signed Nembra Capture.app bundle and reads back its
provenance/entitlements before installation. The install step later reopens the bundle by
mutable pathname. This diagnostic executes the real post-verification install section with
an adversarial same-UID pathname swap: a fake `open` replaces the already-reviewed app,
`devicectl` observes the substituted bytes, and the fake tool restores the accepted bytes
before the shell continues. A safe installer must fail closed rather than report success.
"""

from __future__ import annotations

from pathlib import Path
import os
import subprocess
import tempfile
import textwrap
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
INSTALLER = REPOSITORY / "scripts/field/install_one_time_capture.command"


class CaptureSignedAppInstallSubjectTests(unittest.TestCase):
    def test_verified_bundle_cannot_be_swapped_before_devicectl_install(self) -> None:
        source = INSTALLER.read_text(encoding="utf-8")
        verification_marker = '/usr/bin/codesign --verify --deep --strict "$APP"'
        install_start_marker = 'say "Installing SDK-integrated Capture on the intended iPhone"'
        launch_marker = 'say "Launching privately provisioned Capture on the intended iPhone"'
        install_call_marker = 'xcrun devicectl device install app --device "$COREDEVICE_ID" "$APP"'

        verification_index = source.find(verification_marker)
        start_index = source.find(install_start_marker)
        launch_index = source.find(launch_marker)
        self.assertGreaterEqual(verification_index, 0, "installer no longer exposes the signed-app verification boundary")
        self.assertGreater(start_index, verification_index, "install must remain downstream of signed-app verification")
        self.assertGreater(launch_index, start_index, "could not isolate the real install section")

        install_section = source[start_index:launch_index]
        self.assertIn(install_call_marker, install_section, "diagnostic must exercise the real devicectl install call")

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
                "printf 'SUBSTITUTED_AFTER_VERIFICATION\\n' > \"${NEMBRA_REDTEAM_APP:?}/subject.txt\"\n"
                "exit 0\n",
                encoding="utf-8",
            )
            fake_open.chmod(0o755)

            fake_xcrun = fake_bin / "xcrun"
            fake_xcrun.write_text(
                "#!/bin/bash\n"
                "set -euo pipefail\n"
                "if [[ ${1:-} == 'devicectl' && ${2:-} == 'device' && ${3:-} == 'install' && ${4:-} == 'app' ]]; then\n"
                "  /bin/cat -- \"${NEMBRA_REDTEAM_APP:?}/subject.txt\" > \"${NEMBRA_REDTEAM_INSTALLED_SUBJECT:?}\"\n"
                "  printf 'ACCEPTED_SIGNED_SUBJECT\\n' > \"${NEMBRA_REDTEAM_APP:?}/subject.txt\"\n"
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

            self.assertTrue(installed_subject.is_file(), result.stdout)
            self.assertEqual(
                installed_subject.read_text(encoding="utf-8"),
                "SUBSTITUTED_AFTER_VERIFICATION\n",
                "red-team devicectl must observe bytes different from the earlier accepted subject",
            )
            self.assertEqual(
                payload.read_text(encoding="utf-8"),
                "ACCEPTED_SIGNED_SUBJECT\n",
                "red-team must restore the accepted pathname before later inspection can notice drift",
            )
            self.assertNotEqual(
                result.returncode,
                0,
                "field installer accepted a different app bundle at the devicectl side-effect boundary after signed-app verification; "
                "pin or revalidate the exact install subject so a pathname swap/restore cannot cross physical-build authority",
            )

    @staticmethod
    def _shell_quote(value: str) -> str:
        return "'" + value.replace("'", "'\\''") + "'"


if __name__ == "__main__":
    unittest.main(verbosity=2)
