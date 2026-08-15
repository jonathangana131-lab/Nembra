#!/usr/bin/env python3
"""Exploit-positive oracle for mixed-generation private read-lease planning."""
from __future__ import annotations

import importlib.util
import inspect
import os
from pathlib import Path
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[3]
HELPER = REPO / "scripts/ci/capture_selected_xcode_build_orchestrator.py"


def load():
    spec = importlib.util.spec_from_file_location("nembra_plan_generation_split", HELPER)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load selected-Xcode orchestrator")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class CapturePrivateReadLeasePlanGenerationSplitRedTeamTests(unittest.TestCase):
    def test_actual_grant_can_admit_root_A_and_descendants_B_from_one_raced_plan(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-plan-generation-split-") as raw:
            outer = Path(raw)
            repo = outer / "repo"
            original_subject = repo / "LocalSecrets/TuyaSDK/Build"
            original_subject.mkdir(parents=True)
            (original_subject / "private.fixture").write_text("original\n", encoding="utf-8")

            attacker_hold = outer / "repo-attacker-hold"
            attacker_subject = attacker_hold / "LocalSecrets/TuyaSDK/Build"
            attacker_subject.mkdir(parents=True)
            (attacker_subject / "private.fixture").write_text("replacement\n", encoding="utf-8")

            original_root_signature = helper._path_signature(repo)
            original_subject_signature = helper._path_signature(original_subject)
            attacker_root_signature = helper._path_signature(attacker_hold)
            attacker_subject_signature = helper._path_signature(attacker_subject)
            self.assertNotEqual(original_root_signature, attacker_root_signature)
            self.assertNotEqual(original_subject_signature, attacker_subject_signature)

            original_hold = outer / "repo-original-hold"
            original_require = helper._require_real_directory
            original_open = helper._open_pinned_path
            original_acl_listing = helper._acl_listing
            original_chmod_acl = helper._chmod_acl
            injected = False
            acl_state: dict[int, str] = {}

            def ensure_original_at_repo() -> None:
                if original_hold.exists():
                    if attacker_hold.exists():
                        raise AssertionError("attacker hold unexpectedly occupied before swap to original")
                    repo.rename(attacker_hold)
                    original_hold.rename(repo)

            def ensure_attacker_at_repo() -> None:
                if attacker_hold.exists():
                    if original_hold.exists():
                        raise AssertionError("original hold unexpectedly occupied before swap to attacker")
                    repo.rename(original_hold)
                    attacker_hold.rename(repo)

            def raced_require(path: Path, label: str = "private read-lease path"):
                nonlocal injected
                metadata = original_require(path, label)
                if not injected and Path(path) == repo:
                    # The planner has already accepted repo A's identity. Replace the
                    # pathname with an ordinary real repo B before it walks subject
                    # ancestry. No symlink is involved in either tree.
                    repo.rename(original_hold)
                    attacker_hold.rename(repo)
                    injected = True
                return metadata

            def raced_open(path: Path, is_directory: bool, expected_signature=None):
                candidate = Path(path)
                if candidate == repo and expected_signature == original_root_signature:
                    # Admit the root object captured at the beginning of planning.
                    ensure_original_at_repo()
                else:
                    try:
                        candidate.relative_to(repo)
                    except ValueError:
                        pass
                    else:
                        # Descendant identities were collected only after the planner
                        # had been raced onto repo B. Restore B before each descendant
                        # descriptor admission so every final-object identity check can
                        # still pass individually.
                        ensure_attacker_at_repo()
                return original_open(candidate, is_directory, expected_signature)

            def fake_acl_listing(descriptor: int) -> str:
                return acl_state.get(descriptor, "")

            def fake_chmod_acl(descriptor: int, operation: str, acl: str) -> None:
                if operation == "+a":
                    acl_state[descriptor] = f"0: {acl}"
                elif operation == "-a":
                    acl_state[descriptor] = ""
                else:
                    raise AssertionError(f"unexpected ACL operation: {operation}")

            lease = helper._PrivateReadLease((original_subject,), repo)
            helper._require_real_directory = raced_require
            helper._open_pinned_path = raced_open
            helper._acl_listing = fake_acl_listing
            helper._chmod_acl = fake_chmod_acl
            try:
                # Exploit-positive success: current production grant accepts one lease
                # whose repository-root descriptor is from A while its nominal subject
                # descriptor is from B. Per-entry dev/inode/type checks all succeed;
                # there is no coherent descriptor-rooted plan generation tying them
                # together.
                lease.grant("nembra-build")
                self.assertTrue(injected)
                opened = {
                    Path(record["path"]): helper._descriptor_signature(int(record["descriptor"]))
                    for record in lease._opened
                }
                self.assertEqual(opened[repo], original_root_signature)
                self.assertEqual(opened[original_subject], attacker_subject_signature)
                self.assertNotEqual(opened[repo], attacker_root_signature)
                self.assertNotEqual(opened[original_subject], original_subject_signature)
            finally:
                try:
                    lease.revoke(suppress_errors=True)
                finally:
                    helper._require_real_directory = original_require
                    helper._open_pinned_path = original_open
                    helper._acl_listing = original_acl_listing
                    helper._chmod_acl = original_chmod_acl

    def test_source_still_plans_by_path_then_opens_each_entry_independently(self) -> None:
        helper = load()
        planning = inspect.getsource(helper._lease_paths)
        grant = inspect.getsource(helper._PrivateReadLease.grant)
        opener = inspect.getsource(helper._open_pinned_path)

        self.assertIn("repo_metadata = _require_real_directory(repo", planning)
        self.assertIn("cursor.lstat()", planning)
        self.assertIn("_subject_entries(subject, include_signatures=True)", planning)
        self.assertIn("include_signatures=True", grant)
        self.assertIn("_open_pinned_path(path, is_directory, expected_signature)", grant)
        self.assertIn("expected_signature", opener)
        self.assertNotIn("expected_ancestor_signatures", opener)


if __name__ == "__main__":
    unittest.main(verbosity=2)
