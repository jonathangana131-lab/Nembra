#!/usr/bin/env python3
"""Expected-red source proof for the trusted Capture Xcode harness authority boundary.

VALIDATION ONLY. The owner-commanded default-branch workflow is a legitimate independent workflow
subject only if the acceptance machinery it executes is independently trusted too. It may build the
candidate source, but it must not let that candidate replace the executable harness that decides
whether the Xcode build/test/capture acceptance step happened.
"""
from __future__ import annotations

from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]
WORKFLOW = ROOT / ".github/workflows/capture-xcode27-trusted-command.yml"
CANDIDATE_HARNESS = ROOT / "scripts/ci/xcode27_simulator_capture.sh"


class TrustedCaptureHarnessAuthorityTests(unittest.TestCase):
    def test_trusted_xcode_acceptance_does_not_execute_candidate_owned_harness(self) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")

        # Establish the exact authority topology under review: the workflow intentionally checks out
        # the immutable candidate head before the acceptance step.
        self.assertIn("Checkout immutable trusted Capture head", workflow)
        self.assertIn("ref: ${{ needs.resolve.outputs.head_sha }}", workflow)

        acceptance_step = re.search(
            r"(?ms)^\s*- name: Build, test, and capture Simulator states\s*\n"
            r"(?P<body>(?:\s{8,}.*\n)+?)(?=\s{6}- name:|\Z)",
            workflow,
        )
        self.assertIsNotNone(acceptance_step, "trusted workflow lost the canonical Xcode acceptance step")
        body = acceptance_step.group("body")

        candidate_relative_invocation = re.compile(
            r"(?m)^\s*run:\s*(?:bash\s+)?scripts/ci/xcode27_simulator_capture\.sh\s*$"
        )
        self.assertIsNone(
            candidate_relative_invocation.search(body),
            "owner-pinned workflow must not execute the PR checkout's replaceable Xcode acceptance harness; "
            "run a separately pinned/default-branch trusted harness against the candidate source instead",
        )

    def test_candidate_harness_is_authority_bearing_not_a_harmless_wrapper(self) -> None:
        harness = CANDIDATE_HARNESS.read_text(encoding="utf-8")
        self.assertIn("xcodebuild \\", harness)
        self.assertIn("NembraCaptureExternalBuildRecord.json", harness)
        self.assertIn("build-evidence", harness)


if __name__ == "__main__":
    unittest.main()
