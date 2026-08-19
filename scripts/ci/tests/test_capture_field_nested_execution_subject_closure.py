#!/usr/bin/env python3
"""Adversarial closure for nested Capture field-tool execution subjects."""

from __future__ import annotations

import base64
import hashlib
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

    def test_path_swap_after_git_object_capture_cannot_change_executed_bytes(self) -> None:
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
            oid_result = run("git", "rev-parse", f"{source_sha}:accepted.py", cwd=repo)
            self.assertEqual(oid_result.returncode, 0, oid_result.stderr.decode(errors="replace"))
            oid = oid_result.stdout.decode().strip()
            captured_result = run("git", "cat-file", "blob", oid, cwd=repo)
            self.assertEqual(captured_result.returncode, 0, captured_result.stderr.decode(errors="replace"))
            captured = captured_result.stdout

            expected_oid = hashlib.sha1(
                b"blob " + str(len(captured)).encode("ascii") + b"\0" + captured
            ).hexdigest()
            self.assertEqual(expected_oid, oid)

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

            encoded = base64.b64encode(captured)
            decoded = base64.b64decode(encoded, validate=True)
            completed = run(sys.executable, "-I", "-", cwd=repo, input_bytes=decoded)
            self.assertEqual(completed.returncode, 0, completed.stderr.decode(errors="replace"))
            self.assertEqual(completed.stdout.decode().strip(), "accepted")
            self.assertFalse(marker.exists(), "mutable checkout pathname executed after accepted Git capture")


if __name__ == "__main__":
    unittest.main(verbosity=2)
