#!/usr/bin/env python3
"""Expected-red witness for candidate Git reopening during sealed-handoff teardown."""
from __future__ import annotations

import contextlib
import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
SCRIPT = ROOT / "scripts" / "ci" / "es80_authenticated_stationary_private_review_final_go.py"
SPEC = importlib.util.spec_from_file_location("nembra_final_go_nested_restore_redteam", SCRIPT)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("Final-GO subject import unavailable")
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


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


class RetirementNestedRestoreRedTeamTests(unittest.TestCase):
    def test_inherited_parent_finally_reopens_git_before_outer_retirement_exits(self) -> None:
        base = FakeBase()
        state = {"retired_during_handoff": False, "reopened_in_outer_teardown": False}

        class Custody:
            def prove_quiet(self, stage: str) -> None:
                if stage == "candidate authority handoff":
                    with self_test.assertRaises(MODULE.PrivateReviewGoError):
                        base.git(Path("/candidate"), "status", "--porcelain=v1")
                    state["retired_during_handoff"] = True

        self_test = self

        @contextlib.contextmanager
        def fake_continuous(_root: Path, _source: str):
            try:
                yield Custody()
            finally:
                result = base.git(Path("/candidate"), "status", "--porcelain=v1")
                state["reopened_in_outer_teardown"] = result == "ORIGINAL-GIT-REOPENED"

        @contextlib.contextmanager
        def fake_parent_candidate(_base, _root, _source):
            original_git = base.git
            original_git_bytes = base.git_bytes
            base.git = lambda *_a, **_k: "PARENT-GUARDED"
            base.git_bytes = lambda *_a, **_k: b"PARENT-GUARDED"
            try:
                yield
            finally:
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
            with tempfile.TemporaryDirectory(prefix="nembra-finalgo-nested-restore-") as temporary:
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
        self.assertTrue(state["retired_during_handoff"])
        self.assertTrue(
            state["reopened_in_outer_teardown"],
            "candidate Git remained fenced after inherited parent finally; exploit did not reproduce",
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
