#!/usr/bin/env python3
"""Composition contract for verified-Git stdin Bash bootstrap execution.

The private bootstrap may still run normally by pathname, but when a separately
admitted parent executes exact Git bytes through stdin it must take its repo root
from that explicit parent authority rather than BASH_SOURCE=/dev/stdin.
"""
from __future__ import annotations

import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
BOOTSTRAP = ROOT / "Scripts" / "bootstrap_capture_tuya_sdk.sh"
MARKER = 'TUYA_PRIVATE_SDK="$REPO_ROOT/LocalSecrets/TuyaSDK"'


class PrivateBootstrapVerifiedStdinRootTests(unittest.TestCase):
    def _root_prefix(self) -> str:
        source = BOOTSTRAP.read_text(encoding="utf-8")
        self.assertIn(MARKER, source)
        prefix, _ = source.split(MARKER, 1)
        return prefix + "\nprintf '%s\\n%s\\n' \"$SCRIPT_DIR\" \"$REPO_ROOT\"\n"

    @staticmethod
    def _closed_env(explicit_root: str | None = None) -> dict[str, str]:
        environment = {
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": "/tmp",
            "LANG": "C",
            "LC_ALL": "C",
        }
        if explicit_root is not None:
            environment["NEMBRA_ACCEPTED_SOURCE_ROOT"] = explicit_root
        return environment

    def test_verified_stdin_uses_explicit_admitted_physical_cwd(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-bootstrap-explicit-root-") as temporary:
            repo = Path(temporary).resolve()
            (repo / "Scripts").mkdir()
            completed = subprocess.run(
                ["/bin/bash", "--noprofile", "--norc", "-p", "-c", "source /dev/stdin"],
                cwd=repo,
                env=self._closed_env(str(repo)),
                input=self._root_prefix(),
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            self.assertEqual(
                completed.stdout.splitlines(),
                [str(repo / "Scripts"), str(repo)],
            )

    def test_explicit_root_cannot_redirect_away_from_physical_cwd(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-bootstrap-root-a-") as first, tempfile.TemporaryDirectory(
            prefix="nembra-bootstrap-root-b-"
        ) as second:
            repo = Path(first).resolve()
            other = Path(second).resolve()
            (repo / "Scripts").mkdir()
            (other / "Scripts").mkdir()
            completed = subprocess.run(
                ["/bin/bash", "--noprofile", "--norc", "-p", "-c", "source /dev/stdin"],
                cwd=repo,
                env=self._closed_env(str(other)),
                input=self._root_prefix(),
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )
            self.assertNotEqual(completed.returncode, 0)
            self.assertIn("explicit accepted source root must equal the physical working directory", completed.stderr)

    def test_explicit_root_must_be_absolute_physical_path(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-bootstrap-relative-root-") as temporary:
            repo = Path(temporary).resolve()
            (repo / "Scripts").mkdir()
            completed = subprocess.run(
                ["/bin/bash", "--noprofile", "--norc", "-p", "-c", "source /dev/stdin"],
                cwd=repo,
                env=self._closed_env("relative/path"),
                input=self._root_prefix(),
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )
            self.assertNotEqual(completed.returncode, 0)
            self.assertIn("explicit accepted source root must be absolute", completed.stderr)

    def test_normal_path_execution_preserves_bash_source_fallback(self) -> None:
        source = BOOTSTRAP.read_text(encoding="utf-8")
        self.assertIn('if [[ -n "${NEMBRA_ACCEPTED_SOURCE_ROOT:-}" ]]; then', source)
        self.assertIn('SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"', source)
        self.assertIn('REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"', source)
        self.assertIn('[[ "$NEMBRA_ACCEPTED_SOURCE_ROOT" == "$PHYSICAL_CWD" ]]', source)
        self.assertNotIn("eval ", source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
