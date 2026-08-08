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
