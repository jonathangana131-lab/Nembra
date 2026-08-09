#!/usr/bin/env python3
"""V14 regression for trusted Capture runner worktree custody.

Binding HEAD:path is necessary but does not prove the mutable working-tree pathname still contains
those bytes when it is executed. Candidate tests run arbitrary code, so the final pre-execution
custody step must also hash the actual working-tree bytes and must sit immediately before runner
execution.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
WORKFLOW = ROOT / ".github/workflows/capture-xcode27-trusted-command.yml"
RUNNER = "scripts/ci/xcode27_simulator_capture.sh"
PIN = "4e9ae0cb6728dc68d9b8dd43aac7c50128702ed9"
CUSTODY_STEP = "- name: Verify trusted Simulator evidence-producer custody"
EXECUTION_STEP = "- name: Build, test, and capture Simulator states"


class TrustedCaptureRunnerWorktreeCustodyTests(unittest.TestCase):
    def test_final_custody_rehashes_worktree_bytes_immediately_before_execution(self):
        source = WORKFLOW.read_text(encoding="utf-8")
        execution = source.index(EXECUTION_STEP)
        custody = source.rfind(CUSTODY_STEP, 0, execution)
        self.assertNotEqual(custody, -1, "trusted workflow has no producer-custody step")

        final_custody = source[custody:execution]
        self.assertIn(
            "hash-object --no-filters",
            final_custody,
            "final runner custody checks only HEAD:path and never hashes the mutable worktree bytes",
        )
        self.assertIn(
            RUNNER,
            final_custody,
            "final worktree-byte custody is not visibly bound to the Simulator runner path",
        )
        self.assertIn(
            PIN,
            final_custody,
            "final worktree-byte custody is not visibly bound to the reviewed runner blob",
        )

        intervening_steps = final_custody.count("\n      - name:")
        self.assertEqual(
            intervening_steps,
            0,
            "another workflow step can run after final runner-byte custody and before execution",
        )

    def test_candidate_controlled_validation_finishes_before_final_custody(self):
        source = WORKFLOW.read_text(encoding="utf-8")
        execution = source.index(EXECUTION_STEP)
        custody = source.rfind(CUSTODY_STEP, 0, execution)
        self.assertNotEqual(custody, -1)

        candidate_steps = (
            "- name: Validate project structure",
            "- name: Validate core package",
            "- name: Validate Capture package",
            "- name: Validate signed field evidence tooling",
            "- name: Validate signed field candidate producer source",
            "- name: Validate offline field authorization signer",
        )
        for step in candidate_steps:
            position = source.index(step)
            self.assertLess(
                position,
                custody,
                f"candidate-controlled step remains after final runner custody: {step}",
            )

        direct_execution = f"run: {RUNNER}"
        self.assertIn(direct_execution, source[execution:])


if __name__ == "__main__":
    unittest.main()
