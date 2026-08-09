#!/usr/bin/env python3
"""Expected-red V14 regression for trusted Capture runner worktree custody.

Binding the candidate commit's Git blob is necessary but not sufficient. The owner-commanded
workflow runs multiple candidate-controlled validation steps after checkout and before executing the
Simulator evidence producer. Any such step can rewrite the working-tree runner without changing
HEAD. The trusted workflow must therefore re-bind both committed and actual worktree bytes in the
final step immediately before authority execution.
"""
from __future__ import annotations

from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]
WORKFLOW = ROOT / ".github/workflows/capture-xcode27-trusted-command.yml"
SUBJECT = ROOT / "scripts/ci/es80_today_trusted_capture_xcode_subject.py"
RUNNER_PATH = "scripts/ci/xcode27_simulator_capture.sh"
VERIFY_STEP = "      - name: Verify trusted Simulator evidence-producer worktree custody"
RUN_STEP = "      - name: Build, test, and capture Simulator states"


class TrustedCaptureRunnerWorktreeCustodyExpectedRedTests(unittest.TestCase):
    def setUp(self) -> None:
        self.workflow = WORKFLOW.read_text(encoding="utf-8")
        subject = SUBJECT.read_text(encoding="utf-8")
        match = re.search(
            r'^TRUSTED_SIMULATOR_EVIDENCE_PRODUCER_BLOB_SHA\s*=\s*"([0-9a-f]{40})"\s*$',
            subject,
            re.MULTILINE,
        )
        self.assertIsNotNone(match, "trusted subject has no canonical 40-hex producer blob pin")
        assert match is not None
        self.approved_blob = match.group(1)

    def _guard(self) -> str:
        self.assertIn(
            VERIFY_STEP,
            self.workflow,
            "trusted Mac workflow never verifies the checked-out runner worktree bytes",
        )
        self.assertIn(RUN_STEP, self.workflow)
        verify = self.workflow.index(VERIFY_STEP)
        execute = self.workflow.index(RUN_STEP)
        self.assertLess(verify, execute, "runner custody verification occurs after authority execution")
        guard = self.workflow[verify:execute]
        self.assertNotIn(
            "\n      - name:",
            guard,
            "another workflow step can mutate the runner after custody verification and before execution",
        )
        return guard

    def test_final_pre_execution_guard_binds_committed_and_worktree_runner_bytes(self) -> None:
        guard = self._guard()
        self.assertIn(self.approved_blob, guard, "workflow guard does not carry the independently reviewed runner blob pin")
        self.assertIn(f"HEAD:{RUNNER_PATH}", guard, "workflow guard never resolves the committed runner blob")
        self.assertRegex(
            guard,
            rf"hash-object[^\n]*--no-filters[^\n]*{re.escape(RUNNER_PATH)}",
            "workflow guard never derives the literal worktree runner Git blob",
        )
        self.assertGreaterEqual(
            guard.count("/usr/bin/env -i"),
            2,
            "committed/worktree Git identity checks must not inherit caller Git environment authority",
        )
        for required in (
            "PATH=/usr/bin:/bin",
            "HOME=/tmp",
            "LC_ALL=C",
            "GIT_CONFIG_NOSYSTEM=1",
            "GIT_CONFIG_GLOBAL=/dev/null",
            "GIT_NO_REPLACE_OBJECTS=1",
        ):
            self.assertIn(required, guard, f"closed Git custody is missing {required}")
        self.assertRegex(
            guard,
            rf"test\s+!\s+-L\s+[^\n]*{re.escape(RUNNER_PATH)}",
            "workflow guard does not reject a symlinked authority-producing runner path",
        )
        self.assertRegex(
            guard,
            rf"test\s+-f\s+[^\n]*{re.escape(RUNNER_PATH)}",
            "workflow guard does not require one regular authority-producing runner file",
        )

    def test_guard_uses_one_pin_for_commit_worktree_and_final_go_subject(self) -> None:
        guard = self._guard()
        # The same reviewed Git object must be the workflow's runtime custody target and the
        # Final-GO verifier's durable subject. A second literal 40-hex authority silently creates
        # two acceptance universes.
        literals = set(re.findall(r"\b[0-9a-f]{40}\b", guard))
        self.assertEqual(
            literals,
            {self.approved_blob},
            "workflow worktree custody and Final-GO producer subject do not share one exact blob pin",
        )


if __name__ == "__main__":
    unittest.main()
