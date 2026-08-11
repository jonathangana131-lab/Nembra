#!/usr/bin/env python3
"""Expected-red witness for accepted Bash script identity across verified-byte execution.

The field installer correctly verifies accepted Git blob bytes before interpretation,
but its current Bash adapter sources those bytes from /dev/stdin while passing the
reviewed repository path only as argv[0]. The accepted bootstrap derives SCRIPT_DIR
from BASH_SOURCE[0], so this execution shape can redirect its repository root to /dev.

Validation only. No credentials, Xcode device operation, install, Bluetooth, Tuya,
or physical experiment occurs here.
"""
from __future__ import annotations

from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[3]
INSTALLER = ROOT / "scripts" / "field" / "install_one_time_capture.command"
BOOTSTRAP = ROOT / "Scripts" / "bootstrap_capture_tuya_sdk.sh"


class CaptureFieldAcceptedBashSourceIdentityRedTeamTests(unittest.TestCase):
    def setUp(self) -> None:
        self.installer = INSTALLER.read_text(encoding="utf-8")
        self.bootstrap = BOOTSTRAP.read_text(encoding="utf-8")

    def test_current_verified_bash_adapter_reproduces_source_identity_loss(self) -> None:
        self.assertIn("run_accepted_source_bash() {", self.installer)
        self.assertIn('read_verified_accepted_git_blob "$relative_path" |', self.installer)
        self.assertIn(
            "/bin/bash --noprofile --norc -p -c 'source /dev/stdin' \"$ROOT/$relative_path\"",
            self.installer,
        )
        self.assertIn(
            'SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"',
            self.bootstrap,
        )

        intended = "/accepted/repo/Scripts/bootstrap_capture_tuya_sdk.sh"
        probe = (
            'printf "%s\\0%s\\0%s" "${BASH_SOURCE[0]}" "$0" '
            '"$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"\n'
        )
        result = subprocess.run(
            [
                "/bin/bash",
                "--noprofile",
                "--norc",
                "-p",
                "-c",
                "source /dev/stdin",
                intended,
            ],
            input=probe.encode("utf-8"),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=True,
        )
        source_name, argv0, derived_directory = result.stdout.decode("utf-8").split("\0")
        self.assertEqual(argv0, intended, "the intended accepted path is present only as argv[0]")
        self.assertEqual(source_name, "/dev/stdin")
        self.assertEqual(derived_directory, "/dev")

    def test_accepted_bootstrap_execution_preserves_reviewed_repository_source_identity(self) -> None:
        """Accepted bootstrap root discovery must bind to the reviewed repository path.

        This assertion is intentionally expected red on #2968. Merely verifying the
        payload bytes is insufficient if interpreter metadata changes the script's
        path-derived behavior before private dependency custody is established.
        """
        intended = "/accepted/repo/Scripts/bootstrap_capture_tuya_sdk.sh"
        probe = 'printf "%s" "${BASH_SOURCE[0]}"\n'
        result = subprocess.run(
            [
                "/bin/bash",
                "--noprofile",
                "--norc",
                "-p",
                "-c",
                "source /dev/stdin",
                intended,
            ],
            input=probe.encode("utf-8"),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=True,
        )
        observed_source = result.stdout.decode("utf-8")
        self.assertEqual(
            observed_source,
            intended,
            "EXPECTED RED: verified accepted Bash bytes are sourced as /dev/stdin, "
            "but bootstrap_capture_tuya_sdk.sh derives SCRIPT_DIR from BASH_SOURCE[0]. "
            "Preserve the accepted repository script identity at execution or remove "
            "that path-derived dependency before claiming the guarded private bootstrap can run.",
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
