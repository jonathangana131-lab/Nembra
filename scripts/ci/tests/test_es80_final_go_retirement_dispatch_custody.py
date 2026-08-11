#!/usr/bin/env python3
"""Permanent acceptance for Final-GO retirement-aware Git dispatch custody.

#3074 proved an inherited candidate context can restore the function objects it
captured before retirement and thereby reopen candidate Git during outer watcher
teardown. The repair installs stable retirement-aware dispatchers *before* that
context enters, so every nested restore target remains fail-closed after the
sealed handoff until the outer retirement boundary itself exits.
"""
from __future__ import annotations

import contextlib
import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
SCRIPT = ROOT / "scripts" / "ci" / "es80_authenticated_stationary_private_review_final_go.py"
SPEC = importlib.util.spec_from_file_location("nembra_final_go_retirement_dispatch_subject", SCRIPT)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("Final-GO subject import unavailable")
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)

EXPECTED_PARENT = "cb36f9265f08708c8e47564f62f4857aeae7af0f"
EXPECTED_PARENT_BLOB = "baef9de23a680bedf16f9f7b367f45f7710ac0c6"


class FakeBase:
    def __init__(self) -> None:
        self.original_calls = 0

        def git(*_args, **_kwargs):
            self.original_calls += 1
            return "ORIGINAL-GIT"

        def git_bytes(*_args, **_kwargs):
            self.original_calls += 1
            return b"ORIGINAL-GIT-BYTES"

        self.git = git
        self.git_bytes = git_bytes
        self.original_git = git
        self.original_git_bytes = git_bytes

    @staticmethod
    def canon(value: str, _label: str) -> str:
        return value.lower()


class RetirementDispatchCustodyTests(unittest.TestCase):
    def test_exact_continuous_custody_parent_remains_pinned(self) -> None:
        self.assertEqual(MODULE.PREDECESSOR_SOURCE, EXPECTED_PARENT)
        self.assertEqual(MODULE.PREDECESSOR_MODULE_GIT_BLOB, EXPECTED_PARENT_BLOB)
        payload = MODULE._capture_predecessor_blob(ROOT)
        self.assertEqual(
            MODULE._canonical_git_blob_oid(payload, EXPECTED_PARENT_BLOB),
            EXPECTED_PARENT_BLOB,
        )

    def test_dispatcher_forwards_before_retirement_and_blocks_after(self) -> None:
        base = FakeBase()
        record = {
            "privateFieldInstall": {"installed": True},
            "retainedSignedFieldArtifact": {"sha256": "sealed"},
            "physicalResultCollected": False,
        }
        with MODULE._CandidateRetirementBoundary(base) as boundary:
            self.assertEqual(base.git(Path("/candidate"), "status"), "ORIGINAL-GIT")
            self.assertEqual(base.original_calls, 1)
            boundary.retire(record)
            with self.assertRaisesRegex(MODULE.PrivateReviewGoError, "authority retired"):
                base.git(Path("/candidate"), "status")
            with self.assertRaisesRegex(MODULE.PrivateReviewGoError, "authority retired"):
                base.git_bytes(Path("/candidate"), "show", "HEAD:A.swift")
            self.assertEqual(base.original_calls, 1)
        self.assertIs(base.git, base.original_git)
        self.assertIs(base.git_bytes, base.original_git_bytes)
        self.assertFalse(MODULE._CANDIDATE_RETIRED.get())

    def test_nested_parent_restore_cannot_reopen_git_during_outer_teardown(self) -> None:
        base = FakeBase()
        state = {
            "retired_during_handoff": False,
            "blocked_in_outer_teardown": False,
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
                with self_test.assertRaisesRegex(MODULE.PrivateReviewGoError, "authority retired"):
                    base.git(Path("/candidate"), "status", "--porcelain=v1")
                with self_test.assertRaisesRegex(MODULE.PrivateReviewGoError, "authority retired"):
                    base.git_bytes(Path("/candidate"), "show", "HEAD:A.swift")
                state["blocked_in_outer_teardown"] = True

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
            with tempfile.TemporaryDirectory(prefix="nembra-finalgo-retirement-dispatch-") as temporary:
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
        self.assertTrue(state["blocked_in_outer_teardown"])
        self.assertEqual(base.original_calls, 0)
        self.assertIs(base.git, base.original_git)
        self.assertIs(base.git_bytes, base.original_git_bytes)
        self.assertFalse(MODULE._CANDIDATE_RETIRED.get())


if __name__ == "__main__":
    unittest.main(verbosity=2)
