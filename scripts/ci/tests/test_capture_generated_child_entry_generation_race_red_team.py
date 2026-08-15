#!/usr/bin/env python3
"""Exploit-positive oracle for child-entry splicing under one held generated ancestor."""
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
    spec = importlib.util.spec_from_file_location("nembra_generated_child_entry_splice", HELPER)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load accepted build-input helper")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def seed_common(root: Path) -> tuple[Path, Path, Path, Path, Path]:
    (root / "Podfile.lock").write_text("PODS:\n  - Synthetic\n", encoding="utf-8")
    workspace = root / "NembraCapture.xcworkspace"
    workspace.mkdir()
    (workspace / "contents.xcworkspacedata").write_text("<Workspace/>\n", encoding="utf-8")
    pods = root / "Pods"
    pods.mkdir()
    (pods / "SyntheticPod.swift").write_text("// pod\n", encoding="utf-8")

    local = root / "LocalSecrets"
    sdk_a = local / "TuyaSDK"
    runtime_a = local / "TuyaRuntime"
    sdk_b = local / "TuyaSDK.B"
    runtime_b = local / "TuyaRuntime.B"
    for path in (sdk_a, runtime_a, sdk_b, runtime_b):
        path.mkdir(parents=True, exist_ok=False)
    (sdk_a / "sdk.bin").write_bytes(b"SDK-A\n")
    (runtime_a / "runtime.bin").write_bytes(b"RUNTIME-A\n")
    (sdk_b / "sdk.bin").write_bytes(b"SDK-B\n")
    (runtime_b / "runtime.bin").write_bytes(b"RUNTIME-B\n")
    return local, sdk_a, runtime_a, sdk_b, runtime_b


def digest_for(payload: bytes, relative: str) -> str:
    decoded = json.loads(payload)
    for entry in decoded["entries"]:
        if entry.get("path") == relative:
            return str(entry["sha256"])
    raise AssertionError(f"manifest entry missing: {relative}")


def swap_canonical_children(
    local: Path,
    sdk_a: Path,
    runtime_a: Path,
    sdk_b: Path,
    runtime_b: Path,
) -> None:
    before = local.stat()
    sdk_a.rename(local / "TuyaSDK.A.retired")
    runtime_a.rename(local / "TuyaRuntime.A.retired")
    sdk_b.rename(local / "TuyaSDK")
    runtime_b.rename(local / "TuyaRuntime")
    after = local.stat()
    if (before.st_dev, before.st_ino) != (after.st_dev, after.st_ino):
        raise AssertionError("attack unexpectedly replaced the held LocalSecrets ancestor")


class CaptureGeneratedChildEntryGenerationRaceRedTeamTests(unittest.TestCase):
    def test_manifest_can_splice_sdk_a_with_runtime_b_under_same_held_ancestor(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-generated-child-splice-") as raw:
            root = Path(raw)
            local, sdk_a, runtime_a, sdk_b, runtime_b = seed_common(root)
            pure_a = helper.canonical_generated_manifest(root, SOURCE_SHA)
            original_open = helper._open_subject
            swapped = False

            def splice_before_runtime(root_fd: int, subject: Path, directory_cache=None):
                nonlocal swapped
                if subject == Path("LocalSecrets/TuyaRuntime") and not swapped:
                    swap_canonical_children(local, sdk_a, runtime_a, sdk_b, runtime_b)
                    swapped = True
                return original_open(root_fd, subject, directory_cache)

            with mock.patch.object(helper, "_open_subject", side_effect=splice_before_runtime):
                mixed = helper.canonical_generated_manifest(root, SOURCE_SHA)
            self.assertTrue(swapped)
            pure_b = helper.canonical_generated_manifest(root, SOURCE_SHA)

            sdk_a_hash = hashlib.sha256(b"SDK-A\n").hexdigest()
            sdk_b_hash = hashlib.sha256(b"SDK-B\n").hexdigest()
            runtime_a_hash = hashlib.sha256(b"RUNTIME-A\n").hexdigest()
            runtime_b_hash = hashlib.sha256(b"RUNTIME-B\n").hexdigest()

            self.assertEqual(digest_for(pure_a, "LocalSecrets/TuyaSDK/sdk.bin"), sdk_a_hash)
            self.assertEqual(digest_for(pure_a, "LocalSecrets/TuyaRuntime/runtime.bin"), runtime_a_hash)
            self.assertEqual(digest_for(pure_b, "LocalSecrets/TuyaSDK/sdk.bin"), sdk_b_hash)
            self.assertEqual(digest_for(pure_b, "LocalSecrets/TuyaRuntime/runtime.bin"), runtime_b_hash)
            self.assertEqual(digest_for(mixed, "LocalSecrets/TuyaSDK/sdk.bin"), sdk_a_hash)
            self.assertEqual(digest_for(mixed, "LocalSecrets/TuyaRuntime/runtime.bin"), runtime_b_hash)
            self.assertNotEqual(mixed, pure_a)
            self.assertNotEqual(mixed, pure_b)

    def test_copy_can_splice_sdk_a_with_runtime_b_under_same_held_ancestor(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-generated-child-copy-") as raw:
            root = Path(raw)
            local, sdk_a, runtime_a, sdk_b, runtime_b = seed_common(root)
            destination = root / "stage"
            destination.mkdir()
            original_open = helper._open_subject
            swapped = False

            def splice_before_runtime(root_fd: int, subject: Path, directory_cache=None):
                nonlocal swapped
                if subject == Path("LocalSecrets/TuyaRuntime") and not swapped:
                    swap_canonical_children(local, sdk_a, runtime_a, sdk_b, runtime_b)
                    swapped = True
                return original_open(root_fd, subject, directory_cache)

            with mock.patch.object(helper, "_open_subject", side_effect=splice_before_runtime):
                helper._copy_generated_subjects(root, destination)
            self.assertTrue(swapped)

            self.assertEqual((destination / "LocalSecrets/TuyaSDK/sdk.bin").read_bytes(), b"SDK-A\n")
            self.assertEqual(
                (destination / "LocalSecrets/TuyaRuntime/runtime.bin").read_bytes(),
                b"RUNTIME-B\n",
            )
            self.assertEqual((root / "LocalSecrets/TuyaSDK/sdk.bin").read_bytes(), b"SDK-B\n")
            self.assertEqual(
                (root / "LocalSecrets/TuyaRuntime/runtime.bin").read_bytes(),
                b"RUNTIME-B\n",
            )

    def test_source_cache_holds_only_nonfinal_prefixes(self) -> None:
        helper = load()
        import inspect

        source = inspect.getsource(helper._open_subject)
        self.assertIn("if not is_last and directory_cache is not None", source)
        self.assertIn("directory_cache[relative] = os.dup(child)", source)
        self.assertNotIn("if is_last and directory_cache is not None", source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
