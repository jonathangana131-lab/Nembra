#!/usr/bin/env python3
"""Regression oracle for coherent fixed generated children under one held parent."""
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
    spec = importlib.util.spec_from_file_location("nembra_generated_two_child_splice", HELPER)
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


class CaptureGeneratedTwoChildSpliceRegressionTests(unittest.TestCase):
    def test_manifest_never_splices_sdk_a_with_runtime_b(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-generated-two-child-manifest-") as raw:
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

            try:
                with mock.patch.object(helper, "_open_subject", side_effect=splice_before_runtime):
                    observed = helper.canonical_generated_manifest(root, SOURCE_SHA)
            except helper.AcceptedBuildInputSnapshotError:
                self.assertTrue(swapped)
                return

            self.assertTrue(swapped)
            self.assertEqual(
                observed,
                pure_a,
                "operation neither failed closed nor stayed on the admitted A generation",
            )

    def test_copy_never_splices_sdk_a_with_runtime_b(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-generated-two-child-copy-") as raw:
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

            try:
                with mock.patch.object(helper, "_open_subject", side_effect=splice_before_runtime):
                    helper._copy_generated_subjects(root, destination)
            except helper.AcceptedBuildInputSnapshotError:
                self.assertTrue(swapped)
                return

            self.assertTrue(swapped)
            self.assertEqual((destination / "LocalSecrets/TuyaSDK/sdk.bin").read_bytes(), b"SDK-A\n")
            self.assertEqual(
                (destination / "LocalSecrets/TuyaRuntime/runtime.bin").read_bytes(),
                b"RUNTIME-A\n",
                "operation returned a mixed A/B staged private generation",
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)
