#!/usr/bin/env python3
"""Exploit-positive witness for plan-to-admission real-directory replacement.

The production component walk rejects symlink traversal, but its lease plan currently
retains pathnames rather than the object identities observed during planning. Replacing
a planned directory tree with a different *real* directory tree at the same pathname
therefore needs no symlink. SUCCESS in this diagnostic means the attacked production
head remains RED for plan-to-admission object-continuity custody.
"""
from __future__ import annotations

import importlib.util
import inspect
import os
from pathlib import Path
import tempfile
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
ORCHESTRATOR = REPOSITORY / "scripts/ci/capture_selected_xcode_build_orchestrator.py"


def _load_production():
    spec = importlib.util.spec_from_file_location(
        "capture_selected_xcode_build_orchestrator_real_replacement_red_team",
        ORCHESTRATOR,
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load production orchestrator")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class CapturePrivateReadLeaseRealDirectoryReplacementRedTeam(unittest.TestCase):
    def test_planned_real_directory_can_be_replaced_before_pinned_open(self) -> None:
        production = _load_production()

        with tempfile.TemporaryDirectory(prefix="nembra-read-lease-real-replacement-") as raw:
            root = Path(raw).resolve()
            repository = root / "repo"
            trusted_sdk = repository / "LocalSecrets/TuyaSDK"
            trusted_build = trusted_sdk / "Build"
            trusted_build.mkdir(parents=True)
            (trusted_build / "trusted.txt").write_text("trusted\n", encoding="utf-8")

            planned = production._lease_paths((trusted_build,), repository)
            self.assertIn((trusted_build, False), planned)
            planned_identity = production._path_signature(trusted_build)

            parked_sdk = repository / "LocalSecrets/TuyaSDK.planned"
            trusted_sdk.rename(parked_sdk)
            replacement_build = repository / "LocalSecrets/TuyaSDK/Build"
            replacement_build.mkdir(parents=True)
            (replacement_build / "attacker.txt").write_text("replacement\n", encoding="utf-8")

            # This attack deliberately uses no symlink. Every replacement component at
            # and below TuyaSDK is a real directory, so O_NOFOLLOW cannot distinguish it
            # from the object that _lease_paths observed earlier.
            self.assertFalse((repository / "LocalSecrets/TuyaSDK").is_symlink())
            self.assertFalse(replacement_build.is_symlink())
            self.assertNotEqual(planned_identity, production._path_signature(replacement_build))

            descriptor = production._open_pinned_path(trusted_build, True)
            try:
                opened = production._descriptor_signature(descriptor)
                replacement = production._path_signature(replacement_build)
                original = production._path_signature(parked_sdk / "Build")
                self.assertEqual(opened, replacement)
                self.assertNotEqual(opened, original)
                self.assertNotEqual(opened, planned_identity)
            finally:
                os.close(descriptor)

    def test_current_plan_does_not_carry_object_identity_into_open(self) -> None:
        production = _load_production()
        planner = inspect.getsource(production._lease_paths)
        opener = inspect.getsource(production._open_pinned_path)

        self.assertNotIn("_path_signature", planner)
        self.assertIn("dir_fd=current", opener)
        self.assertIn("_path_signature(path)", opener)
        self.assertLess(opener.index("dir_fd=current"), opener.index("_path_signature(path)"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
