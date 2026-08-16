#!/usr/bin/env python3
"""Exploit regression for a final-child swap after parent-generation revalidation.

SUCCESS in this red-team test means the attacked product head is vulnerable: one
accepted operation can consume TuyaSDK from generation A and TuyaRuntime from
generation B when the sibling entry is replaced after the held parent is checked
but immediately before the final child open.
"""
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
SOURCE_SHA = "b" * 40


def load():
    spec = importlib.util.spec_from_file_location("nembra_final_child_open_race", HELPER)
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


def install_final_child_splice(helper, root: Path, generation_b: Path):
    original_open = helper._open_directory_at
    state = {"swapped": False}

    def splice_after_parent_check(parent_fd: int, name: str, relative: Path):
        if relative == Path("LocalSecrets/TuyaRuntime") and not state["swapped"]:
            active = root / "LocalSecrets"
            (active / "TuyaRuntime").rename(active / "TuyaRuntime.A.attack")
            (generation_b / "TuyaRuntime").rename(active / "TuyaRuntime")
            state["swapped"] = True
        return original_open(parent_fd, name, relative)

    return state, splice_after_parent_check


class CaptureGeneratedFinalChildOpenRaceTests(unittest.TestCase):
    def test_manifest_can_mix_sdk_a_with_runtime_b_after_parent_check(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-final-child-manifest-") as raw:
            root = Path(raw)
            seed_common(root)
            generation_a = make_generation(root, "LocalSecrets.A", b"SDK-A\n", b"RUNTIME-A\n")
            generation_b = make_generation(root, "LocalSecrets.B", b"SDK-B\n", b"RUNTIME-B\n")
            generation_a.rename(root / "LocalSecrets")

            pure_a = json.loads(helper.canonical_generated_manifest(root, SOURCE_SHA))
            state, splice = install_final_child_splice(helper, root, generation_b)
            with mock.patch.object(helper, "_open_directory_at", side_effect=splice):
                attacked = json.loads(helper.canonical_generated_manifest(root, SOURCE_SHA))

            self.assertTrue(state["swapped"], "attack hook never reached final Runtime child open")
            self.assertEqual(
                entry_sha(attacked, "LocalSecrets/TuyaSDK/sdk.bin"),
                hashlib.sha256(b"SDK-A\n").hexdigest(),
            )
            self.assertEqual(
                entry_sha(attacked, "LocalSecrets/TuyaRuntime/identity.bin"),
                hashlib.sha256(b"RUNTIME-B\n").hexdigest(),
            )
            self.assertNotEqual(
                entry_sha(attacked, "LocalSecrets/TuyaRuntime/identity.bin"),
                entry_sha(pure_a, "LocalSecrets/TuyaRuntime/identity.bin"),
            )

    def test_copy_can_stage_sdk_a_with_runtime_b_after_parent_check(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-final-child-copy-") as raw:
            root = Path(raw)
            seed_common(root)
            generation_a = make_generation(root, "LocalSecrets.A", b"SDK-A\n", b"RUNTIME-A\n")
            generation_b = make_generation(root, "LocalSecrets.B", b"SDK-B\n", b"RUNTIME-B\n")
            generation_a.rename(root / "LocalSecrets")
            destination = root / "stage"
            destination.mkdir()

            state, splice = install_final_child_splice(helper, root, generation_b)
            with mock.patch.object(helper, "_open_directory_at", side_effect=splice):
                helper._copy_generated_subjects(root, destination)

            self.assertTrue(state["swapped"], "attack hook never reached final Runtime child open")
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
