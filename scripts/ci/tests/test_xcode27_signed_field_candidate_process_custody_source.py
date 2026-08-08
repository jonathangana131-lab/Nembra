#!/usr/bin/env python3
from pathlib import Path
import re
import unittest

PRODUCER = Path(__file__).resolve().parents[1] / "xcode27_signed_field_candidate.sh"


class SignedFieldCandidateProcessCustodySourceTests(unittest.TestCase):
    """Pin executable-selection custody before private field input is exposed to child processes.

    NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE is intentionally a path rather than the raw UDID, but
    every child process launched by the signing shell runs as the same user and can open that file.
    If caller-controlled PATH remains active, replacing any unqualified child executable is therefore
    equivalent to replacing the private runner from a confidentiality/evidence-authority perspective.
    """

    def setUp(self):
        self.source = PRODUCER.read_text()

    def test_trusted_system_path_is_established_before_first_external_command(self):
        match = re.search(
            r'^PATH="/usr/bin:/bin:/usr/sbin:/sbin"\s*\nexport PATH$',
            self.source,
            re.MULTILINE,
        )
        self.assertIsNotNone(
            match,
            "Signed-field production must replace caller PATH with one closed system path before launching tools.",
        )

        path_index = match.start()
        shell_options_index = self.source.index("set -euo pipefail")
        root_index = self.source.index('ROOT="$(cd "$(dirname "$0")/../.." && pwd -P)"')
        uname_index = self.source.index('if [[ "$(uname -s)" != "Darwin" ]]')

        self.assertGreater(path_index, shell_options_index)
        self.assertLess(
            path_index,
            root_index,
            "PATH must be closed before dirname/pwd participates in repository-root authority.",
        )
        self.assertLess(
            path_index,
            uname_index,
            "PATH must be closed before any platform/tool discovery executes.",
        )

    def test_caller_path_cannot_be_restored_later(self):
        path_assignments = re.findall(r'(?m)^\s*PATH=', self.source)
        self.assertEqual(
            len(path_assignments),
            1,
            "The producer must have one authoritative PATH assignment rather than restoring ambient PATH later.",
        )
        self.assertNotRegex(
            self.source,
            re.compile(r'(?m)^\s*PATH=.*\$\{?PATH\}?'),
            "The closed producer PATH must never append/prepend caller PATH again.",
        )

    def test_python_is_pinned_and_isolated_in_addition_to_global_path_custody(self):
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
