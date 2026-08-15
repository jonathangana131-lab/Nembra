#!/usr/bin/env python3
"""Regression for coherent shared generated-selector ancestry."""
from __future__ import annotations

import errno
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


    def test_cache_dup_failure_closes_newly_opened_child_descriptor(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-shared-ancestor-cache-dup-cleanup-") as raw:
            root = Path(raw)
            (root / "LocalSecrets/TuyaSDK").mkdir(parents=True)
            root_fd = helper._open_repository_root(root)
            real_dup = os.dup
            real_open_directory = helper._open_directory_at
            opened_children: list[int] = []
            dup_calls = 0

            def capture_open(parent_fd: int, name: str, relative: Path) -> int:
                descriptor = real_open_directory(parent_fd, name, relative)
                opened_children.append(descriptor)
                return descriptor

            def fail_cache_dup(descriptor: int) -> int:
                nonlocal dup_calls
                dup_calls += 1
                if dup_calls == 2:
                    raise OSError(errno.EMFILE, "synthetic cache-dup exhaustion")
                return real_dup(descriptor)

            cache: dict[Path, int] = {}
            try:
                with (
                    mock.patch.object(helper, "_open_directory_at", side_effect=capture_open),
                    mock.patch.object(helper.os, "dup", side_effect=fail_cache_dup),
                ):
                    with self.assertRaisesRegex(OSError, "synthetic cache-dup exhaustion"):
                        helper._open_subject(
                            root_fd,
                            Path("LocalSecrets/TuyaSDK"),
                            cache,
                        )

                self.assertEqual(dup_calls, 2)
                self.assertEqual(cache, {})
                self.assertEqual(len(opened_children), 1)
                with self.assertRaises(OSError):
                    os.fstat(opened_children[0])
            finally:
                for descriptor in opened_children:
                    try:
                        os.close(descriptor)
                    except OSError:
                        pass
                os.close(root_fd)


if __name__ == "__main__":
    unittest.main(verbosity=2)
