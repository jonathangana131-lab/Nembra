#!/usr/bin/env python3
"""Exploit-positive oracle for plan-to-open real-directory replacement."""
from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[3]
HELPER = REPO / "scripts/ci/capture_selected_xcode_build_orchestrator.py"


def load():
    spec = importlib.util.spec_from_file_location("nembra_real_dir_swap", HELPER)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load selected-Xcode orchestrator")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class CapturePrivateReadLeaseRealDirectorySwapTests(unittest.TestCase):
    def test_real_directory_replacement_after_plan_is_accepted_by_current_opener(self) -> None:
        """Green means the current plan->open continuity gap is mechanically reproduced."""
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-real-directory-swap-") as raw:
            outer = Path(raw)
            repo = outer / "repo"
            subject = repo / "LocalSecrets/TuyaSDK/Build"
            subject.mkdir(parents=True)

            planned = helper._lease_paths((subject,), repo)
            self.assertIn((subject, False), planned)

            sdk = repo / "LocalSecrets/TuyaSDK"
            planned_sdk_signature = helper._path_signature(sdk)
            original_sdk = repo / "LocalSecrets/TuyaSDK.original"
            sdk.rename(original_sdk)

            replacement_build = repo / "LocalSecrets/TuyaSDK/Build"
            replacement_build.mkdir(parents=True)
            replacement_sdk_signature = helper._path_signature(sdk)
            self.assertNotEqual(planned_sdk_signature, replacement_sdk_signature)
            self.assertFalse(sdk.is_symlink())
            self.assertFalse(replacement_build.is_symlink())

            descriptor = helper._open_pinned_path(subject, True)
            try:
                # Exploit-positive result: the opener accepts the newly substituted
                # real-directory tree because it compares against only the current
                # pathname identity, not identity frozen when _lease_paths planned it.
                self.assertEqual(
                    helper._descriptor_signature(descriptor),
                    helper._path_signature(replacement_build),
                )
                self.assertNotEqual(
                    helper._descriptor_signature(descriptor),
                    helper._path_signature(original_sdk / "Build"),
                )
            finally:
                os.close(descriptor)


if __name__ == "__main__":
    unittest.main(verbosity=2)
