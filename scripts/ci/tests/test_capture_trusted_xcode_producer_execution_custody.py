#!/usr/bin/env python3
"""Source regression for trusted Capture producer execution custody.

The authority-producing workflow must never execute mutable candidate pathname bytes. It must read
from the pinned Git object, independently re-hash the exact returned byte subject, and interpret
only those same bytes. The candidate workspace pathname survives solely as `$0` so the frozen
producer's relative ROOT calculation still points at the exact candidate checkout.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]
WORKFLOW = ROOT / ".github/workflows/capture-xcode27-trusted-command.yml"
PRODUCER_PATH = "scripts/ci/xcode27_simulator_capture.sh"
PRODUCER_BLOB = "4e9ae0cb6728dc68d9b8dd43aac7c50128702ed9"


class TrustedProducerExecutionCustodyTests(unittest.TestCase):
    def test_authority_runner_executes_rehashed_pinned_git_bytes_not_mutable_path(self) -> None:
        text = WORKFLOW.read_text(encoding="utf-8")

        custody_marker = "- name: Verify trusted Simulator evidence-producer custody"
        execution_marker = "- name: Build, test, and capture Simulator states"
        self.assertIn(custody_marker, text)
        self.assertIn(execution_marker, text)
        self.assertLess(text.index(custody_marker), text.index(execution_marker))

        self.assertIn(f'producer_path="{PRODUCER_PATH}"', text)
        self.assertIn(f'expected_blob="{PRODUCER_BLOB}"', text)

        execution_start = text.index(execution_marker)
        next_step = text.find("\n      - name:", execution_start + len(execution_marker))
        execution_block = text[execution_start : next_step if next_step != -1 else len(text)]

        self.assertNotRegex(
            execution_block,
            rf"(?m)^\s*run:\s*{re.escape(PRODUCER_PATH)}\s*$",
            "trusted Capture still executes the mutable candidate worktree pathname",
        )
        self.assertIn(
            '/usr/bin/git -C /tmp hash-object -- "$GITHUB_WORKSPACE/$producer_path"',
            execution_block,
        )
        self.assertIn('/usr/bin/git cat-file blob "$expected_blob"', execution_block)
        self.assertIn('/usr/bin/git -C /tmp hash-object --stdin', execution_block)
        self.assertIn('test "$materialized_blob" = "$expected_blob"', execution_block)
        self.assertIn("GIT_CONFIG_NOSYSTEM=1", execution_block)
        self.assertIn("GIT_CONFIG_GLOBAL=/dev/null", execution_block)
        self.assertIn("GIT_NO_REPLACE_OBJECTS=1", execution_block)
        self.assertIn(
            "/bin/bash -p -c 'source /dev/stdin' \"$GITHUB_WORKSPACE/$producer_path\"",
            execution_block,
        )

        materialize = execution_block.index('/usr/bin/git cat-file blob "$expected_blob"')
        rehash = execution_block.index('/usr/bin/git -C /tmp hash-object --stdin')
        compare = execution_block.index('test "$materialized_blob" = "$expected_blob"')
        execute = execution_block.index("/bin/bash -p -c 'source /dev/stdin'")
        self.assertLess(materialize, rehash)
        self.assertLess(rehash, compare)
        self.assertLess(compare, execute)

        blob_literals = re.findall(r"[0-9a-f]{40}", execution_block)
        if blob_literals:
            self.assertIn(PRODUCER_BLOB, blob_literals)


if __name__ == "__main__":
    unittest.main()
