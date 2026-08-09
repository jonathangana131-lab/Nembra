#!/usr/bin/env python3
"""Portable V14 regression for trusted Capture Simulator runner custody.

The default-branch workflow is independent acceptance authority only when the executable that drives
Simulator build/test/capture is itself trusted. The candidate product remains the subject under test;
the acceptance runner must not be replaceable by that same candidate.
"""
from __future__ import annotations

import importlib.util
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]
WORKFLOW = ROOT / ".github/workflows/capture-xcode27-trusted-command.yml"
SUBJECT_MODULE = ROOT / "scripts/ci/es80_today_trusted_capture_xcode_subject.py"
RUNNER_PATH = "scripts/ci/xcode27_simulator_capture.sh"
EXPECTED_RUNNER_BLOB = "4e9ae0cb6728dc68d9b8dd43aac7c50128702ed9"
EXPECTED_WORKFLOW_BLOB = "35ac8290d7397743d705debf1787fa0af699230c"

spec = importlib.util.spec_from_file_location("trusted_subject_runner_custody", SUBJECT_MODULE)
trusted_subject = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(trusted_subject)


class TrustedCaptureRunnerBlobCustodyTests(unittest.TestCase):
    def test_workflow_pins_and_executes_git_blob_not_mutable_workspace_runner(self) -> None:
        source = WORKFLOW.read_text(encoding="utf-8")
        checkout = source.index("- name: Checkout immutable trusted Capture head")
        execution = source.index("- name: Build, test, and capture Simulator states", checkout)
        prefix = source[checkout:execution]
        execution_block = source[execution:]

        self.assertRegex(
            prefix,
            rf"(?m)^\s*TRUSTED_CAPTURE_SIMULATOR_RUNNER_BLOB_SHA:\s*{EXPECTED_RUNNER_BLOB}\s*$",
        )
        self.assertRegex(
            prefix,
            rf"rev-parse[^\n]*HEAD:{re.escape(RUNNER_PATH)}",
        )
        self.assertRegex(
            prefix,
            r'test\s+"\$candidate_runner_blob"\s+=\s+"\$TRUSTED_CAPTURE_SIMULATOR_RUNNER_BLOB_SHA"',
        )

        # The execution step must stream exact Git object bytes into bash. Reintroducing a direct
        # workspace-file execution would reopen a mutation/TOCTOU path after custody verification.
        self.assertIn(
            '/usr/bin/git cat-file blob "$TRUSTED_CAPTURE_SIMULATOR_RUNNER_BLOB_SHA"',
            execution_block,
        )
        self.assertIn(
            "| /bin/bash -s scripts/ci/xcode27_simulator_capture.sh",
            execution_block,
        )
        self.assertNotRegex(
            execution_block,
            rf"(?m)^\s*run:\s*{re.escape(RUNNER_PATH)}\s*$",
        )

    def test_final_go_subject_pins_same_workflow_and_runner_authority(self) -> None:
        self.assertEqual(
            trusted_subject.TRUSTED_CAPTURE_SIMULATOR_RUNNER_BLOB_SHA,
            EXPECTED_RUNNER_BLOB,
        )
        self.assertEqual(
            trusted_subject.TRUSTED_WORKFLOW_BLOB_SHA,
            EXPECTED_WORKFLOW_BLOB,
        )
        self.assertIn(
            "Verify trusted Capture Simulator runner custody",
            trusted_subject.REQUIRED_SUCCESSFUL_STEPS,
        )


if __name__ == "__main__":
    unittest.main()
