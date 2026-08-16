#!/usr/bin/env python3
"""Exploit-positive oracle for mixed generated subjects across one mutable repo root."""
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
    spec = importlib.util.spec_from_file_location("nembra_generated_root_sibling_splice", HELPER)
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


def entry_sha(payload: dict[str, object], path: str) -> str:
    entries = payload.get("entries")
    if not isinstance(entries, list):
        raise AssertionError("manifest entries missing")
    for entry in entries:
        if isinstance(entry, dict) and entry.get("path") == path:
            return str(entry.get("sha256"))
    raise AssertionError(f"manifest entry missing: {path}")


class CaptureGeneratedRootSiblingSpliceRedTeamTests(unittest.TestCase):
    def test_manifest_can_mint_lock_a_with_pods_b_after_root_membership_splice(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(
            prefix="nembra-generated-root-sibling-splice-",
            dir=REPOSITORY,
        ) as raw:
            outer = Path(raw)
            root_a = outer / "repo-a"
            root_b = outer / "repo-b"
            lock_a = b"PODS:\n  - A\n"
            lock_b = b"PODS:\n  - B\n"
            pod_a = b"POD-A\n"
            pod_b = b"POD-B\n"
            seed_repo(root_a, lock=lock_a, pod=pod_a)
            seed_repo(root_b, lock=lock_b, pod=pod_b)

            pure_a = json.loads(helper.canonical_generated_manifest(root_a, SOURCE_SHA))
            pure_b = json.loads(helper.canonical_generated_manifest(root_b, SOURCE_SHA))

            replacement_lock = outer / "replacement-Podfile.lock"
            replacement_lock.write_bytes(lock_b)
            replacement_pods = outer / "replacement-Pods"
            replacement_pods.mkdir()
            (replacement_pods / "payload.bin").write_bytes(pod_b)

            original_open_subject = helper._open_subject
            swapped = False

            def splice_before_pods(root_fd: int, subject: Path, directory_cache=None):
                nonlocal swapped
                if subject == Path("Pods") and not swapped:
                    (root_a / "Podfile.lock").rename(root_a / "Podfile.lock.A.attack")
                    replacement_lock.rename(root_a / "Podfile.lock")
                    (root_a / "Pods").rename(root_a / "Pods.A.attack")
                    replacement_pods.rename(root_a / "Pods")
                    swapped = True
                return original_open_subject(root_fd, subject, directory_cache)

            with mock.patch.object(helper, "_open_subject", side_effect=splice_before_pods):
                mixed = json.loads(helper.canonical_generated_manifest(root_a, SOURCE_SHA))

            self.assertTrue(swapped)
            self.assertEqual(
                entry_sha(mixed, "Podfile.lock"),
                hashlib.sha256(lock_a).hexdigest(),
            )
            self.assertEqual(
                entry_sha(mixed, "Pods/payload.bin"),
                hashlib.sha256(pod_b).hexdigest(),
            )
            self.assertNotEqual(mixed, pure_a)
            self.assertNotEqual(mixed, pure_b)

    def test_copy_can_stage_lock_a_with_pods_b_after_root_membership_splice(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(
            prefix="nembra-generated-root-copy-splice-",
            dir=REPOSITORY,
        ) as raw:
            outer = Path(raw)
            root = outer / "repo"
            lock_a = b"PODS:\n  - A\n"
            lock_b = b"PODS:\n  - B\n"
            pod_a = b"POD-A\n"
            pod_b = b"POD-B\n"
            seed_repo(root, lock=lock_a, pod=pod_a)
            destination = outer / "stage"
            destination.mkdir()

            replacement_lock = outer / "replacement-Podfile.lock"
            replacement_lock.write_bytes(lock_b)
            replacement_pods = outer / "replacement-Pods"
            replacement_pods.mkdir()
            (replacement_pods / "payload.bin").write_bytes(pod_b)

            original_open_subject = helper._open_subject
            swapped = False

            def splice_before_pods(root_fd: int, subject: Path, directory_cache=None):
                nonlocal swapped
                if subject == Path("Pods") and not swapped:
                    (root / "Podfile.lock").rename(root / "Podfile.lock.A.attack")
                    replacement_lock.rename(root / "Podfile.lock")
                    (root / "Pods").rename(root / "Pods.A.attack")
                    replacement_pods.rename(root / "Pods")
                    swapped = True
                return original_open_subject(root_fd, subject, directory_cache)

            with mock.patch.object(helper, "_open_subject", side_effect=splice_before_pods):
                helper._copy_generated_subjects(root, destination)

            self.assertTrue(swapped)
            self.assertEqual((destination / "Podfile.lock").read_bytes(), lock_a)
            self.assertEqual((destination / "Pods/payload.bin").read_bytes(), pod_b)


if __name__ == "__main__":
    unittest.main(verbosity=2)
