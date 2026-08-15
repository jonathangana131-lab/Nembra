#!/usr/bin/env python3
"""Exploit-positive witness for mixed-generation private read-lease planning."""

from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import tempfile
import unittest
from unittest import mock

REPOSITORY = Path(__file__).resolve().parents[3]
ORCHESTRATOR = REPOSITORY / "scripts/ci/capture_selected_xcode_build_orchestrator.py"


def load():
    spec = importlib.util.spec_from_file_location(
        "nembra_private_read_lease_mixed_generation_red_team", ORCHESTRATOR
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load selected-Xcode build orchestrator")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class CapturePrivateReadLeaseMixedGenerationRedTeamTests(unittest.TestCase):
    def test_planning_can_mix_original_ancestor_with_replacement_descendant_and_grant_both(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-lease-mixed-generation-") as temporary:
            outer = Path(temporary)
            outer.chmod(0o711)
            repo = outer / "repo"
            subject = repo / "LocalSecrets/TuyaSDK/Build"
            subject.mkdir(parents=True)
            accepted_file = subject / "accepted.bin"
            accepted_file.write_bytes(b"accepted\n")

            sdk = repo / "LocalSecrets/TuyaSDK"
            original_sdk = repo / "LocalSecrets/TuyaSDK.accepted"
            original_sdk_signature = helper._path_signature(sdk)
            original_build_signature = helper._path_signature(subject)

            attacker_sdk = outer / "attacker/TuyaSDK"
            attacker_build = attacker_sdk / "Build"
            attacker_build.mkdir(parents=True)
            substituted_file = attacker_build / "substituted.bin"
            substituted_file.write_bytes(b"substituted\n")
            substituted_signature = helper._path_signature(substituted_file)

            real_subject_entries = helper._subject_entries
            swapped_during_plan = False

            def subject_entries_with_mid_plan_swap(path: Path, *, include_signatures: bool = False):
                nonlocal swapped_during_plan
                if Path(path) == subject and not swapped_during_plan:
                    # _lease_paths has already lstat'ed/admitted every lexical ancestor,
                    # including TuyaSDK and Build. Replace that real tree immediately
                    # before its recursive subject enumeration starts.
                    sdk.rename(original_sdk)
                    attacker_sdk.rename(sdk)
                    swapped_during_plan = True
                return real_subject_entries(path, include_signatures=include_signatures)

            with mock.patch.object(
                helper,
                "_subject_entries",
                side_effect=subject_entries_with_mid_plan_swap,
            ):
                plan = helper._lease_paths((subject,), repo, include_signatures=True)

            self.assertTrue(swapped_during_plan)
            plan_by_path = {
                path: signature for path, _host_only, signature in plan
            }
            # The same plan now binds an original ancestor/root generation and an
            # attacker replacement descendant generation.
            self.assertEqual(plan_by_path[sdk], original_sdk_signature)
            self.assertEqual(plan_by_path[subject], original_build_signature)
            canonical_substituted = subject / "substituted.bin"
            self.assertEqual(plan_by_path[canonical_substituted], substituted_signature)
            self.assertNotIn(accepted_file, plan_by_path)

            def activate_original() -> None:
                if sdk.exists():
                    self.assertFalse(attacker_sdk.exists())
                    sdk.rename(attacker_sdk)
                if original_sdk.exists():
                    original_sdk.rename(sdk)

            def activate_attacker() -> None:
                if sdk.exists():
                    self.assertFalse(original_sdk.exists())
                    sdk.rename(original_sdk)
                if attacker_sdk.exists():
                    attacker_sdk.rename(sdk)

            real_open = helper._open_pinned_path
            opened: list[tuple[Path, tuple[int, int, int]]] = []

            def scheduled_open(
                path: Path,
                is_directory: bool,
                expected_signature: tuple[int, int, int] | None = None,
            ) -> int:
                path = Path(path)
                # Model a same-authority actor switching only between production
                # admission calls. The real root-anchored opener still performs every
                # component walk and every expected-signature comparison itself.
                if path in (sdk, subject):
                    activate_original()
                elif path == canonical_substituted:
                    activate_attacker()
                descriptor = real_open(path, is_directory, expected_signature)
                opened.append((path, helper._descriptor_signature(descriptor)))
                return descriptor

            principal = "nembrabuildmixedgeneration"
            acl_added: set[int] = set()

            def fake_listing(descriptor: int) -> str:
                if descriptor in acl_added:
                    return f" 0: user:{principal} allow read\n"
                return ""

            def fake_chmod(descriptor: int, operation: str, _acl: str) -> None:
                if operation == "+a":
                    acl_added.add(descriptor)
                elif operation == "-a":
                    acl_added.discard(descriptor)
                else:
                    raise AssertionError(operation)

            lease = helper._PrivateReadLease((subject,), repo)
            with (
                mock.patch.object(helper, "_lease_paths", return_value=plan),
                mock.patch.object(helper, "_open_pinned_path", side_effect=scheduled_open),
                mock.patch.object(helper, "_acl_listing", side_effect=fake_listing),
                mock.patch.object(helper, "_chmod_acl", side_effect=fake_chmod),
            ):
                lease.grant(principal)

            opened_by_path = dict(opened)
            self.assertEqual(opened_by_path[sdk], original_sdk_signature)
            self.assertEqual(opened_by_path[subject], original_build_signature)
            self.assertEqual(opened_by_path[canonical_substituted], substituted_signature)
            self.assertNotIn(accepted_file, opened_by_path)

            # No real ACL was changed by this portable witness. Close production-opened
            # descriptors directly rather than asking revoke() to reason about the
            # deliberately mixed canonical pathname generation.
            for record in lease._opened:
                os.close(int(record["descriptor"]))
            lease._opened.clear()
            lease._principal = ""


if __name__ == "__main__":
    unittest.main(verbosity=2)
