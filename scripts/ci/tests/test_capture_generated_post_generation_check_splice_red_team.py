#!/usr/bin/env python3
"""Exploit-positive oracle for child replacement after cached-parent generation validation."""
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
    spec = importlib.util.spec_from_file_location("nembra_post_generation_check_splice", HELPER)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load accepted build-input helper")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def seed(root: Path) -> tuple[Path, Path, Path]:
    (root / "Podfile.lock").write_text("PODS:\n  - Synthetic\n", encoding="utf-8")
    workspace = root / "NembraCapture.xcworkspace"
    workspace.mkdir()
    (workspace / "contents.xcworkspacedata").write_text("<Workspace/>\n", encoding="utf-8")
    pods = root / "Pods"
    pods.mkdir()
    (pods / "SyntheticPod.swift").write_text("// pod\n", encoding="utf-8")

    local = root / "LocalSecrets"
    sdk = local / "TuyaSDK"
    runtime_a = local / "TuyaRuntime"
    runtime_b = local / "TuyaRuntime.B"
    for path in (sdk, runtime_a, runtime_b):
        path.mkdir(parents=True, exist_ok=False)
    (sdk / "sdk.bin").write_bytes(b"SDK-A\n")
    (runtime_a / "runtime.bin").write_bytes(b"RUNTIME-A\n")
    (runtime_b / "runtime.bin").write_bytes(b"RUNTIME-B\n")
    return local, runtime_a, runtime_b


def digest_for(payload: bytes, relative: str) -> str:
    decoded = json.loads(payload)
    for entry in decoded["entries"]:
        if entry.get("path") == relative:
            return str(entry["sha256"])
    raise AssertionError(f"manifest entry missing: {relative}")


def replace_runtime_inside_held_parent(local: Path, runtime_a: Path, runtime_b: Path) -> None:
    before = local.stat()
    runtime_a.rename(local / "TuyaRuntime.A.retired")
    runtime_b.rename(local / "TuyaRuntime")
    after = local.stat()
    if (before.st_dev, before.st_ino) != (after.st_dev, after.st_ino):
        raise AssertionError("attack unexpectedly replaced the held LocalSecrets ancestor")
    if (before.st_mtime_ns, before.st_ctime_ns) == (after.st_mtime_ns, after.st_ctime_ns):
        raise AssertionError("attack did not advance held-parent generation metadata")


class CaptureGeneratedPostGenerationCheckSpliceRedTeamTests(unittest.TestCase):
    def test_manifest_can_splice_runtime_after_cached_parent_generation_check(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-post-generation-check-manifest-") as raw:
            root = Path(raw)
            local, runtime_a, runtime_b = seed(root)
            original_open_directory_at = helper._open_directory_at
            swapped = False

            def splice_at_final_child_open(parent_fd: int, name: str, relative: Path):
                nonlocal swapped
                if relative == Path("LocalSecrets/TuyaRuntime") and not swapped:
                    replace_runtime_inside_held_parent(local, runtime_a, runtime_b)
                    swapped = True
                return original_open_directory_at(parent_fd, name, relative)

            with mock.patch.object(helper, "_open_directory_at", side_effect=splice_at_final_child_open):
                mixed = helper.canonical_generated_manifest(root, SOURCE_SHA)

            self.assertTrue(swapped)
            self.assertEqual(
                digest_for(mixed, "LocalSecrets/TuyaSDK/sdk.bin"),
                hashlib.sha256(b"SDK-A\n").hexdigest(),
            )
            self.assertEqual(
                digest_for(mixed, "LocalSecrets/TuyaRuntime/runtime.bin"),
                hashlib.sha256(b"RUNTIME-B\n").hexdigest(),
                "Runtime-B was selected after the cached parent generation had already been validated",
            )

    def test_copy_can_splice_runtime_after_cached_parent_generation_check(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-post-generation-check-copy-") as raw:
            root = Path(raw)
            local, runtime_a, runtime_b = seed(root)
            destination = root / "stage"
            destination.mkdir()
            original_open_directory_at = helper._open_directory_at
            swapped = False

            def splice_at_final_child_open(parent_fd: int, name: str, relative: Path):
                nonlocal swapped
                if relative == Path("LocalSecrets/TuyaRuntime") and not swapped:
                    replace_runtime_inside_held_parent(local, runtime_a, runtime_b)
                    swapped = True
                return original_open_directory_at(parent_fd, name, relative)

            with mock.patch.object(helper, "_open_directory_at", side_effect=splice_at_final_child_open):
                helper._copy_generated_subjects(root, destination)

            self.assertTrue(swapped)
            self.assertEqual((destination / "LocalSecrets/TuyaSDK/sdk.bin").read_bytes(), b"SDK-A\n")
            self.assertEqual(
                (destination / "LocalSecrets/TuyaRuntime/runtime.bin").read_bytes(),
                b"RUNTIME-B\n",
                "copy selected Runtime-B after the cached parent generation had already been validated",
            )

    def test_attack_runs_after_the_new_generation_guard(self) -> None:
        helper = load()
        import inspect

        source = inspect.getsource(helper._open_subject)
        guard = source.index("_assert_directory_generation(cached_descriptor, admitted, relative)")
        final_open = source.index("child = _open_directory_at(current, component, relative)")
        self.assertLess(guard, final_open)
        post_open = source[final_open:]
        self.assertNotIn("_assert_directory_generation(cached_descriptor, admitted, relative)", post_open)


if __name__ == "__main__":
    unittest.main(verbosity=2)
