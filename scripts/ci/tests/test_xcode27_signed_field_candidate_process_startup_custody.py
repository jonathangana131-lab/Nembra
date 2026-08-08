#!/usr/bin/env python3
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

PRODUCER = Path(__file__).resolve().parents[1] / "xcode27_signed_field_candidate.sh"
CLOSED_PATH = "/usr/bin:/bin:/usr/sbin:/sbin"


class SignedFieldCandidateProcessStartupCustodyTests(unittest.TestCase):
    """Pin process authority before the producer can expose private/evidence inputs to children."""

    def setUp(self):
        self.source = PRODUCER.read_text()

    def test_shell_starts_in_privileged_mode_before_bash_env_can_execute(self):
        first_line = self.source.splitlines()[0]
        self.assertEqual(
            first_line,
            "#!/bin/bash -p",
            "Direct release invocation must start Bash in privileged mode so BASH_ENV/ENV, inherited shell functions, SHELLOPTS, BASHOPTS, CDPATH, and GLOBIGNORE are ignored before line 1 executes.",
        )

    def test_malicious_bash_env_cannot_execute_before_producer_body(self):
        with tempfile.TemporaryDirectory(prefix="nembra-producer-startup-custody-") as temporary:
            directory = Path(temporary)
            marker = directory / "bash-env-ran"
            hook = directory / "malicious-bash-env.sh"
            hook.write_text('printf "caller startup hook executed\\n" > "$NEMBRA_BASH_ENV_MARKER"\n')

            environment = os.environ.copy()
            environment["BASH_ENV"] = str(hook)
            environment["NEMBRA_BASH_ENV_MARKER"] = str(marker)

            completed = subprocess.run(
                [str(PRODUCER)],
                cwd=PRODUCER.parents[2],
                env=environment,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=False,
            )
            self.assertNotEqual(completed.returncode, 0)
            self.assertFalse(
                marker.exists(),
                "Caller BASH_ENV executed before the producer established its own release authority boundary.",
            )

    def test_closed_path_is_established_immediately_after_shell_options(self):
        expected = (
            'set -euo pipefail\n'
            f'PATH="{CLOSED_PATH}"\n'
            'export PATH\n'
        )
        self.assertIn(
            expected,
            self.source,
            "Signed-field production must replace caller PATH immediately after shell options and before any external command executes.",
        )

        path_index = self.source.index(f'PATH="{CLOSED_PATH}"')
        root_index = self.source.index('ROOT="$(cd "$(dirname "$0")/../.." && pwd -P)"')
        uname_index = self.source.index('if [[ "$(uname -s)" != "Darwin" ]]')
        self.assertLess(path_index, root_index)
        self.assertLess(path_index, uname_index)

    def test_caller_path_cannot_be_restored_by_plain_or_export_assignment(self):
        assignments = re.findall(r'(?m)^\s*(?:export\s+)?PATH\s*=', self.source)
        self.assertEqual(
            len(assignments),
            1,
            "The producer must have one authoritative PATH assignment, including exported-assignment syntax.",
        )
        self.assertNotRegex(
            self.source,
            re.compile(r'(?m)^\s*(?:export\s+)?PATH\s*=.*\$\{?PATH\}?'),
            "The closed producer PATH must never append/prepend caller PATH later.",
        )

    def test_python_remains_pinned_and_isolated(self):
        self.assertIn('PYTHON3="/usr/bin/python3"', self.source)
        self.assertNotRegex(self.source, re.compile(r'(?m)^\s*python3(?:\s|$)'))

        invocations = re.findall(r'(?m)^\s*"\$PYTHON3"[^\n]*', self.source)
        self.assertTrue(invocations)
        for invocation in invocations:
            self.assertRegex(
                invocation,
                re.compile(r'"\$PYTHON3"\s+-I(?:\s|$)'),
                "Every producer Python process must ignore caller PYTHON* startup authority.",
            )


if __name__ == "__main__":
    unittest.main()
