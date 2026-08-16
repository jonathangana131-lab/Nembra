#!/usr/bin/env python3
"""Regression coverage for one-generation accepted generated-input root custody."""
from __future__ import annotations

import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest import mock

REPOSITORY = Path(__file__).resolve().parents[3]
HELPER = REPOSITORY / "scripts/ci/capture_accepted_build_input_snapshot.py"
SOURCE_SHA = "a" * 40


def load():
    spec = importlib.util.spec_from_file_location(
        "nembra_generated_root_generation_continuity",
        HELPER,
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load accepted build-input helper")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def seed_repo(root: Path, *, lock: bytes, pod: bytes) -> None:
    root.mkdir()
    (root / "Podfile.lock").write_bytes(lock)
    workspace = root / "NembraCapture.xcworkspace"
    workspace.mkdir()
    (workspace / "contents.xcworkspacedata").write_text("<Workspace/>\n", encoding="utf-8")
    pods = root / "Pods"
    pods.mkdir()
    (pods / "payload.bin").write_bytes(pod)
    sdk = root / "LocalSecrets/TuyaSDK"
    runtime = root / "LocalSecrets/TuyaRuntime"
    sdk.mkdir(parents=True)
    runtime.mkdir(parents=True)
    (sdk / "sdk.bin").write_bytes(b"SDK\n")
    (runtime / "runtime.bin").write_bytes(b"RUNTIME\n")


def install_root_sibling_splice(helper, root: Path, outer: Path):
    replacement_lock = outer / "replacement-Podfile.lock"
    replacement_lock.write_bytes(b"PODS:\n  - B\n")
    replacement_pods = outer / "replacement-Pods"
    replacement_pods.mkdir()
    (replacement_pods / "payload.bin").write_bytes(b"POD-B\n")

    original_open_subject = helper._open_subject
    state = {"swapped": False}

    def splice_before_pods(root_fd: int, subject: Path, directory_cache=None):
        if subject == Path("Pods") and not state["swapped"]:
            (root / "Podfile.lock").rename(root / "Podfile.lock.A.attack")
            replacement_lock.rename(root / "Podfile.lock")
            (root / "Pods").rename(root / "Pods.A.attack")
            replacement_pods.rename(root / "Pods")
            state["swapped"] = True
        return original_open_subject(root_fd, subject, directory_cache)

    return state, splice_before_pods


class CaptureGeneratedRootGenerationContinuityTests(unittest.TestCase):
    def test_manifest_rejects_root_sibling_generation_splice(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(
            prefix="nembra-generated-root-generation-manifest-",
            dir=REPOSITORY,
        ) as raw:
            outer = Path(raw)
            root = outer / "repo"
            seed_repo(root, lock=b"PODS:\n  - A\n", pod=b"POD-A\n")
            state, splice = install_root_sibling_splice(helper, root, outer)
            with mock.patch.object(helper, "_open_subject", side_effect=splice):
                with self.assertRaises(helper.AcceptedBuildInputSnapshotError):
                    helper.canonical_generated_manifest(root, SOURCE_SHA)
            self.assertTrue(state["swapped"])

    def test_copy_rejects_root_sibling_generation_splice(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(
            prefix="nembra-generated-root-generation-copy-",
            dir=REPOSITORY,
        ) as raw:
            outer = Path(raw)
            root = outer / "repo"
            seed_repo(root, lock=b"PODS:\n  - A\n", pod=b"POD-A\n")
            destination = outer / "stage"
            destination.mkdir()
            state, splice = install_root_sibling_splice(helper, root, outer)
            with mock.patch.object(helper, "_open_subject", side_effect=splice):
                with self.assertRaises(helper.AcceptedBuildInputSnapshotError):
                    helper._copy_generated_subjects(root, destination)
            self.assertTrue(state["swapped"])

    def test_stable_root_still_accepts_manifest_and_copy(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(
            prefix="nembra-generated-root-generation-positive-",
            dir=REPOSITORY,
        ) as raw:
            outer = Path(raw)
            root = outer / "repo"
            seed_repo(root, lock=b"PODS:\n  - A\n", pod=b"POD-A\n")
            manifest = helper.canonical_generated_manifest(root, SOURCE_SHA)
            self.assertTrue(manifest.endswith(b"\n"))
            destination = outer / "stage"
            destination.mkdir()
            helper._copy_generated_subjects(root, destination)
            self.assertEqual((destination / "Podfile.lock").read_bytes(), b"PODS:\n  - A\n")
            self.assertEqual((destination / "Pods/payload.bin").read_bytes(), b"POD-A\n")


if __name__ == "__main__":
    unittest.main(verbosity=2)
