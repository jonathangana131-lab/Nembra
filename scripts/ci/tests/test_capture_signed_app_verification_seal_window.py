#!/usr/bin/env python3
"""The signed app seal must be earned by authority verification under custody.

A same-UID replacement immediately after the legacy shell verification message must
not become the new accepted install subject. The installer is required to invoke the
custody helper's authority-verification mode before it records the digest that later
admits devicectl.
"""

from __future__ import annotations

from pathlib import Path
import subprocess
import tempfile
import textwrap
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
INSTALLER = REPOSITORY / "scripts/field/install_one_time_capture.command"


class CaptureSignedAppVerificationSealWindowTests(unittest.TestCase):
    def test_swap_after_shell_verification_cannot_become_new_install_authority(self) -> None:
        source = INSTALLER.read_text(encoding="utf-8")
        start_marker = 'say "Final signed app and embedded provisioning profile authorize Sign in with Apple for one exact App ID and the selected team"'
        launch_marker = 'say "Launching privately provisioned Capture on the intended iPhone"'
        start = source.find(start_marker)
        end = source.find(launch_marker)
        self.assertGreaterEqual(start, 0)
        self.assertGreater(end, start)
        section = source[start:end]
        self.assertIn('--verify-authority-only', section)
        self.assertIn('--expected-sha256 "$SIGNED_APP_SUBJECT_SHA256"', section)

        with tempfile.TemporaryDirectory(prefix="nembra-signed-app-verification-seal-") as temporary:
            root = Path(temporary)
            app = root / "Derived/Build/Products/Debug-iphoneos/Nembra Capture.app"
            app.mkdir(parents=True)
            payload = app / "subject.txt"
            payload.write_text("ACCEPTED_VERIFIED_SUBJECT\n", encoding="utf-8")

            scripts = root / "Scripts"
            scripts.mkdir()
            fake_guard = scripts / "capture_signed_app_install_guard.py"
            fake_guard.write_text(
                textwrap.dedent(
                    """\
                    #!/usr/bin/env python3
                    import argparse, hashlib, subprocess
                    from pathlib import Path
                    parser = argparse.ArgumentParser()
                    parser.add_argument('--app', type=Path, required=True)
                    parser.add_argument('--verify-authority-only', action='store_true')
                    parser.add_argument('--expected-sha256')
                    parser.add_argument('--expected-build-identifier')
                    parser.add_argument('--expected-source-sha')
                    parser.add_argument('--expected-tuya-lock-sha256')
                    parser.add_argument('--expected-procedure-id')
                    parser.add_argument('--expected-bundle-id')
                    parser.add_argument('--expected-team-id')
                    parser.add_argument('command', nargs=argparse.REMAINDER)
                    args = parser.parse_args()
                    subject = (args.app / 'subject.txt').read_bytes()
                    digest = hashlib.sha256(subject).hexdigest()
                    if args.verify_authority_only:
                        if subject != b'ACCEPTED_VERIFIED_SUBJECT\\n':
                            raise SystemExit(74)
                        print(digest)
                        raise SystemExit(0)
                    if digest != args.expected_sha256:
                        raise SystemExit(74)
                    command = args.command[1:] if args.command and args.command[0] == '--' else args.command
                    raise SystemExit(subprocess.run(command, check=False).returncode)
                    """
                ),
                encoding="utf-8",
            )
            fake_guard.chmod(0o755)

            fake_bin = root / "fake-bin"
            fake_bin.mkdir()
            installed_subject = root / "installed-subject.txt"
            fake_open = fake_bin / "open"
            fake_open.write_text("#!/bin/bash\nexit 0\n", encoding="utf-8")
            fake_open.chmod(0o755)
            fake_xcrun = fake_bin / "xcrun"
            fake_xcrun.write_text(
                "#!/bin/bash\n"
                "set -euo pipefail\n"
                "if [[ ${1:-} == devicectl && ${2:-} == device && ${3:-} == install && ${4:-} == app ]]; then\n"
                "  /bin/cat -- \"${NEMBRA_REDTEAM_APP:?}/subject.txt\" > \"${NEMBRA_REDTEAM_INSTALLED_SUBJECT:?}\"\n"
                "  exit 0\n"
                "fi\n"
                "exit 97\n",
                encoding="utf-8",
            )
            fake_xcrun.chmod(0o755)

            harness = root / "verification-seal-harness.sh"
            harness.write_text(
                textwrap.dedent(
                    f"""\
                    #!/bin/bash
                    set -euo pipefail
                    ROOT={self._quote(str(root))}
                    DERIVED="$ROOT/Derived"
                    APP={self._quote(str(app))}
                    COREDEVICE_ID='redteam-coredevice'
                    DEVICE_UDID='redteam-private-udid'
                    TMPDIR="$ROOT/tmp"
                    BUILD_LABEL='capture-v14-0123456789ab'
                    SOURCE_SHA='0123456789abcdef0123456789abcdef01234567'
                    TUYA_DEPENDENCY_LOCK_SHA256='89abcdef0123456789abcdef0123456789abcdef0123456789abcdef01234567'
                    PROCEDURE_ID='ES80-AUTHENTICATED-STATIONARY-v1'
                    BUNDLE_ID='com.jonathangana131.nembra.capturelearn'
                    TEAM_ID='A1B2C3D4E5'
                    /bin/mkdir -p "$TMPDIR"
                    say() {{
                        builtin printf '%s\\n' "$*"
                        if [[ "$*" == "Final signed app and embedded provisioning profile authorize Sign in with Apple for one exact App ID and the selected team" ]]; then
                            builtin printf 'SUBSTITUTED_AFTER_VERIFICATION\\n' > "$APP/subject.txt"
                        fi
                    }}
                    die() {{ builtin printf 'ERROR: %s\\n' "$*" >&2; exit 88; }}
                    {section}
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

            self.assertEqual(payload.read_text(encoding="utf-8"), "SUBSTITUTED_AFTER_VERIFICATION\n")
            self.assertFalse(
                installed_subject.exists(),
                "substituted bytes reached devicectl instead of being rejected by authority verification before sealing",
            )
            self.assertNotEqual(result.returncode, 0, result.stdout)

    @staticmethod
    def _quote(value: str) -> str:
        return "'" + value.replace("'", "'\\''") + "'"


if __name__ == "__main__":
    unittest.main(verbosity=2)
