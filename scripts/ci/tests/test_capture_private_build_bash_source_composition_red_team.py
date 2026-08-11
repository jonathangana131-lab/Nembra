#!/usr/bin/env python3
"""Demonstrate the cross-lineage Bash source-identity composition seam.

Validation only. Current private-identity bootstrap bytes derive repository
location from BASH_SOURCE[0]. Current build-authority execution preserves accepted
Git *bytes* by piping them to `source /dev/stdin` while passing the reviewed path
as `$0`. Those two individually valid contracts are incompatible when composed:
BASH_SOURCE[0] remains /dev/stdin and the bootstrap derives `/` as REPO_ROOT.

A passing test means the incompatibility was demonstrated; it is an expected-red
product/composition verdict, not product acceptance.
"""
from __future__ import annotations

from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
BUILD_AUTHORITY_SHA = "947f592239a800f636e0626b2a0b9233ccbac38d"
INSTALLER_PATH = "scripts/field/install_one_time_capture.command"
BOOTSTRAP_PATH = ROOT / "Scripts/bootstrap_capture_tuya_sdk.sh"


class PrivateBuildBashSourceCompositionRedTeamTests(unittest.TestCase):
    def _git_show(self, subject: str) -> str:
        return subprocess.check_output(
            ["git", "show", subject],
            cwd=ROOT,
            text=True,
            stderr=subprocess.STDOUT,
        )

    def test_verified_stdin_execution_breaks_current_bash_source_root_contract(self) -> None:
        installer = self._git_show(f"{BUILD_AUTHORITY_SHA}:{INSTALLER_PATH}")
        self.assertIn("run_accepted_source_bash() {", installer)
        self.assertIn('read_verified_accepted_git_blob "$relative_path" |', installer)
        self.assertIn(
            "/bin/bash --noprofile --norc -p -c 'source /dev/stdin' \"$ROOT/$relative_path\"",
            installer,
            "fixture must bind the exact accepted build-authority execution spelling",
        )

        bootstrap = BOOTSTRAP_PATH.read_text(encoding="utf-8")
        lines = bootstrap.splitlines()
        script_dir_lines = [line for line in lines if line.startswith('SCRIPT_DIR=')]
        repo_root_lines = [line for line in lines if line.startswith('REPO_ROOT=')]
        self.assertEqual(len(script_dir_lines), 1)
        self.assertEqual(len(repo_root_lines), 1)
        self.assertIn("${BASH_SOURCE[0]}", script_dir_lines[0])
        assignments = script_dir_lines[0] + "\n" + repo_root_lines[0] + "\n"

        with tempfile.TemporaryDirectory(prefix="nembra-bash-source-composition-") as temporary:
            checkout = Path(temporary) / "checkout"
            scripts = checkout / "Scripts"
            scripts.mkdir(parents=True)
            reviewed_path = scripts / "bootstrap_capture_tuya_sdk.sh"
            reviewed_path.write_text(
                assignments + 'printf "%s\\n" "$REPO_ROOT"\n',
                encoding="utf-8",
            )

            direct = subprocess.run(
                ["/bin/bash", "--noprofile", "--norc", "-p", str(reviewed_path)],
                cwd=checkout,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )
            self.assertEqual(direct.returncode, 0, direct.stderr)
            self.assertEqual(Path(direct.stdout.strip()).resolve(), checkout.resolve())

            via_verified_stdin = subprocess.run(
                [
                    "/bin/bash",
                    "--noprofile",
                    "--norc",
                    "-p",
                    "-c",
                    'source /dev/stdin; printf "%s\\n" "$REPO_ROOT"',
                    str(reviewed_path),
                ],
                cwd=checkout,
                input=assignments,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )
            self.assertEqual(via_verified_stdin.returncode, 0, via_verified_stdin.stderr)
            derived = Path(via_verified_stdin.stdout.strip()).resolve()

            self.assertEqual(
                derived,
                Path("/").resolve(),
                "fixture no longer demonstrates the /dev/stdin BASH_SOURCE identity used by the build-authority adapter",
            )
            self.assertNotEqual(
                derived,
                checkout.resolve(),
                "verified stdin execution unexpectedly preserved the reviewed bootstrap repository root",
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)
