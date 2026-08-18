#!/usr/bin/env python3
"""Migrate #3082 build-level retirement races to the required manifest review ABI.

Historical retirement/object tests remain byte-for-byte unchanged. Their two
build-level fixtures predate the V17 generated-manifest review argument, so this
file replays those exact race shapes with one stable independently reviewed
manifest subject rather than weakening production build() back to an optional
review authority.
"""
from __future__ import annotations

import contextlib
import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
SCRIPT = ROOT / "scripts/ci/es80_authenticated_stationary_private_review_final_go.py"
SPEC = importlib.util.spec_from_file_location("nembra_final_go_manifest_retirement_migration", SCRIPT)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("Final-GO manifest retirement subject import unavailable")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)

SOURCE = "a" * 40
PR = 3606
REVIEW_ID = 7001
MANIFEST_DIGEST = "1" * 64


def stable_manifest_review(*_args, **_kwargs):
    return {
        "authority": MODULE.MANIFEST_REVIEW_AUTHORITY,
        "reviewID": REVIEW_ID,
        "reviewNodeID": "PRR_manifest_retirement_fixture",
        "reviewBodySHA256": "2" * 64,
        "reviewedAtUTC": "2026-08-18T03:35:00Z",
        "reviewer": MODULE.OWNER,
        "state": "COMMENTED",
        "sourceCommitSHA": SOURCE,
        MODULE.MANIFEST_DIGEST_KEY: MANIFEST_DIGEST,
        "verdict": "accepted",
    }


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
    def api(_path):
        return b"{}", {}

    @staticmethod
    def canon(value: str, _label: str) -> str:
        return value.lower()

    @staticmethod
    def pos(value: int, label: str) -> int:
        if not isinstance(value, int) or isinstance(value, bool) or value <= 0:
            raise MODULE.PrivateReviewGoError(f"{label} invalid")
        return value


@contextlib.contextmanager
def noop(*_args, **_kwargs):
    yield


class ManifestAwareRetirementMigrationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.original_review = MODULE.generated_manifest_review
        self.original_candidate = MODULE._PREDECESSOR_CANDIDATE_GIT_CUSTODY
        self.original_vnode = MODULE._CURRENT_VNODE_AUTHORITY
        self.original_semantic = MODULE._SEMANTIC_BUILD
        self.original_dispatch = MODULE._dispatch_predecessor_physical_reads
        self.original_semantic_adapter = MODULE._SEMANTIC_MODULE._private_environment_adapter
        MODULE.generated_manifest_review = stable_manifest_review

    def tearDown(self) -> None:
        MODULE.generated_manifest_review = self.original_review
        MODULE._PREDECESSOR_CANDIDATE_GIT_CUSTODY = self.original_candidate
        MODULE._CURRENT_VNODE_AUTHORITY = self.original_vnode
        MODULE._SEMANTIC_BUILD = self.original_semantic
        MODULE._dispatch_predecessor_physical_reads = self.original_dispatch
        MODULE._SEMANTIC_MODULE._private_environment_adapter = self.original_semantic_adapter
        self.assertFalse(MODULE._CANDIDATE_RETIRED.get())
        self.assertIsNone(MODULE._ACTIVE_MANIFEST_REVIEW.get())

    def _build(self, root: Path, base: FakeBase):
        original_loader = MODULE.generated._load_base_module
        MODULE.generated._load_base_module = lambda: base
        try:
            return MODULE.build(
                candidate_repo=root,
                source=SOURCE,
                pr=PR,
                generated_manifest_review_id=REVIEW_ID,
            )
        finally:
            MODULE.generated._load_base_module = original_loader

    def test_sealed_build_retires_before_candidate_release_with_manifest_review(self) -> None:
        base = FakeBase()
        events: list[str] = []
        record = {
            "privateFieldInstall": {"installed": True, "fingerprint": "sealed-install"},
            "retainedSignedFieldArtifact": {"sha256": "sealed-artifact"},
            "physicalResultCollected": False,
        }

        with tempfile.TemporaryDirectory(prefix="nembra-finalgo-manifest-handoff-") as temporary:
            root = Path(temporary).resolve(strict=True)
            tracked = root / "A.swift"
            tracked.write_text("accepted\n", encoding="utf-8")

            @contextlib.contextmanager
            def fake_candidate_custody(_base, candidate_repo: Path, source: str):
                self.assertEqual(candidate_repo, root)
                self.assertEqual(source, SOURCE)
                events.append("custody-enter")
                try:
                    yield
                finally:
                    events.append("custody-release-start")
                    tracked.write_text("attacker-after-handoff\n", encoding="utf-8")
                    with self.assertRaisesRegex(MODULE.PrivateReviewGoError, "authority retired"):
                        base.git(root, "status", "--porcelain=v1")
                    with self.assertRaisesRegex(MODULE.PrivateReviewGoError, "authority retired"):
                        MODULE._physical_blob_oid(root, "A.swift", b"100644", "0" * 40)
                    events.append("custody-release-finished")

            def fake_semantic_build(**kwargs):
                self.assertEqual(kwargs["candidate_repo"], root)
                self.assertEqual(kwargs["source"], SOURCE)
                self.assertEqual(kwargs["pr"], PR)
                self.assertIs(kwargs["base_module"], base)
                self.assertEqual(tracked.read_text(encoding="utf-8"), "accepted\n")
                events.append("semantic-build-complete")
                return record

            MODULE._PREDECESSOR_CANDIDATE_GIT_CUSTODY = fake_candidate_custody
            MODULE._CURRENT_VNODE_AUTHORITY = noop
            MODULE._SEMANTIC_BUILD = fake_semantic_build
            result = self._build(root, base)

            self.assertIs(result, record)
            self.assertEqual(tracked.read_text(encoding="utf-8"), "attacker-after-handoff\n")
            self.assertIn(MODULE.MANIFEST_RECORD_KEY, result)
            self.assertLess(events.index("semantic-build-complete"), events.index("custody-release-start"))
            self.assertIs(base.git, base.original_git)
            self.assertIs(base.git_bytes, base.original_git_bytes)

    def test_nested_parent_restore_stays_blocked_with_manifest_review(self) -> None:
        base = FakeBase()
        state = {
            "retired_during_handoff": False,
            "blocked_in_outer_teardown": False,
            "inner_saved_dispatcher": False,
        }

        class Custody:
            def prove_quiet(_self, stage: str) -> None:
                if stage == "candidate authority handoff":
                    with self.assertRaisesRegex(MODULE.PrivateReviewGoError, "authority retired"):
                        base.git(Path("/candidate"), "status", "--porcelain=v1")
                    state["retired_during_handoff"] = True

        @contextlib.contextmanager
        def fake_continuous(_root: Path, _source: str):
            try:
                yield Custody()
            finally:
                with self.assertRaisesRegex(MODULE.PrivateReviewGoError, "authority retired"):
                    base.git(Path("/candidate"), "status", "--porcelain=v1")
                with self.assertRaisesRegex(MODULE.PrivateReviewGoError, "authority retired"):
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

        original_continuous = MODULE._previous._continuous_tracked_tree_custody
        original_parent = MODULE._previous._PARENT_CANDIDATE_GIT_CUSTODY
        original_dispatch_prev = MODULE._previous._dispatch_parent_physical_reads
        try:
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
            with tempfile.TemporaryDirectory(prefix="nembra-finalgo-manifest-retirement-") as temporary:
                result = self._build(Path(temporary), base)
        finally:
            MODULE._previous._dispatch_parent_physical_reads = original_dispatch_prev
            MODULE._previous._PARENT_CANDIDATE_GIT_CUSTODY = original_parent
            MODULE._previous._continuous_tracked_tree_custody = original_continuous

        self.assertFalse(result["physicalResultCollected"])
        self.assertIn(MODULE.MANIFEST_RECORD_KEY, result)
        self.assertTrue(state["inner_saved_dispatcher"])
        self.assertTrue(state["retired_during_handoff"])
        self.assertTrue(state["blocked_in_outer_teardown"])
        self.assertEqual(base.original_calls, 0)
        self.assertIs(base.git, base.original_git)
        self.assertIs(base.git_bytes, base.original_git_bytes)


if __name__ == "__main__":
    unittest.main(verbosity=2)
