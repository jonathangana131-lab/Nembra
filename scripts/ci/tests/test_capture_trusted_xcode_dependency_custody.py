#!/usr/bin/env python3
"""Expected-red V14 regression for trusted Capture Xcode dependency custody.

The owner-commanded default-branch workflow is a trust root only if an authority-bearing executable
cannot be replaced by the candidate it is supposed to validate. This regression deliberately does
not prescribe how app/product source is tested. It targets the narrower executable-authority seam:
a candidate checkout must not be allowed to replace the Simulator acceptance runner and then have
that replacement treated as independent trusted-Xcode evidence.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]
WORKFLOW = ROOT / ".github/workflows/capture-xcode27-trusted-command.yml"
RUNNER = "scripts/ci/xcode27_simulator_capture.sh"
PIN_NAME = "TRUSTED_CAPTURE_SIMULATOR_RUNNER_BLOB_SHA"


class TrustedCaptureXcodeDependencyCustodyTests(unittest.TestCase):
    def test_candidate_simulator_runner_is_byte_bound_before_authority_execution(self):
        source = WORKFLOW.read_text(encoding="utf-8")

        checkout_anchor = "- name: Checkout immutable trusted Capture head"
        execution_anchor = f"run: {RUNNER}"
        self.assertIn(checkout_anchor, source)
        self.assertIn(execution_anchor, source)

        checkout = source.index(checkout_anchor)
        execution = source.index(execution_anchor, checkout)
        authority_prefix = source[checkout:execution]

        # The current defect is specifically that the workflow changes the workspace to candidate
        # bytes and later executes the candidate's runner directly. A repair may keep that shape,
        # but then the runner itself must be bound to independently trusted Git bytes before it is
        # allowed to become acceptance authority.
        self.assertRegex(
            authority_prefix,
            rf"(?m)^\s*{PIN_NAME}:\s*[0-9a-f]{{40}}\s*$",
            "trusted workflow executes candidate Simulator runner without an independently pinned blob",
        )
        self.assertRegex(
            authority_prefix,
            rf"rev-parse[^\n]*HEAD:{re.escape(RUNNER)}",
            "trusted workflow never derives the exact candidate runner Git blob before execution",
        )
        self.assertRegex(
            authority_prefix,
            rf"test[^\n]*{PIN_NAME}|{PIN_NAME}[^\n]*test",
            "trusted workflow derives no fail-closed comparison against the trusted runner blob pin",
        )

    def test_candidate_runner_execution_remains_explicitly_visible_to_the_regression(self):
        source = WORKFLOW.read_text(encoding="utf-8")
        direct_runs = re.findall(
            rf"(?m)^\s*run:\s*{re.escape(RUNNER)}\s*$",
            source,
        )
        self.assertEqual(
            len(direct_runs),
            1,
            "update this regression deliberately if trusted workflow stops executing the candidate runner directly",
        )


if __name__ == "__main__":
    unittest.main()
