#!/usr/bin/env python3
from pathlib import Path
import re
import unittest

PRODUCER = Path(__file__).resolve().parents[1] / "xcode27_signed_field_candidate.sh"


class SignedFieldCandidatePythonCustodySourceTests(unittest.TestCase):
    def setUp(self):
        self.source = PRODUCER.read_text()

    def test_producer_pins_one_absolute_python3_executable(self):
        self.assertRegex(
            self.source,
            re.compile(r'^PYTHON3="/[^"]*/python3"$', re.MULTILINE),
        )
        self.assertNotRegex(
            self.source,
            re.compile(r'^\s*python3(?:\s|$)', re.MULTILINE),
        )

    def test_pinned_python_and_parent_path_are_root_custodied_before_first_use(self):
        self.assertIn('validate_root_custodied_path()', self.source)
        self.assertIn('/usr/bin/stat -f', self.source)
        self.assertIn('/usr/bin/dirname', self.source)
        self.assertIn('owner_uid != 0', self.source)
        self.assertIn('mode_value & 0022', self.source)
        self.assertIn('validate_root_custodied_path "$PYTHON3" file', self.source)

        validation = self.source.index('validate_root_custodied_path "$PYTHON3" file')
        first_invocation = self.source.index('"$PYTHON3" -I')
        self.assertLess(
            validation,
            first_invocation,
            "The pinned interpreter and its canonical parent chain must be proven non-replaceable before Python executes.",
        )

    def test_private_runner_is_started_in_isolated_mode(self):
        for descriptor in (7, 9):
            self.assertRegex(
                self.source,
                re.compile(rf'"\$PYTHON3"\s+-I\s+/dev/fd/{descriptor}\b'),
            )

    def test_every_pinned_python_invocation_uses_isolated_mode(self):
        invocations = re.findall(r'(?m)^\s*"\$PYTHON3"[^\n]*', self.source)
        self.assertTrue(invocations)
        non_isolated = [line for line in invocations if not re.search(r'"\$PYTHON3"\s+-I(?:\s|$)', line)]
        self.assertEqual(non_isolated, [])


if __name__ == "__main__":
    unittest.main()
