#!/usr/bin/env python3
"""Expected-red: post-verification sealing must not bless substituted app bytes.

The production installer validates signature/provenance/entitlements, then seals a bundle
digest and protects that digest through devicectl. This diagnostic attacks the remaining
ordering seam: the app changes immediately after the final accepted verification message
but before the digest-only seal. A perfect digest-to-install guard cannot repair authority
that was already transferred to substituted bytes, so the installer must eventually keep
custody continuously from verification through sealing/install.
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
    def test_swap_after_final_verification_cannot_become_new_install_authority(self) -> None:
        source = INSTALLER.read_text(encoding="utf-8")
        start_marker = 'say "Final signed app and embedded provisioning profile authorize Sign in with Apple for one exact App ID and the selected team"'
        launch_marker = 'say "Launching privately provisioned Capture on the intended iPhone"'
        start = source.find(start_marker)
        end = source.find(launch_marker)
        self.assertGreaterEqual(start, 0)
        self.assertGreater(end, start)
        section = source[start:end]
        self.assertIn('--digest-only --app "$APP"', section)
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
                    import argparse, hashlib, subprocess, sys
                    from pathlib import Path
                    parser = argparse.ArgumentParser()
                    parser.add_argument('--app', type=Path, required=True)
                    parser.add_argument('--digest-only', action='store_true')
                    parser.add_argument('--expected-sha256')
                    parser.add_argument('command', nargs=argparse.REMAINDER)
                    args = parser.parse_args()
                    digest = hashlib.sha256((args.app / 'subject.txt').read_bytes()).hexdigest()
                    if args.digest_only:
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
                "the post-verification digest blessed substituted bytes and devicectl consumed them; custody must span verification -> seal -> install",
            )
            self.assertNotEqual(result.returncode, 0, result.stdout)

    @staticmethod
    def _quote(value: str) -> str:
        return "'" + value.replace("'", "'\\''") + "'"


if __name__ == "__main__":
    unittest.main(verbosity=2)
