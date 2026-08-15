#!/usr/bin/env python3
"""Exploit-positive witness for real-directory substitution after lease planning."""

from __future__ import annotations

import importlib.util
import inspect
import os
from pathlib import Path
import tempfile
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
ORCHESTRATOR = REPOSITORY / "scripts/ci/capture_selected_xcode_build_orchestrator.py"


def load():
    spec = importlib.util.spec_from_file_location(
        "nembra_private_read_lease_real_directory_swap_red_team", ORCHESTRATOR
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load selected-Xcode build orchestrator")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class CapturePrivateReadLeaseRealDirectorySwapRedTeamTests(unittest.TestCase):
    def test_planned_real_directory_can_be_replaced_without_symlink_and_still_open(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-real-directory-swap-") as temporary:
            outer = Path(temporary)
            repo = outer / "repo"
            legitimate = repo / "LocalSecrets/TuyaSDK/Build"
            legitimate.mkdir(parents=True)
            (legitimate / "accepted.bin").write_bytes(b"accepted\n")

            planned = helper._lease_paths((legitimate,), repo)
            self.assertIn((legitimate, False), planned)
            accepted_signature = helper._path_signature(legitimate)

            sdk = repo / "LocalSecrets/TuyaSDK"
            original = repo / "LocalSecrets/TuyaSDK.accepted"
            sdk.rename(original)

            attacker_sdk = outer / "attacker/TuyaSDK"
            attacker_build = attacker_sdk / "Build"
            attacker_build.mkdir(parents=True)
            (attacker_build / "substituted.bin").write_bytes(b"substituted\n")
            attacker_signature = helper._path_signature(attacker_build)
            self.assertNotEqual(attacker_signature, accepted_signature)

            # Move a normal real directory into the admitted canonical pathname. There
            # is no symlink for O_NOFOLLOW to reject.
            attacker_sdk.rename(sdk)
            self.assertFalse(sdk.is_symlink())
            self.assertFalse(legitimate.is_symlink())

            descriptor = helper._open_pinned_path(legitimate, True)
            try:
                opened_signature = helper._descriptor_signature(descriptor)
                self.assertEqual(opened_signature, attacker_signature)
                self.assertNotEqual(opened_signature, accepted_signature)
            finally:
                os.close(descriptor)

    def test_current_plan_does_not_transport_admitted_object_identity_to_opener(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-real-directory-plan-shape-") as temporary:
            repo = Path(temporary) / "repo"
            subject = repo / "LocalSecrets/TuyaSDK/Build"
            subject.mkdir(parents=True)
            entries = helper._lease_paths((subject,), repo)
            self.assertTrue(entries)
            self.assertTrue(all(len(entry) == 2 for entry in entries))

        parameters = inspect.signature(helper._open_pinned_path).parameters
        self.assertEqual(tuple(parameters), ("path", "is_directory"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
