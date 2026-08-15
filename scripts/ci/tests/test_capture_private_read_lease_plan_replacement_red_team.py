#!/usr/bin/env python3
"""Exploit-positive oracle for private read-lease plan-to-grant object replacement."""
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
    spec = importlib.util.spec_from_file_location("nembra_plan_replacement_red_team", HELPER)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load selected-Xcode orchestrator")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class CapturePrivateReadLeasePlanReplacementRedTeamTests(unittest.TestCase):
    def test_real_directory_replacement_after_planning_is_currently_accepted(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-plan-replacement-") as raw:
            outer = Path(raw)
            repo = outer / "repo"
            legitimate = repo / "LocalSecrets/TuyaSDK/Build"
            legitimate.mkdir(parents=True)

            planned = helper._lease_paths((legitimate,), repo)
            self.assertIn((legitimate, False), planned)

            sdk = repo / "LocalSecrets/TuyaSDK"
            original_sdk = repo / "LocalSecrets/TuyaSDK.original"
            sdk.rename(original_sdk)
            original_build = original_sdk / "Build"
            original_signature = original_build.stat().st_dev, original_build.stat().st_ino

            replacement_build = sdk / "Build"
            replacement_build.mkdir(parents=True)
            replacement_signature = replacement_build.stat().st_dev, replacement_build.stat().st_ino
            self.assertNotEqual(original_signature, replacement_signature)
            self.assertFalse(sdk.is_symlink())
            self.assertFalse(replacement_build.is_symlink())

            descriptor = helper._open_pinned_path(legitimate, True)
            try:
                descriptor_stat = os.fstat(descriptor)
                descriptor_signature = descriptor_stat.st_dev, descriptor_stat.st_ino
                self.assertEqual(descriptor_signature, replacement_signature)
                self.assertNotEqual(descriptor_signature, original_signature)
            finally:
                os.close(descriptor)

    def test_current_opener_has_no_planning_identity_input(self) -> None:
        helper = load()
        parameters = tuple(inspect.signature(helper._open_pinned_path).parameters)
        self.assertEqual(parameters, ("path", "is_directory"))
        source = inspect.getsource(helper._open_pinned_path)
        self.assertIn("_path_signature(path)", source)
        self.assertIn("dir_fd=current", source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
