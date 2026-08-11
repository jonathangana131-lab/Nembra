#!/usr/bin/env python3
"""Exact exploit-negative replay of #3074 against the selected repaired head."""
from __future__ import annotations

import contextlib
import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
SCRIPT = ROOT / "scripts" / "ci" / "es80_authenticated_stationary_private_review_final_go.py"
SPEC = importlib.util.spec_from_file_location("nembra_final_go_nested_restore_replay_r2", SCRIPT)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("Final-GO subject import unavailable")
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)

DEFEATED_PARENT = "899e5dc5cc5e71617bfe4151cdb1da20c576fbc2"
REPAIRED_PARENT = "36b531b2e7d0c07bb8a63766e5b9fb5779d0a022"


class FakeBase:
    def __init__(self) -> None:
        self.original_calls = 0

        def git(*_args, **_kwargs):
            self.original_calls += 1
            return "ORIGINAL-GIT-REOPENED"

        def git_bytes(*_args, **_kwargs):
            self.original_calls += 1
            return b"ORIGINAL-GIT-BYTES-REOPENED"

        self.git = git
        self.git_bytes = git_bytes
        self.original_git = git
        self.original_git_bytes = git_bytes

    @staticmethod
    def canon(value: str, _label: str) -> str:
        return value.lower()


class RetirementNestedRestoreReplayTests(unittest.TestCase):
    def test_selected_production_parent_is_exact(self) -> None:
        branch_parent = subprocess.check_output(
            ["/usr/bin/git", "-C", str(ROOT), "rev-parse", "HEAD^2"],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip().lower() if self._is_merge_commit() else subprocess.check_output(
            ["/usr/bin/git", "-C", str(ROOT), "merge-base", REPAIRED_PARENT, "HEAD"],
            text=True,
        ).strip().lower()
        self.assertEqual(branch_parent, REPAIRED_PARENT)
        self.assertNotEqual(REPAIRED_PARENT, DEFEATED_PARENT)

    def _is_merge_commit(self) -> bool:
        parents = subprocess.check_output(
            ["/usr/bin/git", "-C", str(ROOT), "rev-list", "--parents", "-n", "1", "HEAD"],
            text=True,
        ).split()
        return len(parents) > 2

    def test_inherited_parent_finally_cannot_reopen_git_before_outer_retirement_exits(self) -> None:
        base = FakeBase()
        state = {
            "retired_during_handoff": False,
            "git_blocked_in_outer_teardown": False,
            "git_bytes_blocked_in_outer_teardown": False,
            "inner_saved_dispatcher": False,
        }
        self_test = self

        class Custody:
            def prove_quiet(self, stage: str) -> None:
                if stage == "candidate authority handoff":
                    with self_test.assertRaisesRegex(MODULE.PrivateReviewGoError, "authority retired"):
                        base.git(Path("/candidate"), "status", "--porcelain=v1")
                    state["retired_during_handoff"] = True

        @contextlib.contextmanager
        def fake_continuous(_root: Path, _source: str):
            try:
                yield Custody()
            finally:
                # Preserve #3074 ordering: this executes only after inherited
                # custody's unconditional restore of its saved Git functions.
                with self_test.assertRaisesRegex(MODULE.PrivateReviewGoError, "authority retired"):
                    base.git(Path("/candidate"), "status", "--porcelain=v1")
                state["git_blocked_in_outer_teardown"] = True
                with self_test.assertRaisesRegex(MODULE.PrivateReviewGoError, "authority retired"):
                    base.git_bytes(Path("/candidate"), "show", "HEAD:A.swift")
                state["git_bytes_blocked_in_outer_teardown"] = True

        @contextlib.contextmanager
        def fake_parent_candidate(_base, _root, _source):
            original_git = base.git
            original_git_bytes = base.git_bytes
            state["inner_saved_dispatcher"] = (
                original_git is not base.original_git
                and original_git_bytes is not base.original_git_bytes
            )
            base.git = lambda *_a, **_k: "PARENT-GUARDED"
            base.git_bytes = lambda *_a, **_k: b"PARENT-GUARDED"
            try:
                yield
            finally:
                # Deliberately unchanged exploit action from #3074.
                base.git = original_git
                base.git_bytes = original_git_bytes

        @contextlib.contextmanager
        def noop(*_args, **_kwargs):
            yield

        original_continuous = MODULE._previous._continuous_tracked_tree_custody
        original_parent = MODULE._previous._PARENT_CANDIDATE_GIT_CUSTODY
        original_dispatch_prev = MODULE._previous._dispatch_parent_physical_reads
        original_dispatch_current = MODULE._dispatch_predecessor_physical_reads
        original_vnode = MODULE._CURRENT_VNODE_AUTHORITY
        original_semantic = MODULE._SEMANTIC_BUILD
        MODULE._previous._continuous_tracked_tree_custody = fake_continuous
        MODULE._previous._PARENT_CANDIDATE_GIT_CUSTODY = fake_parent_candidate
        MODULE._previous._dispatch_parent_physical_reads = noop
        MODULE._dispatch_predecessor_physical_reads = noop
        MODULE._CURRENT_VNODE_AUTHORITY = noop
        MODULE._SEMANTIC_BUILD = lambda **_kwargs: {
            "privateFieldInstall": {"installed": True},
            "retainedSignedFieldArtifact": {"sha256": "sealed"},
            "physicalResultCollected": False,
        }
        try:
            with tempfile.TemporaryDirectory(prefix="nembra-finalgo-nested-restore-replay-r2-") as temporary:
                result = MODULE.build(
                    candidate_repo=Path(temporary),
                    source="a" * 40,
                    base_module=base,
                )
        finally:
            MODULE._SEMANTIC_BUILD = original_semantic
            MODULE._CURRENT_VNODE_AUTHORITY = original_vnode
            MODULE._dispatch_predecessor_physical_reads = original_dispatch_current
            MODULE._previous._dispatch_parent_physical_reads = original_dispatch_prev
            MODULE._previous._PARENT_CANDIDATE_GIT_CUSTODY = original_parent
            MODULE._previous._continuous_tracked_tree_custody = original_continuous

        self.assertFalse(result["physicalResultCollected"])
        self.assertTrue(state["inner_saved_dispatcher"])
        self.assertTrue(state["retired_during_handoff"])
        self.assertTrue(state["git_blocked_in_outer_teardown"])
        self.assertTrue(state["git_bytes_blocked_in_outer_teardown"])
        self.assertEqual(base.original_calls, 0)
        self.assertIs(base.git, base.original_git)
        self.assertIs(base.git_bytes, base.original_git_bytes)
        self.assertFalse(MODULE._CANDIDATE_RETIRED.get())


if __name__ == "__main__":
    unittest.main(verbosity=2)
