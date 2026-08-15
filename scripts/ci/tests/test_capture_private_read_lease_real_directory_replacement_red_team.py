#!/usr/bin/env python3
"""Exploit-positive witness for real-directory replacement after lease planning.

This is validation-only. SUCCESS means the attacked component-walk implementation
still admits a different real object at the same pathname when an ancestor is
renamed/replaced after planning. It creates no product or physical authority.
"""
from __future__ import annotations

import importlib.util
import inspect
import os
from pathlib import Path
import stat
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[3]
HELPER = REPO / "scripts/ci/capture_selected_xcode_build_orchestrator.py"


def load():
    spec = importlib.util.spec_from_file_location("nembra_real_directory_swap", HELPER)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load selected-Xcode orchestrator")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class CapturePrivateReadLeaseRealDirectoryReplacementRedTeamTests(unittest.TestCase):
    def test_real_directory_replacement_is_admitted_after_plan(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-real-dir-swap-") as raw:
            outer = Path(raw)
            repo = outer / "repo"
            legitimate = repo / "LocalSecrets/TuyaSDK/Build"
            legitimate.mkdir(parents=True)

            planned = helper._lease_paths((legitimate,), repo)
            self.assertIn((legitimate, False), planned)
            accepted_signature = helper._path_signature(legitimate)

            sdk = repo / "LocalSecrets/TuyaSDK"
            accepted_sdk = repo / "LocalSecrets/TuyaSDK.accepted"
            sdk.rename(accepted_sdk)
            replacement = sdk / "Build"
            replacement.mkdir(parents=True)

            # The attacker uses only real directories. O_NOFOLLOW therefore has
            # nothing to reject while the accepted object has changed identity.
            for path in (sdk, replacement):
                metadata = path.lstat()
                self.assertTrue(stat.S_ISDIR(metadata.st_mode))
                self.assertFalse(stat.S_ISLNK(metadata.st_mode))
            replacement_signature = helper._path_signature(replacement)
            self.assertNotEqual(accepted_signature, replacement_signature)

            descriptor = helper._open_pinned_path(legitimate, True)
            try:
                opened_signature = helper._descriptor_signature(descriptor)
            finally:
                os.close(descriptor)

            self.assertEqual(opened_signature, replacement_signature)
            self.assertNotEqual(opened_signature, accepted_signature)

    def test_grant_reopens_replacement_selected_after_real_plan(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-real-dir-grant-") as raw:
            outer = Path(raw)
            repo = outer / "repo"
            legitimate = repo / "LocalSecrets/TuyaSDK/Build"
            legitimate.mkdir(parents=True)
            original_lease_paths = helper._lease_paths
            accepted_signature = None
            replacement_signature = None
            probed_signatures: list[tuple[int, int, int]] = []

            def raced_lease_paths(subjects, repository):
                nonlocal accepted_signature, replacement_signature
                planned = original_lease_paths(subjects, repository)
                self.assertIn((legitimate, False), planned)
                accepted_signature = helper._path_signature(legitimate)

                sdk = repo / "LocalSecrets/TuyaSDK"
                sdk.rename(repo / "LocalSecrets/TuyaSDK.accepted")
                replacement = sdk / "Build"
                replacement.mkdir(parents=True)
                replacement_signature = helper._path_signature(replacement)
                self.assertNotEqual(accepted_signature, replacement_signature)

                # Narrow the portable probe to the exact planned subject. The real
                # planner above already completed before the race was injected.
                return ((legitimate, False),)

            class AdmissionObserved(RuntimeError):
                pass

            def observe_first_acl_listing(descriptor: int) -> str:
                probed_signatures.append(helper._descriptor_signature(descriptor))
                os.close(descriptor)
                raise AdmissionObserved("descriptor reached ACL admission")

            helper._lease_paths = raced_lease_paths
            helper._acl_listing = observe_first_acl_listing
            lease = helper._PrivateReadLease((legitimate,), repo)
            with self.assertRaises(AdmissionObserved):
                lease.grant("nembra_red_team")

            self.assertIsNotNone(accepted_signature)
            self.assertIsNotNone(replacement_signature)
            self.assertEqual(probed_signatures, [replacement_signature])
            self.assertNotEqual(probed_signatures[0], accepted_signature)

    def test_opener_has_no_planned_identity_input(self) -> None:
        helper = load()
        parameters = tuple(inspect.signature(helper._open_pinned_path).parameters)
        self.assertEqual(parameters, ("path", "is_directory"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
