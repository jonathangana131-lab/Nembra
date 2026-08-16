#!/usr/bin/env python3
"""Regression for one-generation repository-root custody across generated subjects."""
from __future__ import annotations

import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest import mock

REPOSITORY = Path(__file__).resolve().parents[3]
HELPER = REPOSITORY / "scripts/ci/capture_accepted_build_input_snapshot.py"
SOURCE_SHA = "c" * 40


def load():
    spec = importlib.util.spec_from_file_location("nembra_generated_root_continuity", HELPER)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load accepted build-input helper")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def seed_generation(root: Path, marker: str) -> None:
    root.mkdir()
    (root / "Podfile.lock").write_text(f"LOCK-{marker}\n", encoding="utf-8")
    workspace = root / "NembraCapture.xcworkspace"
    workspace.mkdir()
    (workspace / "contents.xcworkspacedata").write_text(
        f"<Workspace-{marker}/>\n", encoding="utf-8"
    )
    pods = root / "Pods"
    pods.mkdir()
    (pods / "SyntheticPod.swift").write_text(f"// POD-{marker}\n", encoding="utf-8")
    sdk = root / "LocalSecrets/TuyaSDK"
    runtime = root / "LocalSecrets/TuyaRuntime"
    sdk.mkdir(parents=True)
    runtime.mkdir(parents=True)
    (sdk / "sdk.bin").write_bytes(f"SDK-{marker}\n".encode())
    (runtime / "identity.bin").write_bytes(f"RUNTIME-{marker}\n".encode())


def replace_generated_root_membership(active: Path, generation_b: Path) -> None:
    for index, name in enumerate(
        ("Podfile.lock", "NembraCapture.xcworkspace", "Pods", "LocalSecrets")
    ):
        (active / name).rename(active / f"generation-A-{index}.attack")
        (generation_b / name).rename(active / name)


def install_splice(helper, active: Path, generation_b: Path):
    original_open = helper._open_subject
    state = {"swapped": False}

    def splice_before_second_subject(root_fd: int, subject: Path, directory_cache=None):
        if subject == Path("NembraCapture.xcworkspace") and not state["swapped"]:
            replace_generated_root_membership(active, generation_b)
            state["swapped"] = True
        return original_open(root_fd, subject, directory_cache)

    return state, splice_before_second_subject


class CaptureGeneratedRootGenerationContinuityTests(unittest.TestCase):
    def test_manifest_rejects_cross_subject_root_generation_splice(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-root-generation-manifest-") as raw:
            sandbox = Path(raw)
            active = sandbox / "active"
            generation_b = sandbox / "generation-b"
            seed_generation(active, "A")
            seed_generation(generation_b, "B")
            state, splice = install_splice(helper, active, generation_b)

            with mock.patch.object(helper, "_open_subject", side_effect=splice):
                with self.assertRaises(helper.AcceptedBuildInputSnapshotError):
                    helper.canonical_generated_manifest(active, SOURCE_SHA)
            self.assertTrue(state["swapped"])

    def test_copy_rejects_cross_subject_root_generation_splice(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-root-generation-copy-") as raw:
            sandbox = Path(raw)
            active = sandbox / "active"
            generation_b = sandbox / "generation-b"
            destination = sandbox / "stage"
            seed_generation(active, "A")
            seed_generation(generation_b, "B")
            destination.mkdir()
            state, splice = install_splice(helper, active, generation_b)

            with mock.patch.object(helper, "_open_subject", side_effect=splice):
                with self.assertRaises(helper.AcceptedBuildInputSnapshotError):
                    helper._copy_generated_subjects(active, destination)
            self.assertTrue(state["swapped"])

    def test_stable_root_preserves_existing_positive_path(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-root-generation-positive-") as raw:
            sandbox = Path(raw)
            active = sandbox / "active"
            destination = sandbox / "stage"
            seed_generation(active, "A")
            manifest = helper.canonical_generated_manifest(active, SOURCE_SHA)
            self.assertTrue(manifest.endswith(b"\n"))
            destination.mkdir()
            helper._copy_generated_subjects(active, destination)
            self.assertEqual((destination / "Podfile.lock").read_bytes(), b"LOCK-A\n")
            self.assertEqual(
                (destination / "LocalSecrets/TuyaRuntime/identity.bin").read_bytes(),
                b"RUNTIME-A\n",
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)
