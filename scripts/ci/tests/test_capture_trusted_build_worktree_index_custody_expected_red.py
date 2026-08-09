#!/usr/bin/env python3
"""Expected-red V14 regression for exact-source worktree/index custody.

The frozen Simulator producer checks `git status --porcelain` before building. Git's index flags can
make that check report clean while tracked worktree bytes differ from HEAD. Because the trusted
workflow runs candidate-controlled validation surfaces before the producer, exact-head authority
must reject or neutralize hidden index flags at the final build boundary rather than trusting a
candidate-owned index state.
"""
from __future__ import annotations

from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
WORKFLOW = ROOT / ".github/workflows/capture-xcode27-trusted-command.yml"
RUNNER = ROOT / "scripts/ci/xcode27_simulator_capture.sh"
AUTHORITY_STEP = "      - name: Build, test, and capture Simulator states"


class TrustedBuildWorktreeIndexCustodyExpectedRedTests(unittest.TestCase):
    def test_git_assume_unchanged_can_hide_a_tracked_source_rewrite(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory)
            subprocess.run(["git", "init", "-q"], cwd=repo, check=True)
            subprocess.run(["git", "config", "user.email", "nembra@example.invalid"], cwd=repo, check=True)
            subprocess.run(["git", "config", "user.name", "Nembra QA"], cwd=repo, check=True)
            source = repo / "Tracked.swift"
            source.write_text("let authority = 1\n", encoding="utf-8")
            subprocess.run(["git", "add", "Tracked.swift"], cwd=repo, check=True)
            subprocess.run(["git", "commit", "-qm", "fixture"], cwd=repo, check=True)

            subprocess.run(
                ["git", "update-index", "--assume-unchanged", "Tracked.swift"],
                cwd=repo,
                check=True,
            )
            source.write_text("let authority = 999\n", encoding="utf-8")

            status = subprocess.check_output(
                ["git", "status", "--porcelain=v1", "--untracked-files=all"],
                cwd=repo,
                text=True,
            )
            self.assertEqual(status, "", "attack witness no longer bypasses porcelain cleanliness")
            self.assertEqual(source.read_text(encoding="utf-8"), "let authority = 999\n")
            self.assertEqual(
                subprocess.check_output(["git", "ls-files", "-v", "Tracked.swift"], cwd=repo, text=True),
                "h Tracked.swift\n",
            )

    def test_current_frozen_runner_relies_on_index_sensitive_porcelain_cleanliness(self) -> None:
        source = RUNNER.read_text(encoding="utf-8")
        self.assertIn('git status --porcelain=v1 --untracked-files=all', source)
        self.assertNotIn("--no-assume-unchanged", source)
        self.assertNotIn("--no-skip-worktree", source)

    def test_trusted_authority_step_rejects_hidden_index_flags_before_build(self) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn(AUTHORITY_STEP, workflow)
        start = workflow.index(AUTHORITY_STEP)
        remainder = workflow[start + len(AUTHORITY_STEP):]
        next_step = remainder.find("\n      - name: ")
        step = remainder if next_step < 0 else remainder[:next_step]

        # This deliberately allows implementation freedom. A repair may reject hidden flags or
        # normalize them, but it must explicitly handle both mechanisms Git uses to hide tracked
        # worktree divergence from ordinary status: assume-unchanged and skip-worktree.
        handles_assume = (
            "--no-assume-unchanged" in step
            or "assume-unchanged" in step
            or re.search(r"git\s+ls-files\s+-v", step) is not None
        )
        handles_skip = (
            "--no-skip-worktree" in step
            or "skip-worktree" in step
            or re.search(r"git\s+ls-files\s+-v", step) is not None
        )
        self.assertTrue(
            handles_assume,
            "trusted build boundary does not reject/neutralize assume-unchanged index authority",
        )
        self.assertTrue(
            handles_skip,
            "trusted build boundary does not reject/neutralize skip-worktree index authority",
        )


if __name__ == "__main__":
    unittest.main()
