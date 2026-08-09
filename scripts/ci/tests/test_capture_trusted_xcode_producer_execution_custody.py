#!/usr/bin/env python3
"""Expected-red source regression for trusted Capture producer execution custody.

The default-branch workflow may inspect a candidate Git blob, but that inspection is not enough if
candidate-controlled code runs afterwards and the authority-producing step later executes the
mutable worktree pathname. The bytes actually interpreted by Bash must come from the already-pinned
Git object, while preserving the candidate workspace pathname only as `$0` so the frozen runner's
relative ROOT calculation still points at the exact candidate checkout.

VALIDATION ONLY: this test intentionally fails until the trusted workflow closes that TOCTOU.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]
WORKFLOW = ROOT / ".github/workflows/capture-xcode27-trusted-command.yml"
PRODUCER_PATH = "scripts/ci/xcode27_simulator_capture.sh"
PRODUCER_BLOB = "4e9ae0cb6728dc68d9b8dd43aac7c50128702ed9"


class TrustedProducerExecutionCustodyTests(unittest.TestCase):
    def test_authority_runner_executes_pinned_git_object_not_mutable_worktree_path(self) -> None:
        text = WORKFLOW.read_text(encoding="utf-8")

        custody_marker = "- name: Verify trusted Simulator evidence-producer custody"
        execution_marker = "- name: Build, test, and capture Simulator states"
        self.assertIn(custody_marker, text)
        self.assertIn(execution_marker, text)
        self.assertLess(text.index(custody_marker), text.index(execution_marker))

        # The existing preflight pin must remain explicit and exact.
        self.assertIn(f'producer_path="{PRODUCER_PATH}"', text)
        self.assertIn(f'expected_blob="{PRODUCER_BLOB}"', text)

        execution_start = text.index(execution_marker)
        next_step = text.find("\n      - name:", execution_start + len(execution_marker))
        execution_block = text[execution_start : next_step if next_step != -1 else len(text)]

        # A pathname invocation reopens candidate-controlled worktree bytes after the earlier check.
        self.assertNotRegex(
            execution_block,
            rf"(?m)^\s*run:\s*{re.escape(PRODUCER_PATH)}\s*$",
            "trusted Capture still executes the mutable candidate worktree pathname after its custody check",
        )

        # Green recovery must source the interpreter input from the exact pinned Git object, under
        # the same closed Git environment used by authority resolution. `$0` may point at the
        # candidate path solely so the frozen runner computes ROOT correctly; it is not the source
        # of executable bytes.
        self.assertIn('/usr/bin/git cat-file blob "$expected_blob"', execution_block)
        self.assertIn("GIT_CONFIG_NOSYSTEM=1", execution_block)
        self.assertIn("GIT_CONFIG_GLOBAL=/dev/null", execution_block)
        self.assertIn("GIT_NO_REPLACE_OBJECTS=1", execution_block)
        self.assertIn(
            "/bin/bash -c 'source /dev/stdin' \"$GITHUB_WORKSPACE/$producer_path\"",
            execution_block,
        )

        # Do not silently regress to a caller-selected producer blob in the execution step.
        blob_literals = re.findall(r"[0-9a-f]{40}", execution_block)
        if blob_literals:
            self.assertIn(PRODUCER_BLOB, blob_literals)


if __name__ == "__main__":
    unittest.main()
