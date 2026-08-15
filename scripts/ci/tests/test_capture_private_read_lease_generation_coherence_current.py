#!/usr/bin/env python3
"""Current-product replay of the canonical #3401 mixed-generation lease attack."""
from __future__ import annotations

import importlib.util
import inspect
from pathlib import Path
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[3]
HELPER = REPO / "scripts/ci/capture_selected_xcode_build_orchestrator.py"


def load():
    spec = importlib.util.spec_from_file_location("nembra_generation_coherence_current", HELPER)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load selected-Xcode orchestrator")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class CapturePrivateReadLeaseGenerationCoherenceCurrentTests(unittest.TestCase):
    def test_canonical_root_A_to_B_swap_cannot_create_mixed_held_lease(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-generation-coherence-current-") as raw:
            outer = Path(raw)
            repo = outer / "repo"
            subject = repo / "LocalSecrets/TuyaSDK/Build"
            subject.mkdir(parents=True)
            (subject / "private.fixture").write_text("original\n", encoding="utf-8")

            attacker_hold = outer / "repo-attacker-hold"
            attacker_subject = attacker_hold / "LocalSecrets/TuyaSDK/Build"
            attacker_subject.mkdir(parents=True)
            (attacker_subject / "private.fixture").write_text("replacement\n", encoding="utf-8")

            original_root = helper._path_signature(repo)
            original_subject = helper._path_signature(subject)
            attacker_root = helper._path_signature(attacker_hold)
            attacker_subject_signature = helper._path_signature(attacker_subject)
            self.assertNotEqual(original_root, attacker_root)
            self.assertNotEqual(original_subject, attacker_subject_signature)

            original_hold = outer / "repo-original-hold"
            original_require = helper._require_real_directory
            original_acl_listing = helper._acl_listing
            original_chmod_acl = helper._chmod_acl
            injected = False
            acl_state: dict[int, str] = {}

            def raced_require(path: Path, label: str = "private read-lease path"):
                nonlocal injected
                metadata = original_require(path, label)
                if not injected and Path(path) == repo:
                    repo.rename(original_hold)
                    attacker_hold.rename(repo)
                    injected = True
                return metadata

            def fake_acl_listing(descriptor: int) -> str:
                return acl_state.get(descriptor, "")

            def fake_chmod_acl(descriptor: int, operation: str, acl: str) -> None:
                if operation == "+a":
                    acl_state[descriptor] = f"0: {acl}"
                elif operation == "-a":
                    acl_state[descriptor] = ""
                else:
                    raise AssertionError(f"unexpected ACL operation: {operation}")

            lease = helper._PrivateReadLease((subject,), repo)
            helper._require_real_directory = raced_require
            helper._acl_listing = fake_acl_listing
            helper._chmod_acl = fake_chmod_acl
            try:
                try:
                    lease.grant("nembra-build")
                except helper.SelectedXcodeBuildOrchestratorError:
                    self.assertTrue(injected)
                    self.assertFalse(lease._opened)
                    self.assertEqual(lease._principal, "")
                    self.assertFalse(any(acl_state.values()))
                    return

                self.assertTrue(injected)
                opened = {
                    Path(record["path"]): helper._descriptor_signature(int(record["descriptor"]))
                    for record in lease._opened
                }
                pair = (opened[repo], opened[subject])
                self.assertIn(
                    pair,
                    (
                        (original_root, original_subject),
                        (attacker_root, attacker_subject_signature),
                    ),
                    f"mixed held generation admitted: {pair}",
                )
            finally:
                try:
                    lease.revoke(suppress_errors=False)
                finally:
                    helper._require_real_directory = original_require
                    helper._acl_listing = original_acl_listing
                    helper._chmod_acl = original_chmod_acl
            self.assertFalse(any(acl_state.values()))
            self.assertFalse(lease._opened)
            self.assertEqual(lease._principal, "")

    def test_production_grant_uses_held_descriptor_coherence_not_signature_reopen(self) -> None:
        helper = load()
        planning = inspect.getsource(helper._lease_paths)
        verifier = inspect.getsource(helper._verify_descriptor_plan)
        grant = inspect.getsource(helper._PrivateReadLease.grant)
        self.assertIn("include_descriptors", planning)
        self.assertIn("_verify_descriptor_plan", planning)
        self.assertIn("_open_pinned_child", verifier)
        self.assertIn("include_descriptors=True", grant)
        self.assertNotIn("include_signatures=True", grant)


if __name__ == "__main__":
    unittest.main(verbosity=2)
