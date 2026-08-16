#!/usr/bin/env python3
"""Exploit oracle for cross-subject root-generation splicing.

SUCCESS means the attacked product can consume Podfile.lock from generation A and
later generated subjects from generation B after the held repository root's
membership changes between subjects.
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
SOURCE_SHA = "c" * 40


def load():
    spec = importlib.util.spec_from_file_location("nembra_generated_root_splice", HELPER)
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


def entry_sha(payload: dict[str, object], path: str) -> str:
    for entry in payload["entries"]:
        if entry.get("path") == path:
            return str(entry["sha256"])
    raise AssertionError(f"manifest entry missing: {path}")


class CaptureGeneratedRootGenerationSpliceRedTeamTests(unittest.TestCase):
    def test_manifest_can_mix_lock_a_with_remaining_generation_b(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-root-generation-manifest-") as raw:
            sandbox = Path(raw)
            active = sandbox / "active"
            generation_b = sandbox / "generation-b"
            seed_generation(active, "A")
            seed_generation(generation_b, "B")

            original_open = helper._open_subject
            swapped = False

            def splice_before_second_subject(root_fd: int, subject: Path, directory_cache=None):
                nonlocal swapped
                if subject == Path("NembraCapture.xcworkspace") and not swapped:
                    replace_generated_root_membership(active, generation_b)
                    swapped = True
                return original_open(root_fd, subject, directory_cache)

            with mock.patch.object(helper, "_open_subject", side_effect=splice_before_second_subject):
                payload = json.loads(helper.canonical_generated_manifest(active, SOURCE_SHA))

            self.assertTrue(swapped)
            self.assertEqual(
                entry_sha(payload, "Podfile.lock"),
                hashlib.sha256(b"LOCK-A\n").hexdigest(),
            )
            self.assertEqual(
                entry_sha(payload, "NembraCapture.xcworkspace/contents.xcworkspacedata"),
                hashlib.sha256(b"<Workspace-B/>\n").hexdigest(),
            )
            self.assertEqual(
                entry_sha(payload, "Pods/SyntheticPod.swift"),
                hashlib.sha256(b"// POD-B\n").hexdigest(),
            )
            self.assertEqual(
                entry_sha(payload, "LocalSecrets/TuyaSDK/sdk.bin"),
                hashlib.sha256(b"SDK-B\n").hexdigest(),
            )
            self.assertEqual(
                entry_sha(payload, "LocalSecrets/TuyaRuntime/identity.bin"),
                hashlib.sha256(b"RUNTIME-B\n").hexdigest(),
            )

    def test_copy_can_stage_lock_a_with_remaining_generation_b(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-root-generation-copy-") as raw:
            sandbox = Path(raw)
            active = sandbox / "active"
            generation_b = sandbox / "generation-b"
            destination = sandbox / "stage"
            seed_generation(active, "A")
            seed_generation(generation_b, "B")
            destination.mkdir()

            original_open = helper._open_subject
            swapped = False

            def splice_before_second_subject(root_fd: int, subject: Path, directory_cache=None):
                nonlocal swapped
                if subject == Path("NembraCapture.xcworkspace") and not swapped:
                    replace_generated_root_membership(active, generation_b)
                    swapped = True
                return original_open(root_fd, subject, directory_cache)

            with mock.patch.object(helper, "_open_subject", side_effect=splice_before_second_subject):
                helper._copy_generated_subjects(active, destination)

            self.assertTrue(swapped)
            self.assertEqual((destination / "Podfile.lock").read_bytes(), b"LOCK-A\n")
            self.assertEqual(
                (destination / "NembraCapture.xcworkspace/contents.xcworkspacedata").read_bytes(),
                b"<Workspace-B/>\n",
            )
            self.assertEqual(
                (destination / "Pods/SyntheticPod.swift").read_bytes(),
                b"// POD-B\n",
            )
            self.assertEqual(
                (destination / "LocalSecrets/TuyaSDK/sdk.bin").read_bytes(),
                b"SDK-B\n",
            )
            self.assertEqual(
                (destination / "LocalSecrets/TuyaRuntime/identity.bin").read_bytes(),
                b"RUNTIME-B\n",
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)
