#!/usr/bin/env python3
"""Regression for coherent shared generated-selector ancestry."""
from __future__ import annotations

import hashlib
import importlib.util
import json
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
    for entry in payload["entries"]:
        if entry.get("path") == path:
            return str(entry["sha256"])
    raise AssertionError(f"manifest entry missing: {path}")


class CaptureGeneratedSharedAncestorContinuityTests(unittest.TestCase):
    def test_manifest_holds_one_localsecrets_generation_across_private_subjects(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-shared-ancestor-continuity-") as raw:
            root = Path(raw)
            seed_common(root)
            generation_a = make_generation(root, "LocalSecrets.A", b"SDK-A\n", b"RUNTIME-A\n")
            generation_b = make_generation(root, "LocalSecrets.B", b"SDK-B\n", b"RUNTIME-B\n")
            generation_a.rename(root / "LocalSecrets")
            pure_a = helper.canonical_generated_manifest(root, SOURCE_SHA)
            original_open = helper._open_subject
            swapped = False

            def swap_before_runtime(root_fd: int, subject: Path, directory_cache=None):
                nonlocal swapped
                if subject == Path("LocalSecrets/TuyaRuntime") and not swapped:
                    (root / "LocalSecrets").rename(root / "LocalSecrets.A.attack")
                    generation_b.rename(root / "LocalSecrets")
                    swapped = True
                return original_open(root_fd, subject, directory_cache)

            with mock.patch.object(helper, "_open_subject", side_effect=swap_before_runtime):
                held = helper.canonical_generated_manifest(root, SOURCE_SHA)

            self.assertTrue(swapped)
            self.assertEqual(held, pure_a)
            payload = json.loads(held)
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
            generation_a = make_generation(root, "LocalSecrets.A", b"SDK-A\n", b"RUNTIME-A\n")
            generation_b = make_generation(root, "LocalSecrets.B", b"SDK-B\n", b"RUNTIME-B\n")
            generation_a.rename(root / "LocalSecrets")
            destination = root / "stage"
            destination.mkdir()
            original_open = helper._open_subject
            swapped = False

            def swap_before_runtime(root_fd: int, subject: Path, directory_cache=None):
                nonlocal swapped
                if subject == Path("LocalSecrets/TuyaRuntime") and not swapped:
                    (root / "LocalSecrets").rename(root / "LocalSecrets.A.attack")
                    generation_b.rename(root / "LocalSecrets")
                    swapped = True
                return original_open(root_fd, subject, directory_cache)

            with mock.patch.object(helper, "_open_subject", side_effect=swap_before_runtime):
                helper._copy_generated_subjects(root, destination)

            self.assertTrue(swapped)
            self.assertEqual((destination / "LocalSecrets/TuyaSDK/sdk.bin").read_bytes(), b"SDK-A\n")
            self.assertEqual(
                (destination / "LocalSecrets/TuyaRuntime/identity.bin").read_bytes(),
                b"RUNTIME-A\n",
            )

    def test_manifest_rejects_or_holds_generation_when_runtime_sibling_is_replaced(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-shared-ancestor-sibling-manifest-") as raw:
            root = Path(raw)
            seed_common(root)
            generation_a = make_generation(root, "LocalSecrets.A", b"SDK-A\n", b"RUNTIME-A\n")
            generation_b = make_generation(root, "LocalSecrets.B", b"SDK-B\n", b"RUNTIME-B\n")
            generation_a.rename(root / "LocalSecrets")
            original_open = helper._open_subject
            swapped = False

            def splice_runtime_inside_held_parent(root_fd: int, subject: Path, directory_cache=None):
                nonlocal swapped
                if subject == Path("LocalSecrets/TuyaRuntime") and not swapped:
                    active = root / "LocalSecrets"
                    (active / "TuyaRuntime").rename(active / "TuyaRuntime.A.attack")
                    (generation_b / "TuyaRuntime").rename(active / "TuyaRuntime")
                    swapped = True
                return original_open(root_fd, subject, directory_cache)

            try:
                with mock.patch.object(helper, "_open_subject", side_effect=splice_runtime_inside_held_parent):
                    manifest = helper.canonical_generated_manifest(root, SOURCE_SHA)
            except helper.AcceptedBuildInputSnapshotError:
                self.assertTrue(swapped)
                return

            self.assertTrue(swapped)
            payload = json.loads(manifest)
            self.assertEqual(
                entry_sha(payload, "LocalSecrets/TuyaSDK/sdk.bin"),
                hashlib.sha256(b"SDK-A\n").hexdigest(),
            )
            self.assertEqual(
                entry_sha(payload, "LocalSecrets/TuyaRuntime/identity.bin"),
                hashlib.sha256(b"RUNTIME-A\n").hexdigest(),
                "manifest admitted SDK-A with replacement Runtime-B inside the held LocalSecrets inode",
            )

    def test_copy_rejects_or_holds_generation_when_runtime_sibling_is_replaced(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-shared-ancestor-sibling-copy-") as raw:
            root = Path(raw)
            seed_common(root)
            generation_a = make_generation(root, "LocalSecrets.A", b"SDK-A\n", b"RUNTIME-A\n")
            generation_b = make_generation(root, "LocalSecrets.B", b"SDK-B\n", b"RUNTIME-B\n")
            generation_a.rename(root / "LocalSecrets")
            destination = root / "stage"
            destination.mkdir()
            original_open = helper._open_subject
            swapped = False

            def splice_runtime_inside_held_parent(root_fd: int, subject: Path, directory_cache=None):
                nonlocal swapped
                if subject == Path("LocalSecrets/TuyaRuntime") and not swapped:
                    active = root / "LocalSecrets"
                    (active / "TuyaRuntime").rename(active / "TuyaRuntime.A.attack")
                    (generation_b / "TuyaRuntime").rename(active / "TuyaRuntime")
                    swapped = True
                return original_open(root_fd, subject, directory_cache)

            try:
                with mock.patch.object(helper, "_open_subject", side_effect=splice_runtime_inside_held_parent):
                    helper._copy_generated_subjects(root, destination)
            except helper.AcceptedBuildInputSnapshotError:
                self.assertTrue(swapped)
                return

            self.assertTrue(swapped)
            self.assertEqual((destination / "LocalSecrets/TuyaSDK/sdk.bin").read_bytes(), b"SDK-A\n")
            self.assertEqual(
                (destination / "LocalSecrets/TuyaRuntime/identity.bin").read_bytes(),
                b"RUNTIME-A\n",
                "copy admitted SDK-A with replacement Runtime-B inside the held LocalSecrets inode",
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)
