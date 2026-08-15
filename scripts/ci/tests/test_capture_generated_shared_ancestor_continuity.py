#!/usr/bin/env python3
"""Permanent regression for one-generation generated/private subject admission."""
from __future__ import annotations

import hashlib
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest import mock

REPOSITORY = Path(__file__).resolve().parents[3]
HELPER = REPOSITORY / "scripts/ci/capture_accepted_build_input_snapshot.py"
SOURCE_SHA = "a" * 40


def load():
    spec = importlib.util.spec_from_file_location("nembra_shared_ancestor_continuity", HELPER)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load accepted build-input helper")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def seed_common(root: Path) -> None:
    (root / "Podfile.lock").write_text("PODS:\n  - Synthetic\n", encoding="utf-8")
    workspace = root / "NembraCapture.xcworkspace"
    workspace.mkdir()
    (workspace / "contents.xcworkspacedata").write_text("<Workspace/>\n", encoding="utf-8")
    pods = root / "Pods"
    pods.mkdir()
    (pods / "SyntheticPod.swift").write_text("// pod\n", encoding="utf-8")


def make_generation(root: Path, name: str, sdk: bytes, runtime: bytes) -> Path:
    generation = root / name
    sdk_root = generation / "TuyaSDK"
    runtime_root = generation / "TuyaRuntime"
    sdk_root.mkdir(parents=True)
    runtime_root.mkdir(parents=True)
    (sdk_root / "sdk.bin").write_bytes(sdk)
    (runtime_root / "identity.bin").write_bytes(runtime)
    return generation


def entry_sha(payload: dict[str, object], path: str) -> str:
    entries = payload.get("entries")
    if not isinstance(entries, list):
        raise AssertionError("manifest entries missing")
    for entry in entries:
        if isinstance(entry, dict) and entry.get("path") == path:
            return str(entry["sha256"])
    raise AssertionError(f"manifest entry missing: {path}")


class CaptureGeneratedSharedAncestorContinuityTests(unittest.TestCase):
    def _install_a_and_b(self, root: Path) -> Path:
        generation_a = make_generation(root, "LocalSecrets.A", b"SDK-A\n", b"RUNTIME-A\n")
        generation_b = make_generation(root, "LocalSecrets.B", b"SDK-B\n", b"RUNTIME-B\n")
        generation_a.rename(root / "LocalSecrets")
        return generation_b

    def _swap_on_runtime_open(self, helper, root: Path, generation_b: Path):
        original_open = os.open
        swapped = {"value": False}

        def raced_open(path, flags, mode=0o777, *, dir_fd=None):
            if path == "TuyaRuntime" and dir_fd is not None and not swapped["value"]:
                (root / "LocalSecrets").rename(root / "LocalSecrets.A.attack")
                generation_b.rename(root / "LocalSecrets")
                swapped["value"] = True
            if dir_fd is None:
                return original_open(path, flags, mode)
            return original_open(path, flags, mode, dir_fd=dir_fd)

        return swapped, mock.patch.object(helper.os, "open", side_effect=raced_open)

    def test_manifest_holds_one_localsecrets_generation_across_private_subjects(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-shared-ancestor-manifest-") as raw:
            root = Path(raw)
            seed_common(root)
            generation_b = self._install_a_and_b(root)
            pure_a = helper.canonical_generated_manifest(root, SOURCE_SHA)
            swapped, patch = self._swap_on_runtime_open(helper, root, generation_b)
            with patch:
                attacked = helper.canonical_generated_manifest(root, SOURCE_SHA)
            self.assertTrue(swapped["value"], "attack seam did not execute")
            self.assertEqual(attacked, pure_a)
            payload = json.loads(attacked)
            self.assertEqual(
                entry_sha(payload, "LocalSecrets/TuyaSDK/sdk.bin"),
                hashlib.sha256(b"SDK-A\n").hexdigest(),
            )
            self.assertEqual(
                entry_sha(payload, "LocalSecrets/TuyaRuntime/identity.bin"),
                hashlib.sha256(b"RUNTIME-A\n").hexdigest(),
            )

    def test_copy_holds_one_localsecrets_generation_across_private_subjects(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-shared-ancestor-copy-") as raw:
            root = Path(raw)
            seed_common(root)
            generation_b = self._install_a_and_b(root)
            destination = root / "stage"
            destination.mkdir(mode=0o700)
            swapped, patch = self._swap_on_runtime_open(helper, root, generation_b)
            with patch:
                helper._copy_generated_subjects(root, destination)
            self.assertTrue(swapped["value"], "attack seam did not execute")
            self.assertEqual(
                (destination / "LocalSecrets/TuyaSDK/sdk.bin").read_bytes(),
                b"SDK-A\n",
            )
            self.assertEqual(
                (destination / "LocalSecrets/TuyaRuntime/identity.bin").read_bytes(),
                b"RUNTIME-A\n",
            )
            self.assertEqual(
                stat_mode(destination / "LocalSecrets"),
                0o700,
            )

    def test_source_keeps_namespace_and_descriptor_graph_invariants(self) -> None:
        source = HELPER.read_text(encoding="utf-8")
        self.assertIn("def _assert_tracked_namespace_coherence", source)
        self.assertIn("_assert_tracked_namespace_coherence(relative for", source)
        self.assertIn("def _open_generated_subject_set", source)
        self.assertIn("directory_cache: dict[Path, int] = {Path(): root_fd}", source)
        self.assertIn("if not final and prefix in directory_cache", source)
        self.assertIn("subjects, descriptors = _open_generated_subject_set(root)", source)
        self.assertIn("subjects, descriptors = _open_generated_subject_set(source_root)", source)
        self.assertIn("before.st_ctime_ns", source)
        self.assertIn("after.st_ctime_ns", source)
        self.assertIn("_ensure_owner_only_parent", source)
        self.assertIn("_validate_relative_symlink_target", source)
        self.assertNotIn("for subject in GENERATED_SUBJECTS:\n            descriptor, metadata, kind = _open_subject", source)


def stat_mode(path: Path) -> int:
    return path.stat().st_mode & 0o777


if __name__ == "__main__":
    unittest.main(verbosity=2)
