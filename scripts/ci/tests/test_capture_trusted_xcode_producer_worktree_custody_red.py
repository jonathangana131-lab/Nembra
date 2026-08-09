#!/usr/bin/env python3
"""Expected-red source contract for trusted Capture producer execution custody.

The default-branch workflow may pin the candidate's producer Git object, but authority belongs to the
bytes actually executed after all earlier candidate-controlled steps have finished. A preflight
`HEAD:path` lookup is therefore insufficient if the later build step executes a mutable worktree
pathname without re-proving those bytes.
"""
from __future__ import annotations

from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
WORKFLOW_PATH = ROOT / ".github/workflows/capture-xcode27-trusted-command.yml"
PRODUCER_PATH = "scripts/ci/xcode27_simulator_capture.sh"
EXECUTION_STEP = "Build, test, and capture Simulator states"


def step_source(workflow: str, name: str) -> str:
    marker = f"      - name: {name}\n"
    start = workflow.index(marker)
    next_step = workflow.find("\n      - name: ", start + len(marker))
    return workflow[start:] if next_step < 0 else workflow[start:next_step]


class TrustedProducerWorktreeCustodyExpectedRedTests(unittest.TestCase):
    def test_authority_step_reproves_actual_worktree_bytes_immediately_before_execution(self) -> None:
        workflow = WORKFLOW_PATH.read_text(encoding="utf-8")

        pin_index = workflow.index("      - name: Verify trusted Capture evidence producer blob")
        execution_index = workflow.index(f"      - name: {EXECUTION_STEP}")
        self.assertLess(pin_index, execution_index)

        # Precondition proving this is a real time-of-check/time-of-use boundary: candidate code runs
        # after the Git-object pin and before the authority-producing runner is invoked.
        intervening = workflow[pin_index:execution_index]
        self.assertIn("- name: Validate project structure", intervening)
        self.assertIn("- name: Validate core package", intervening)
        self.assertIn("- name: Validate Capture package", intervening)

        execution = step_source(workflow, EXECUTION_STEP)
        self.assertIn(
            "TRUSTED_CAPTURE_EVIDENCE_PRODUCER_BLOB_SHA",
            execution,
            "the authority-producing step must carry the accepted producer identity itself",
        )
        self.assertIn(
            "TRUSTED_CAPTURE_EVIDENCE_PRODUCER_PATH",
            execution,
            "the authority-producing step must identify the exact worktree producer it will execute",
        )

        # Accept either a direct worktree Git-object calculation or an exact byte comparison against
        # the pinned object. Both prove the mutable pathname again after all prior candidate steps.
        proves_worktree_bytes = (
            "git hash-object" in execution
            or ("git cat-file" in execution and ("cmp " in execution or "/usr/bin/cmp" in execution))
        )
        self.assertTrue(
            proves_worktree_bytes,
            "the authority-producing step must re-prove the actual worktree bytes, not only HEAD:path",
        )

        invocation = execution.find(PRODUCER_PATH)
        proof_markers = [
            index
            for token in ("git hash-object", "git cat-file", "cmp ", "/usr/bin/cmp")
            if (index := execution.find(token)) >= 0
        ]
        self.assertGreaterEqual(invocation, 0, "trusted workflow no longer invokes the expected producer")
        self.assertTrue(proof_markers)
        self.assertLess(
            min(proof_markers),
            invocation,
            "actual producer bytes must be re-proven before the worktree pathname is executed",
        )


if __name__ == "__main__":
    unittest.main()
