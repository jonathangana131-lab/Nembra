#!/usr/bin/env python3
"""Adversarial closure for nested Capture field-tool execution subjects."""

from __future__ import annotations

import base64
from pathlib import Path
import subprocess
import sys
import tempfile
import textwrap
import unittest


ROOT = Path(__file__).resolve().parents[3]
INSTALLER = ROOT / "scripts/field/install_one_time_capture.command"
BOOTSTRAP = ROOT / "Scripts/bootstrap_capture_tuya_sdk.sh"


def run(*args: str, cwd: Path, input_bytes: bytes | None = None) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(
        list(args),
        cwd=cwd,
        input=input_bytes,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )


def production_capture_function(installer: str) -> str:
    start_marker = "capture_accepted_git_source_base64() {"
    end_marker = "\n}\n\nCAPTURE_BOOTSTRAP_PATH="
    start = installer.find(start_marker)
    end = installer.find(end_marker, start)
    if start < 0 or end < 0:
        raise AssertionError("production accepted-Git capture function could not be isolated")
    return installer[start : end + 2]


class NestedFieldExecutionSubjectClosureTests(unittest.TestCase):
    def test_installer_has_no_checkout_path_execution_for_nested_repo_tools(self) -> None:
        installer = INSTALLER.read_text(encoding="utf-8")
        bootstrap = BOOTSTRAP.read_text(encoding="utf-8")

        self.assertIn('GIT_NO_REPLACE_OBJECTS=1 git -C "$ROOT" cat-file blob "$blob"', installer)
        self.assertIn('CAPTURE_BOOTSTRAP_SOURCE_B64="$(capture_accepted_git_source_base64 "$CAPTURE_BOOTSTRAP_PATH")"', installer)
        self.assertIn('TUYA_PROVENANCE_SOURCE_B64="$(capture_accepted_git_source_base64 "$TUYA_PROVENANCE_PATH")"', installer)
        self.assertIn('PRIVATE_DEVICE_RUNNER="$(capture_accepted_git_source_base64 "$PRIVATE_DEVICE_RUNNER_PATH")"', installer)
        self.assertIn('printf \'%s\' "$CAPTURE_BOOTSTRAP_SOURCE_B64" | /usr/bin/base64 -D | /bin/bash -p -s --', installer)
        self.assertIn('/usr/bin/python3 -I -B - "$TUYA_PROVENANCE_SOURCE_B64" "$operation"', installer)
        self.assertNotIn('"$ROOT/Scripts/bootstrap_capture_tuya_sdk.sh"', installer)
        self.assertNotIn('/usr/bin/python3 -I "$TUYA_PROVENANCE_HELPER" verify', installer)
        self.assertNotIn('/usr/bin/base64 < "$PRIVATE_DEVICE_RUNNER_PATH"', installer)

        self.assertIn('--field-provenance-helper-base64', bootstrap)
        self.assertIn('CAPTURED_PROVENANCE_BLOB', bootstrap)
        self.assertIn('/usr/bin/python3 -I -B - "$PROVENANCE_HELPER_SOURCE_B64" "$operation"', bootstrap)

    def test_actual_installer_capture_survives_checkout_path_swap(self) -> None:
        installer = INSTALLER.read_text(encoding="utf-8")
        capture_function = production_capture_function(installer)

        with tempfile.TemporaryDirectory(prefix="nembra-nested-field-exec-") as temporary:
            repo = Path(temporary) / "repo"
            repo.mkdir()
            self.assertEqual(run("git", "init", "-q", cwd=repo).returncode, 0)
            self.assertEqual(run("git", "config", "user.name", "Nembra Test", cwd=repo).returncode, 0)
            self.assertEqual(run("git", "config", "user.email", "nembra@example.invalid", cwd=repo).returncode, 0)

            subject = repo / "accepted.py"
            subject.write_text("print('accepted')\n", encoding="utf-8")
            self.assertEqual(run("git", "add", "accepted.py", cwd=repo).returncode, 0)
            self.assertEqual(run("git", "commit", "-q", "-m", "accepted", cwd=repo).returncode, 0)

            head = run("git", "rev-parse", "HEAD", cwd=repo)
            self.assertEqual(head.returncode, 0, head.stderr.decode(errors="replace"))
            source_sha = head.stdout.decode().strip()

            harness = textwrap.dedent(
                f"""\
                #!/bin/bash -p
                set -euo pipefail
                ROOT="$1"
                SOURCE_SHA="$2"
                die() {{ builtin printf 'ERROR: %s\\n' "$*" >&2; exit 1; }}
                {capture_function}
                capture_accepted_git_source_base64 "accepted.py"
                """
            )
            harness_path = repo / "capture-harness.sh"
            harness_path.write_text(harness, encoding="utf-8")

            captured_result = run("/bin/bash", "-p", str(harness_path), str(repo), source_sha, cwd=repo)
            self.assertEqual(
                captured_result.returncode,
                0,
                captured_result.stderr.decode(errors="replace"),
            )
            captured_b64 = captured_result.stdout.strip()
            captured = base64.b64decode(captured_b64, validate=True)
            self.assertEqual(captured, b"print('accepted')\n")

            marker = repo / "attacker-ran.txt"
            subject.write_text(
                textwrap.dedent(
                    f"""
                    from pathlib import Path
                    Path({str(marker)!r}).write_text("attacker executed\\n", encoding="utf-8")
                    print("malicious")
                    """
                ).lstrip(),
                encoding="utf-8",
            )

            completed = run(sys.executable, "-I", "-", cwd=repo, input_bytes=captured)
            self.assertEqual(completed.returncode, 0, completed.stderr.decode(errors="replace"))
            self.assertEqual(completed.stdout.decode().strip(), "accepted")
            self.assertFalse(marker.exists(), "mutable checkout pathname executed after accepted Git capture")

    def test_private_reader_bootstrap_and_provenance_share_the_same_capture_primitive(self) -> None:
        installer = INSTALLER.read_text(encoding="utf-8")
        calls = [
            'CAPTURE_BOOTSTRAP_SOURCE_B64="$(capture_accepted_git_source_base64 "$CAPTURE_BOOTSTRAP_PATH")"',
            'TUYA_PROVENANCE_SOURCE_B64="$(capture_accepted_git_source_base64 "$TUYA_PROVENANCE_PATH")"',
            'PRIVATE_DEVICE_RUNNER="$(capture_accepted_git_source_base64 "$PRIVATE_DEVICE_RUNNER_PATH")"',
        ]
        for call in calls:
            self.assertIn(call, installer)
        self.assertEqual(installer.count("$(capture_accepted_git_source_base64"), 3)


if __name__ == "__main__":
    unittest.main(verbosity=2)
