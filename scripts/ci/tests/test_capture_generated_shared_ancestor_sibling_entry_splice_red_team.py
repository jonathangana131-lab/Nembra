#!/usr/bin/env python3
"""Exploit-positive witness for sibling replacement inside a held generated ancestor."""
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
    spec = importlib.util.spec_from_file_location("nembra_shared_ancestor_sibling_splice", HELPER)
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


def seed_private_a(root: Path) -> tuple[Path, Path]:
    sdk = root / "LocalSecrets/TuyaSDK"
    runtime = root / "LocalSecrets/TuyaRuntime"
    sdk.mkdir(parents=True)
    runtime.mkdir(parents=True)
    (sdk / "sdk.bin").write_bytes(b"SDK-A\n")
    (runtime / "identity.bin").write_bytes(b"RUNTIME-A\n")
    return sdk, runtime


def seed_runtime_b(root: Path) -> Path:
    runtime = root / "TuyaRuntime.B"
    runtime.mkdir()
    (runtime / "identity.bin").write_bytes(b"RUNTIME-B\n")
    return runtime


def entry_sha(payload: dict[str, object], path: str) -> str:
    for entry in payload["entries"]:
        if entry.get("path") == path:
            return str(entry["sha256"])
    raise AssertionError(f"manifest entry missing: {path}")


class CaptureGeneratedSharedAncestorSiblingEntrySpliceRedTeamTests(unittest.TestCase):
    def test_manifest_can_mix_sdk_a_with_replaced_runtime_b_inside_held_localsecrets(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-shared-ancestor-sibling-manifest-") as raw:
            root = Path(raw)
            seed_common(root)
            _sdk_a, runtime_a = seed_private_a(root)
            runtime_b = seed_runtime_b(root)
            pure_a = json.loads(helper.canonical_generated_manifest(root, SOURCE_SHA))

            original_open = helper._open_subject
            swapped = False

            def swap_runtime_child(root_fd: int, subject: Path, directory_cache=None):
                nonlocal swapped
                if subject == Path("LocalSecrets/TuyaRuntime") and not swapped:
                    runtime_a.rename(root / "TuyaRuntime.A.attack")
                    runtime_b.rename(root / "LocalSecrets/TuyaRuntime")
                    swapped = True
                return original_open(root_fd, subject, directory_cache)

            with mock.patch.object(helper, "_open_subject", side_effect=swap_runtime_child):
                mixed = json.loads(helper.canonical_generated_manifest(root, SOURCE_SHA))

            self.assertTrue(swapped)
            self.assertEqual(
                entry_sha(mixed, "LocalSecrets/TuyaSDK/sdk.bin"),
                hashlib.sha256(b"SDK-A\n").hexdigest(),
            )
            self.assertEqual(
                entry_sha(mixed, "LocalSecrets/TuyaRuntime/identity.bin"),
                hashlib.sha256(b"RUNTIME-B\n").hexdigest(),
            )
            self.assertEqual(
                entry_sha(pure_a, "LocalSecrets/TuyaRuntime/identity.bin"),
                hashlib.sha256(b"RUNTIME-A\n").hexdigest(),
            )
            self.assertNotEqual(mixed, pure_a)

    def test_copy_can_mix_sdk_a_with_replaced_runtime_b_inside_held_localsecrets(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-shared-ancestor-sibling-copy-") as raw:
            root = Path(raw)
            seed_common(root)
            _sdk_a, runtime_a = seed_private_a(root)
            runtime_b = seed_runtime_b(root)
            destination = root / "stage"
            destination.mkdir()

            original_open = helper._open_subject
            swapped = False

            def swap_runtime_child(root_fd: int, subject: Path, directory_cache=None):
                nonlocal swapped
                if subject == Path("LocalSecrets/TuyaRuntime") and not swapped:
                    runtime_a.rename(root / "TuyaRuntime.A.attack")
                    runtime_b.rename(root / "LocalSecrets/TuyaRuntime")
                    swapped = True
                return original_open(root_fd, subject, directory_cache)

            with mock.patch.object(helper, "_open_subject", side_effect=swap_runtime_child):
                helper._copy_generated_subjects(root, destination)

            self.assertTrue(swapped)
            self.assertEqual(
                (destination / "LocalSecrets/TuyaSDK/sdk.bin").read_bytes(),
                b"SDK-A\n",
            )
            self.assertEqual(
                (destination / "LocalSecrets/TuyaRuntime/identity.bin").read_bytes(),
                b"RUNTIME-B\n",
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)
