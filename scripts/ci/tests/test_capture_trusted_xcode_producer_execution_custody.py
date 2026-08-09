#!/usr/bin/env python3
"""Source regression for trusted Capture producer execution custody.

The owner-commanded default-branch workflow must execute the exact reviewed Simulator producer Git
object, not reopen candidate-controlled working-tree bytes after validation. The reviewed bytes are
materialized into shell memory, re-hashed independently, and those same bytes are interpreted by
Bash. The candidate pathname is supplied only as `$0` so the frozen producer retains its existing
relative repository-root semantics.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]
WORKFLOW = ROOT / ".github/workflows/capture-xcode27-trusted-command.yml"
PRODUCER_PATH = "scripts/ci/xcode27_simulator_capture.sh"
PRODUCER_BLOB = "4e9ae0cb6728dc68d9b8dd43aac7c50128702ed9"


class TrustedProducerExecutionCustodyTests(unittest.TestCase):
    def test_authority_runner_executes_verified_object_bytes_not_worktree_path(self) -> None:
        text = WORKFLOW.read_text(encoding="utf-8")
        execution_marker = "- name: Build, test, and capture Simulator states"
        self.assertIn(execution_marker, text)

        execution_start = text.index(execution_marker)
        next_step = text.find("\n      - name:", execution_start + len(execution_marker))
        execution = text[execution_start : next_step if next_step != -1 else len(text)]

        self.assertNotRegex(
            execution,
            rf"(?m)^\s*run:\s*{re.escape(PRODUCER_PATH)}\s*$",
            "trusted Capture reopened mutable candidate worktree bytes",
        )
        self.assertIn(f'producer_path="{PRODUCER_PATH}"', execution)
        self.assertIn(f'expected_blob="{PRODUCER_BLOB}"', execution)
        self.assertIn('/usr/bin/git cat-file blob "$expected_blob"', execution)
        self.assertIn('/usr/bin/git hash-object --stdin', execution)
        self.assertIn('producer_bytes="$(' , execution)
        self.assertIn('builtin printf \'%s\' "$producer_bytes"', execution)
        self.assertIn(
            "/bin/bash -c 'source /dev/stdin' \"$GITHUB_WORKSPACE/$producer_path\"",
            execution,
        )
        self.assertGreaterEqual(execution.count("GIT_CONFIG_NOSYSTEM=1"), 2)
        self.assertGreaterEqual(execution.count("GIT_CONFIG_GLOBAL=/dev/null"), 2)
        self.assertGreaterEqual(execution.count("GIT_NO_REPLACE_OBJECTS=1"), 2)

        read_index = execution.index('/usr/bin/git cat-file blob "$expected_blob"')
        hash_index = execution.index('/usr/bin/git hash-object --stdin')
        execute_index = execution.index("/bin/bash -c 'source /dev/stdin'")
        self.assertLess(read_index, hash_index)
        self.assertLess(hash_index, execute_index)

    def test_execution_step_does_not_select_a_different_literal_blob(self) -> None:
        text = WORKFLOW.read_text(encoding="utf-8")
        marker = "- name: Build, test, and capture Simulator states"
        start = text.index(marker)
        end = text.find("\n      - name:", start + len(marker))
        execution = text[start : end if end != -1 else len(text)]
        literals = set(re.findall(r"[0-9a-f]{40}", execution))
        self.assertEqual(literals, {PRODUCER_BLOB})


if __name__ == "__main__":
    unittest.main()
