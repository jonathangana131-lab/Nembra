#!/usr/bin/env python3
from pathlib import Path
import re
import unittest

PRODUCER = Path(__file__).resolve().parents[1] / "xcode27_signed_field_candidate.sh"


class SignedFieldCandidatePythonCustodySourceTests(unittest.TestCase):
    """Pin interpreter/startup custody before private intended-device input is exposed."""

    def setUp(self):
        self.source = PRODUCER.read_text()

    def test_producer_pins_root_custodied_system_python(self):
        self.assertRegex(
            self.source,
            re.compile(r'^PYTHON3="/[^"]*/python3"$', re.MULTILINE),
            "Field-candidate evidence must not execute Python through ambient PATH.",
        )
        self.assertIn('validate_root_custodied_path "$PYTHON3" file', self.source)
        self.assertIn("Pinned Python custody path is not root-owned", self.source)
        self.assertIn("Pinned Python custody path is group/world writable", self.source)
        self.assertIn("Pinned Python custody path contains a symlink", self.source)
        self.assertNotRegex(
            self.source,
            re.compile(r'^\s*python3(?:\s|$)', re.MULTILINE),
            "Unqualified python3 lets PATH select code that can read private input or forge evidence.",
        )

    def test_private_runner_is_started_in_isolated_mode(self):
        for descriptor in (7, 9):
            self.assertRegex(
                self.source,
                re.compile(rf'"\$PYTHON3"\s+-I\s+/dev/fd/{descriptor}\b'),
                f"Descriptor-bound private runner FD {descriptor} must start with Python isolated mode.",
            )

    def test_every_pinned_python_invocation_uses_isolated_mode(self):
        invocations = re.findall(r'(?m)^\s*"\$PYTHON3"[^\n]*', self.source)
        self.assertTrue(invocations, "Expected field-candidate producer to invoke its pinned Python executable")
        non_isolated = [line for line in invocations if not re.search(r'"\$PYTHON3"\s+-I(?:\s|$)', line)]
        self.assertEqual(
            non_isolated,
            [],
            "Every field-candidate Python process must ignore caller PYTHON* startup authority: "
            + " | ".join(non_isolated),
        )

    def test_pinned_python_is_validated_before_first_invocation(self):
        validation = self.source.index('validate_root_custodied_path "$PYTHON3" file')
        first_invocation = self.source.index('"$PYTHON3" -I')
        self.assertLess(
            validation,
            first_invocation,
            "The pinned interpreter must earn custody before any Python code executes.",
        )


if __name__ == "__main__":
    unittest.main()
