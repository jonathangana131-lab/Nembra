#!/usr/bin/env python3
"""V14 regression for immutable trusted Capture Simulator runner execution.

The candidate app/source is the subject under test. The Simulator evidence producer is acceptance
authority, so proving only its committed Git blob is insufficient if later candidate-controlled steps
can mutate the workspace file before direct execution. The trusted workflow must execute the exact
pinned Git object bytes instead.
"""
from __future__ import annotations

import importlib.util
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]
WORKFLOW = ROOT / ".github/workflows/capture-xcode27-trusted-command.yml"
SUBJECT = ROOT / "scripts/ci/es80_today_trusted_capture_xcode_subject.py"
RUNNER = "scripts/ci/xcode27_simulator_capture.sh"
EXPECTED_RUNNER_BLOB = "4e9ae0cb6728dc68d9b8dd43aac7c50128702ed9"
EXPECTED_WORKFLOW_BLOB = "fbafd920270808fbb712ecc8e1bfbe90819f23a3"

spec = importlib.util.spec_from_file_location("trusted_subject_immutable_exec", SUBJECT)
trusted_subject = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(trusted_subject)


class TrustedCaptureImmutableRunnerExecutionTests(unittest.TestCase):
    def test_trusted_workflow_executes_exact_pinned_git_object_not_workspace_path(self) -> None:
        source = WORKFLOW.read_text(encoding="utf-8")
        custody_anchor = "- name: Verify trusted Simulator evidence-producer custody"
        execution_anchor = "- name: Build, test, and capture Simulator states"
        self.assertIn(custody_anchor, source)
        self.assertIn(execution_anchor, source)

        custody = source.index(custody_anchor)
        execution = source.index(execution_anchor, custody)
        custody_block = source[custody:execution]
        execution_block = source[execution:]

        self.assertRegex(
            custody_block,
            rf"(?m)^\s*TRUSTED_SIMULATOR_EVIDENCE_PRODUCER_BLOB_SHA:\s*{EXPECTED_RUNNER_BLOB}\s*$",
        )
        self.assertRegex(
            custody_block,
            rf"rev-parse[^\n]*HEAD[^\n]*{re.escape(RUNNER)}",
        )
        self.assertRegex(
            custody_block,
            r'test\s+"\$actual_blob"\s+=\s+"\$TRUSTED_SIMULATOR_EVIDENCE_PRODUCER_BLOB_SHA"',
        )

        self.assertIn(
            '/usr/bin/git cat-file blob "$TRUSTED_SIMULATOR_EVIDENCE_PRODUCER_BLOB_SHA"',
            execution_block,
        )
        self.assertIn(
            "| /bin/bash -s scripts/ci/xcode27_simulator_capture.sh",
            execution_block,
        )
        self.assertNotRegex(
            execution_block,
            rf"(?m)^\s*run:\s*{re.escape(RUNNER)}\s*$",
            "trusted workflow reopened mutable candidate workspace bytes after custody proof",
        )

    def test_final_go_pins_exact_immutable_execution_workflow_and_runner(self) -> None:
        self.assertEqual(
            trusted_subject.TRUSTED_SIMULATOR_EVIDENCE_PRODUCER_BLOB_SHA,
            EXPECTED_RUNNER_BLOB,
        )
        self.assertEqual(
            trusted_subject.TRUSTED_WORKFLOW_BLOB_SHA,
            EXPECTED_WORKFLOW_BLOB,
        )
        self.assertIn(
            "Verify trusted Simulator evidence-producer custody",
            trusted_subject.REQUIRED_SUCCESSFUL_STEPS,
        )


if __name__ == "__main__":
    unittest.main()
