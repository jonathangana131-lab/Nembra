#!/usr/bin/env python3
from pathlib import Path
import re
import unittest

PRODUCER = Path(__file__).resolve().parents[1] / "xcode27_signed_field_candidate.sh"


class SignedFieldCandidateProcessCustodySourceTests(unittest.TestCase):
    def setUp(self):
        self.source = PRODUCER.read_text()

    def test_trusted_system_path_is_established_before_first_external_command(self):
        match = re.search(r'^PATH="/usr/bin:/bin:/usr/sbin:/sbin"\s*\nexport PATH$', self.source, re.MULTILINE)
        self.assertIsNotNone(match)
        path_index = match.start()
        self.assertGreater(path_index, self.source.index("set -euo pipefail"))
        self.assertLess(path_index, self.source.index('ROOT="$(cd "$(dirname "$0")/../.." && pwd -P)"'))
        self.assertLess(path_index, self.source.index('if [[ "$(uname -s)" != "Darwin" ]]'))

    def test_caller_path_cannot_be_restored_later(self):
        self.assertEqual(len(re.findall(r'(?m)^\s*PATH=', self.source)), 1)
        self.assertNotRegex(self.source, re.compile(r'(?m)^\s*PATH=.*\$\{?PATH\}?'))

    def test_python_is_pinned_and_isolated_in_addition_to_global_path_custody(self):
        self.assertIn('PYTHON3="/usr/bin/python3"', self.source)
        self.assertNotRegex(self.source, re.compile(r'(?m)^\s*python3(?:\s|$)'))
        invocations = re.findall(r'(?m)^\s*"\$PYTHON3"[^\n]*', self.source)
        self.assertTrue(invocations)
        for invocation in invocations:
            self.assertRegex(invocation, re.compile(r'"\$PYTHON3"\s+-I(?:\s|$)'))


if __name__ == "__main__":
    unittest.main()
