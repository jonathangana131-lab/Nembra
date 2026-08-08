#!/usr/bin/env python3
from pathlib import Path
import re
import unittest

PRODUCER = Path(__file__).resolve().parents[1] / "xcode27_signed_field_candidate.sh"


class SignedFieldCandidatePythonCustodySourceTests(unittest.TestCase):
    """Pin interpreter/startup custody before private intended-device input is exposed.

    The producer passes the mode-0600 intended-device file path to the descriptor-bound private
    runner. Keeping the raw UDID out of argv is not enough if an ambient-PATH Python executable or
    caller-controlled Python startup hook can run before that runner validates/reads the file.
    """

    def setUp(self):
        self.source = PRODUCER.read_text()

    def test_producer_pins_one_absolute_python3_executable(self):
        self.assertRegex(
            self.source,
            re.compile(r'^PYTHON3="/[^"]*/python3"$', re.MULTILINE),
            "Field-candidate evidence must not execute Python through ambient PATH.",
        )
        self.assertNotRegex(
            self.source,
            re.compile(r'^\s*python3(?:\s|$)', re.MULTILINE),
            "Unqualified python3 lets PATH select code that can read the private UDID file or forge evidence.",
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
            "Every evidence-producing Python process must ignore caller PYTHON* startup authority: "
            + " | ".join(non_isolated),
        )


if __name__ == "__main__":
    unittest.main()
