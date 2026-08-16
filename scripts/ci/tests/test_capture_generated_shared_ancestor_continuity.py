#!/usr/bin/env python3
"""Regression for coherent generated-selector ancestry and directory membership."""
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
    def test_manifest_holds_or_rejects_whole_localsecrets_generation_replacement(self) -> None:
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

            try:
                with mock.patch.object(helper, "_open_subject", side_effect=swap_before_runtime):
                    held = helper.canonical_generated_manifest(root, SOURCE_SHA)
            except helper.AcceptedBuildInputSnapshotError:
                self.assertTrue(swapped)
                return

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

    def test_copy_holds_or_rejects_whole_localsecrets_generation_replacement(self) -> None:
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

            try:
                with mock.patch.object(helper, "_open_subject", side_effect=swap_before_runtime):
                    helper._copy_generated_subjects(root, destination)
            except helper.AcceptedBuildInputSnapshotError:
                self.assertTrue(swapped)
                return

            self.assertTrue(swapped)
            self.assertEqual((destination / "LocalSecrets/TuyaSDK/sdk.bin").read_bytes(), b"SDK-A\n")
            self.assertEqual(
                (destination / "LocalSecrets/TuyaRuntime/identity.bin").read_bytes(),
                b"RUNTIME-A\n",
            )

    def test_manifest_rejects_or_holds_runtime_sibling_replacement_inside_held_parent(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-sibling-entry-manifest-") as raw:
            root = Path(raw)
            seed_common(root)
            generation_a = make_generation(root, "LocalSecrets.A", b"SDK-A\n", b"RUNTIME-A\n")
            generation_b = make_generation(root, "LocalSecrets.B", b"SDK-B\n", b"RUNTIME-B\n")
            generation_a.rename(root / "LocalSecrets")
            pure_a = helper.canonical_generated_manifest(root, SOURCE_SHA)
            original_open = helper._open_subject
            swapped = False

            def splice_runtime_inside_parent(root_fd: int, subject: Path, directory_cache=None):
                nonlocal swapped
                if subject == Path("LocalSecrets/TuyaRuntime") and not swapped:
                    active = root / "LocalSecrets"
                    (active / "TuyaRuntime").rename(active / "TuyaRuntime.A.attack")
                    (generation_b / "TuyaRuntime").rename(active / "TuyaRuntime")
                    swapped = True
                return original_open(root_fd, subject, directory_cache)

            try:
                with mock.patch.object(helper, "_open_subject", side_effect=splice_runtime_inside_parent):
                    held = helper.canonical_generated_manifest(root, SOURCE_SHA)
            except helper.AcceptedBuildInputSnapshotError:
                self.assertTrue(swapped)
                return

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

    def test_copy_rejects_or_holds_runtime_sibling_replacement_inside_held_parent(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-sibling-entry-copy-") as raw:
            root = Path(raw)
            seed_common(root)
            generation_a = make_generation(root, "LocalSecrets.A", b"SDK-A\n", b"RUNTIME-A\n")
            generation_b = make_generation(root, "LocalSecrets.B", b"SDK-B\n", b"RUNTIME-B\n")
            generation_a.rename(root / "LocalSecrets")
            destination = root / "stage"
            destination.mkdir()
            original_open = helper._open_subject
            swapped = False

            def splice_runtime_inside_parent(root_fd: int, subject: Path, directory_cache=None):
                nonlocal swapped
                if subject == Path("LocalSecrets/TuyaRuntime") and not swapped:
                    active = root / "LocalSecrets"
                    (active / "TuyaRuntime").rename(active / "TuyaRuntime.A.attack")
                    (generation_b / "TuyaRuntime").rename(active / "TuyaRuntime")
                    swapped = True
                return original_open(root_fd, subject, directory_cache)

            try:
                with mock.patch.object(helper, "_open_subject", side_effect=splice_runtime_inside_parent):
                    helper._copy_generated_subjects(root, destination)
            except helper.AcceptedBuildInputSnapshotError:
                self.assertTrue(swapped)
                return

            self.assertTrue(swapped)
            self.assertEqual((destination / "LocalSecrets/TuyaSDK/sdk.bin").read_bytes(), b"SDK-A\n")
            self.assertEqual(
                (destination / "LocalSecrets/TuyaRuntime/identity.bin").read_bytes(),
                b"RUNTIME-A\n",
            )


    def test_manifest_rejects_runtime_swap_after_cached_parent_revalidation(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-final-child-manifest-reject-") as raw:
            root = Path(raw)
            seed_common(root)
            generation_a = make_generation(root, "LocalSecrets.A", b"SDK-A\n", b"RUNTIME-A\n")
            generation_b = make_generation(root, "LocalSecrets.B", b"SDK-B\n", b"RUNTIME-B\n")
            generation_a.rename(root / "LocalSecrets")
            original_open = helper._open_directory_at
            swapped = False

            def splice_after_parent_check(parent_fd: int, name: str, relative: Path) -> int:
                nonlocal swapped
                if relative == Path("LocalSecrets/TuyaRuntime") and not swapped:
                    active = root / "LocalSecrets"
                    (active / "TuyaRuntime").rename(active / "TuyaRuntime.A.attack")
                    (generation_b / "TuyaRuntime").rename(active / "TuyaRuntime")
                    swapped = True
                return original_open(parent_fd, name, relative)

            with mock.patch.object(helper, "_open_directory_at", side_effect=splice_after_parent_check):
                with self.assertRaises(helper.AcceptedBuildInputSnapshotError):
                    helper.canonical_generated_manifest(root, SOURCE_SHA)
            self.assertTrue(swapped)

    def test_copy_rejects_runtime_swap_after_cached_parent_revalidation(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-final-child-copy-reject-") as raw:
            root = Path(raw)
            seed_common(root)
            generation_a = make_generation(root, "LocalSecrets.A", b"SDK-A\n", b"RUNTIME-A\n")
            generation_b = make_generation(root, "LocalSecrets.B", b"SDK-B\n", b"RUNTIME-B\n")
            generation_a.rename(root / "LocalSecrets")
            destination = root / "stage"
            destination.mkdir()
            original_open = helper._open_directory_at
            swapped = False

            def splice_after_parent_check(parent_fd: int, name: str, relative: Path) -> int:
                nonlocal swapped
                if relative == Path("LocalSecrets/TuyaRuntime") and not swapped:
                    active = root / "LocalSecrets"
                    (active / "TuyaRuntime").rename(active / "TuyaRuntime.A.attack")
                    (generation_b / "TuyaRuntime").rename(active / "TuyaRuntime")
                    swapped = True
                return original_open(parent_fd, name, relative)

            with mock.patch.object(helper, "_open_directory_at", side_effect=splice_after_parent_check):
                with self.assertRaises(helper.AcceptedBuildInputSnapshotError):
                    helper._copy_generated_subjects(root, destination)
            self.assertTrue(swapped)
            self.assertEqual(
                (destination / "LocalSecrets/TuyaSDK/sdk.bin").read_bytes(),
                b"SDK-A\n",
            )
            self.assertFalse(
                (destination / "LocalSecrets/TuyaRuntime/identity.bin").exists()
            )



    def test_manifest_rejects_generated_root_sibling_membership_splice(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-root-generation-manifest-") as raw:
            outer = Path(raw)
            root = outer / "repo"
            root.mkdir()
            seed_common(root)
            generation = make_generation(root, "LocalSecrets.A", b"SDK-A\n", b"RUNTIME-A\n")
            generation.rename(root / "LocalSecrets")

            replacement_lock = outer / "replacement-Podfile.lock"
            replacement_lock.write_text("PODS:\n  - Replacement\n", encoding="utf-8")
            replacement_pods = outer / "replacement-Pods"
            replacement_pods.mkdir()
            (replacement_pods / "SyntheticPod.swift").write_text("// replacement pod\n", encoding="utf-8")

            original_open = helper._open_subject
            swapped = False

            def splice_before_pods(root_fd: int, subject: Path, directory_cache=None):
                nonlocal swapped
                if subject == Path("Pods") and not swapped:
                    (root / "Podfile.lock").rename(root / "Podfile.lock.A.attack")
                    replacement_lock.rename(root / "Podfile.lock")
                    (root / "Pods").rename(root / "Pods.A.attack")
                    replacement_pods.rename(root / "Pods")
                    swapped = True
                return original_open(root_fd, subject, directory_cache)

            with mock.patch.object(helper, "_open_subject", side_effect=splice_before_pods):
                with self.assertRaises(helper.AcceptedBuildInputSnapshotError):
                    helper.canonical_generated_manifest(root, SOURCE_SHA)
            self.assertTrue(swapped)

    def test_copy_rejects_generated_root_sibling_membership_splice_before_use(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-root-generation-copy-") as raw:
            outer = Path(raw)
            root = outer / "repo"
            root.mkdir()
            seed_common(root)
            generation = make_generation(root, "LocalSecrets.A", b"SDK-A\n", b"RUNTIME-A\n")
            generation.rename(root / "LocalSecrets")
            destination = outer / "stage"
            destination.mkdir()

            replacement_lock = outer / "replacement-Podfile.lock"
            replacement_lock.write_text("PODS:\n  - Replacement\n", encoding="utf-8")
            replacement_pods = outer / "replacement-Pods"
            replacement_pods.mkdir()
            (replacement_pods / "SyntheticPod.swift").write_text("// replacement pod\n", encoding="utf-8")

            original_open = helper._open_subject
            swapped = False

            def splice_before_pods(root_fd: int, subject: Path, directory_cache=None):
                nonlocal swapped
                if subject == Path("Pods") and not swapped:
                    (root / "Podfile.lock").rename(root / "Podfile.lock.A.attack")
                    replacement_lock.rename(root / "Podfile.lock")
                    (root / "Pods").rename(root / "Pods.A.attack")
                    replacement_pods.rename(root / "Pods")
                    swapped = True
                return original_open(root_fd, subject, directory_cache)

            with mock.patch.object(helper, "_open_subject", side_effect=splice_before_pods):
                with self.assertRaises(helper.AcceptedBuildInputSnapshotError):
                    helper._copy_generated_subjects(root, destination)
            self.assertTrue(swapped)
            self.assertTrue((destination / "Podfile.lock").exists())
            self.assertFalse((destination / "Pods/SyntheticPod.swift").exists())

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

            cache: dict[Path, tuple[int, os.stat_result]] = {}
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


    def test_cached_reuse_dup_failure_does_not_close_reused_fd_number(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-cached-reuse-dup-cleanup-") as raw:
            root = Path(raw)
            (root / "LocalSecrets/TuyaSDK").mkdir(parents=True)
            (root / "LocalSecrets/TuyaRuntime").mkdir(parents=True)
            sentinel_path = root / "sentinel.bin"
            sentinel_path.write_bytes(b"sentinel\n")
            root_fd = helper._open_repository_root(root)
            cache: dict[Path, tuple[int, os.stat_result]] = {}
            opened, _metadata, _kind = helper._open_subject(
                root_fd,
                Path("LocalSecrets/TuyaSDK"),
                cache,
            )
            os.close(opened)
            cached_descriptor = cache[Path("LocalSecrets")][0]
            real_dup = os.dup
            sentinel_fd: int | None = None

            def fail_cached_reuse(descriptor: int) -> int:
                nonlocal sentinel_fd
                if descriptor == cached_descriptor:
                    sentinel_fd = os.open(sentinel_path, os.O_RDONLY)
                    raise OSError(errno.EMFILE, "synthetic cached-reuse dup exhaustion")
                return real_dup(descriptor)

            try:
                with mock.patch.object(helper.os, "dup", side_effect=fail_cached_reuse):
                    with self.assertRaisesRegex(OSError, "synthetic cached-reuse dup exhaustion"):
                        helper._open_subject(
                            root_fd,
                            Path("LocalSecrets/TuyaRuntime"),
                            cache,
                        )
                self.assertIsNotNone(sentinel_fd)
                assert sentinel_fd is not None
                os.fstat(sentinel_fd)
                os.fstat(cached_descriptor)
            finally:
                if sentinel_fd is not None:
                    try:
                        os.close(sentinel_fd)
                    except OSError:
                        pass
                helper._close_directory_cache(cache)
                os.close(root_fd)


if __name__ == "__main__":
    unittest.main(verbosity=2)
