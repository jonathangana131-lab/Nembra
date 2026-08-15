#!/usr/bin/env python3
"""Regress component-anchored private read-lease admission."""

from __future__ import annotations

import importlib.util
import inspect
import os
from pathlib import Path
import tempfile
import unittest
from unittest import mock

REPO = Path(__file__).resolve().parents[3]
HELPER = REPO / "scripts/ci/capture_selected_xcode_build_orchestrator.py"


def load():
    spec = importlib.util.spec_from_file_location("nembra_component_walk", HELPER)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load selected-Xcode orchestrator")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class CapturePrivateReadLeaseComponentWalkTests(unittest.TestCase):
    def test_intermediate_swap_after_parent_pin_cannot_redirect_authority(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-component-walk-race-") as raw:
            outer = Path(raw)
            repo = outer / "repo"
            legitimate = repo / "LocalSecrets/TuyaSDK/Build"
            legitimate.mkdir(parents=True)
            original_sdk = repo / "LocalSecrets/TuyaSDK.original"
            sdk = repo / "LocalSecrets/TuyaSDK"
            attacker_sdk = outer / "attacker/TuyaSDK"
            attacker_build = attacker_sdk / "Build"
            attacker_build.mkdir(parents=True)

            real_open = os.open
            swapped = False

            def racing_open(path, flags, mode=0o777, *, dir_fd=None):
                nonlocal swapped
                if dir_fd is None:
                    descriptor = real_open(path, flags, mode)
                else:
                    descriptor = real_open(path, flags, mode, dir_fd=dir_fd)
                if path == "TuyaSDK" and dir_fd is not None and not swapped:
                    sdk.rename(original_sdk)
                    sdk.symlink_to(attacker_sdk, target_is_directory=True)
                    swapped = True
                return descriptor

            with mock.patch.object(helper.os, "open", side_effect=racing_open):
                with self.assertRaises(helper.SelectedXcodeBuildOrchestratorError):
                    helper._open_pinned_path(legitimate, True)

            self.assertTrue(swapped)
            self.assertEqual(legitimate.stat().st_ino, attacker_build.stat().st_ino)
            sdk.unlink()

    def test_preexisting_intermediate_symlink_is_rejected(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-component-walk-link-") as raw:
            outer = Path(raw)
            repo = outer / "repo"
            local = repo / "LocalSecrets"
            local.mkdir(parents=True)
            attacker_sdk = outer / "attacker/TuyaSDK"
            (attacker_sdk / "Build").mkdir(parents=True)
            link = local / "TuyaSDK"
            link.symlink_to(attacker_sdk, target_is_directory=True)
            with self.assertRaises(helper.SelectedXcodeBuildOrchestratorError):
                helper._open_pinned_path(local / "TuyaSDK/Build", True)
            link.unlink()

    def test_real_directory_and_regular_file_still_open(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-component-walk-control-") as raw:
            root = Path(raw)
            directory = root / "a/b/c"
            directory.mkdir(parents=True)
            file = directory / "private.fixture"
            file.write_bytes(b"fixture\n")
            for path, is_directory in ((directory, True), (file, False)):
                descriptor = helper._open_pinned_path(path, is_directory)
                try:
                    self.assertEqual(
                        helper._descriptor_signature(descriptor),
                        helper._path_signature(path),
                    )
                finally:
                    os.close(descriptor)

    def test_source_uses_component_dirfd_walk_not_full_path_open(self) -> None:
        helper = load()
        source = inspect.getsource(helper._open_pinned_path)
        self.assertIn("dir_fd=current", source)
        self.assertIn("os.supports_dir_fd", source)
        self.assertIn("O_NOFOLLOW", source)
        self.assertNotIn("os.open(path,", source)
        self.assertLess(source.index("dir_fd=current"), source.index("_path_signature(path)"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
