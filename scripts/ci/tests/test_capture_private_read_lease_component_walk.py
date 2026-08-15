#!/usr/bin/env python3
"""Portable regression for component-anchored private read-lease admission."""
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
    spec = importlib.util.spec_from_file_location("nembra_component_walk", HELPER)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load selected-Xcode orchestrator")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class CapturePrivateReadLeaseComponentWalkTests(unittest.TestCase):
    def test_intermediate_symlink_swap_is_rejected_after_plan(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-component-walk-") as raw:
            outer = Path(raw)
            repo = outer / "repo"
            legitimate = repo / "LocalSecrets/TuyaSDK/Build"
            legitimate.mkdir(parents=True)
            planned = helper._lease_paths((legitimate,), repo)
            self.assertIn((legitimate, False), planned)

            sdk = repo / "LocalSecrets/TuyaSDK"
            original = repo / "LocalSecrets/TuyaSDK.original"
            sdk.rename(original)
            attacker = outer / "attacker/TuyaSDK"
            attacker_build = attacker / "Build"
            attacker_build.mkdir(parents=True)
            sdk.symlink_to(attacker, target_is_directory=True)

            plain = os.open(legitimate, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
            try:
                self.assertEqual(os.fstat(plain).st_ino, attacker_build.stat().st_ino)
            finally:
                os.close(plain)

            with self.assertRaises(helper.SelectedXcodeBuildOrchestratorError):
                helper._open_pinned_path(legitimate, True)

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

    def test_real_directory_replacement_is_rejected_against_planned_identity(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-component-real-swap-") as raw:
            outer = Path(raw)
            repo = outer / "repo"
            legitimate = repo / "LocalSecrets/TuyaSDK/Build"
            legitimate.mkdir(parents=True)
            planned = helper._lease_paths((legitimate,), repo, include_signatures=True)
            expected = next(
                signature
                for path, _host_only, signature in planned
                if path == legitimate
            )

            sdk = repo / "LocalSecrets/TuyaSDK"
            original = repo / "LocalSecrets/TuyaSDK.original"
            sdk.rename(original)
            replacement = repo / "LocalSecrets/TuyaSDK/Build"
            replacement.mkdir(parents=True)
            self.assertFalse(sdk.is_symlink())
            self.assertFalse(replacement.is_symlink())
            self.assertNotEqual(expected, helper._path_signature(replacement))

            with self.assertRaises(helper.SelectedXcodeBuildOrchestratorError):
                helper._open_pinned_path(legitimate, True, expected)

    def test_source_uses_dirfd_component_walk_before_path_diagnostic(self) -> None:
        helper = load()
        source = inspect.getsource(helper._open_pinned_path)
        self.assertIn("dir_fd=current", source)
        self.assertIn("os.supports_dir_fd", source)
        self.assertIn("O_NOFOLLOW", source)
        self.assertIn("expected_signature", source)
        self.assertNotIn("os.open(path,", source)
        self.assertLess(source.index("dir_fd=current"), source.index("_path_signature(path)"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
