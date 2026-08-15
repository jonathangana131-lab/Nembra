#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

HELPER = Path(__file__).resolve().parents[1] / "capture_accepted_build_input_snapshot.py"
spec = importlib.util.spec_from_file_location("snapshot", HELPER)
assert spec and spec.loader
snapshot = importlib.util.module_from_spec(spec)
spec.loader.exec_module(snapshot)


def git(repo: Path, *args: str) -> str:
    completed = subprocess.run(
        ["git", "-C", str(repo), *args], text=True, capture_output=True, check=True
    )
    return completed.stdout.strip()


def seed_repo(root: Path) -> str:
    git(root, "init", "-q")
    git(root, "config", "user.email", "capture@example.invalid")
    git(root, "config", "user.name", "Capture Test")
    (root / "NembraCapture.xcodeproj").mkdir()
    (root / "NembraCapture.xcodeproj/project.pbxproj").write_text("// exact tracked project\n", encoding="utf-8")
    (root / "Sources").mkdir()
    (root / "Sources/App.swift").write_text("let accepted = true\n", encoding="utf-8")
    (root / "Scripts").mkdir()
    tool = root / "Scripts/tool.sh"
    tool.write_text("#!/bin/sh\necho accepted\n", encoding="utf-8")
    tool.chmod(0o755)
    git(root, "add", "NembraCapture.xcodeproj", "Sources", "Scripts")
    git(root, "commit", "-qm", "accepted")
    return git(root, "rev-parse", "HEAD")


def seed_generated(root: Path, *, secret: str = "APP-SECRET-A") -> None:
    (root / "Podfile.lock").write_text("PODS:\n  - ThingSmartHomeKit (7.8.0)\n", encoding="utf-8")
    workspace = root / "NembraCapture.xcworkspace"
    workspace.mkdir()
    (workspace / "contents.xcworkspacedata").write_text("<Workspace/>\n", encoding="utf-8")
    pods = root / "Pods"
    (pods / "ThingSmartHomeKit").mkdir(parents=True)
    (pods / "ThingSmartHomeKit/libTuya.a").write_bytes(b"public-pod-bytes-A")
    sdk = root / "LocalSecrets/TuyaSDK"
    (sdk / "Build").mkdir(parents=True)
    (sdk / "ThingSmartCryption.podspec").write_text("Pod::Spec.new\n", encoding="utf-8")
    (sdk / "Build/libThingSmartCryption.a").write_bytes(b"private-security-A")
    runtime = root / "LocalSecrets/TuyaRuntime"
    sources = runtime / "Sources/NembraTuyaPrivateConfig"
    sources.mkdir(parents=True)
    (runtime / "NembraTuyaPrivateConfig.podspec").write_text("Pod::Spec.new\n", encoding="utf-8")
    (sources / "Identity.swift").write_text(f'let secret = "{secret}"\n', encoding="utf-8")
    (runtime / "ResolvedTuyaDependencyProvenance.txt").write_text("schema=1\nprivate-hashes-only\n", encoding="utf-8")


class AcceptedBuildInputSnapshotTests(unittest.TestCase):
    def test_manifest_is_deterministic_hash_only_and_binds_source_sha(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            source_sha = seed_repo(root)
            seed_generated(root)
            first = snapshot.canonical_generated_manifest(root, source_sha)
            second = snapshot.canonical_generated_manifest(root, source_sha)
            self.assertEqual(first, second)
            self.assertNotIn(b"APP-SECRET-A", first)
            self.assertEqual(len(snapshot.generated_manifest_sha256(root, source_sha)), 64)
            self.assertNotEqual(
                snapshot.generated_manifest_sha256(root, source_sha),
                snapshot.generated_manifest_sha256(root, "0" * 40),
            )

    def test_stage_uses_exact_git_bytes_not_mutable_tracked_checkout(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw) / "repo"
            root.mkdir()
            source_sha = seed_repo(root)
            seed_generated(root)
            accepted = snapshot.generated_manifest_sha256(root, source_sha)
            (root / "Sources/App.swift").write_text("let attacker = true\n", encoding="utf-8")
            destination = Path(raw) / "stage"
            actual = snapshot.stage_accepted_build_inputs(root, source_sha, destination, accepted)
            self.assertEqual(actual, accepted)
            self.assertEqual(
                (destination / "Sources/App.swift").read_text(encoding="utf-8"),
                "let accepted = true\n",
            )
            self.assertEqual(
                (destination / "LocalSecrets/TuyaRuntime/Sources/NembraTuyaPrivateConfig/Identity.swift").read_text(encoding="utf-8"),
                'let secret = "APP-SECRET-A"\n',
            )

    def test_staged_generated_inputs_remain_owner_only(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw) / "repo"
            root.mkdir()
            source_sha = seed_repo(root)
            seed_generated(root)
            accepted = snapshot.generated_manifest_sha256(root, source_sha)
            destination = Path(raw) / "stage"
            snapshot.stage_accepted_build_inputs(root, source_sha, destination, accepted)

            for subject in snapshot.GENERATED_SUBJECTS:
                subject_path = destination / subject
                candidates = [subject_path]
                if subject_path.is_dir() and not subject_path.is_symlink():
                    candidates.extend(subject_path.rglob("*"))
                for candidate in candidates:
                    if candidate.is_symlink():
                        continue
                    with self.subTest(path=candidate.relative_to(destination)):
                        self.assertEqual(
                            candidate.stat().st_mode & 0o077,
                            0,
                            f"generated/private staged subject widened group/other authority: {candidate}",
                        )

    def test_generated_private_ancestor_symlink_escape_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw) / "repo"
            root.mkdir()
            source_sha = seed_repo(root)
            seed_generated(root)
            accepted = snapshot.generated_manifest_sha256(root, source_sha)

            external_private = Path(raw) / "external-private"
            os.rename(root / "LocalSecrets", external_private)
            os.symlink("../external-private", root / "LocalSecrets")
            self.assertTrue((root / "LocalSecrets").is_symlink())

            with self.assertRaises(snapshot.AcceptedBuildInputSnapshotError):
                snapshot.canonical_generated_manifest(root, source_sha)

            destination = Path(raw) / "stage"
            with self.assertRaises(snapshot.AcceptedBuildInputSnapshotError):
                snapshot.stage_accepted_build_inputs(root, source_sha, destination, accepted)
            self.assertFalse(destination.exists())

    def test_changed_private_input_fails_manifest_and_destroys_candidate(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw) / "repo"
            root.mkdir()
            source_sha = seed_repo(root)
            seed_generated(root)
            accepted = snapshot.generated_manifest_sha256(root, source_sha)
            identity = root / "LocalSecrets/TuyaRuntime/Sources/NembraTuyaPrivateConfig/Identity.swift"
            identity.write_text('let secret = "APP-SECRET-B"\n', encoding="utf-8")
            destination = Path(raw) / "stage"
            with self.assertRaises(snapshot.AcceptedBuildInputSnapshotError):
                snapshot.stage_accepted_build_inputs(root, source_sha, destination, accepted)
            self.assertFalse(destination.exists())

    def test_changed_generated_pod_fails_even_when_lock_is_unchanged(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw) / "repo"
            root.mkdir()
            source_sha = seed_repo(root)
            seed_generated(root)
            accepted = snapshot.generated_manifest_sha256(root, source_sha)
            lock_before = (root / "Podfile.lock").read_bytes()
            (root / "Pods/ThingSmartHomeKit/libTuya.a").write_bytes(b"transient-attacker-pod")
            self.assertEqual((root / "Podfile.lock").read_bytes(), lock_before)
            with self.assertRaises(snapshot.AcceptedBuildInputSnapshotError):
                snapshot.stage_accepted_build_inputs(root, source_sha, Path(raw) / "stage", accepted)

    def test_internal_relative_symlink_is_bound_but_escape_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw) / "repo"
            root.mkdir()
            source_sha = seed_repo(root)
            seed_generated(root)
            os.symlink("ThingSmartHomeKit/libTuya.a", root / "Pods/current-tuya")
            accepted = snapshot.generated_manifest_sha256(root, source_sha)
            destination = Path(raw) / "stage"
            snapshot.stage_accepted_build_inputs(root, source_sha, destination, accepted)
            self.assertTrue((destination / "Pods/current-tuya").is_symlink())
            self.assertEqual(os.readlink(destination / "Pods/current-tuya"), "ThingSmartHomeKit/libTuya.a")

        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw) / "repo"
            root.mkdir()
            source_sha = seed_repo(root)
            seed_generated(root)
            os.symlink("../../../../outside", root / "Pods/escape")
            with self.assertRaises(snapshot.AcceptedBuildInputSnapshotError):
                snapshot.canonical_generated_manifest(root, source_sha)

    def test_special_file_and_tracked_generated_collision_fail_closed(self) -> None:
        if hasattr(os, "mkfifo"):
            with tempfile.TemporaryDirectory() as raw:
                root = Path(raw) / "repo"
                root.mkdir()
                source_sha = seed_repo(root)
                seed_generated(root)
                os.mkfifo(root / "Pods/poison.fifo")
                with self.assertRaises(snapshot.AcceptedBuildInputSnapshotError):
                    snapshot.canonical_generated_manifest(root, source_sha)

        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw) / "repo"
            root.mkdir()
            source_sha = seed_repo(root)
            (root / "Podfile.lock").write_text("tracked lock\n", encoding="utf-8")
            git(root, "add", "Podfile.lock")
            git(root, "commit", "-qm", "track collision")
            source_sha = git(root, "rev-parse", "HEAD")
            seed_generated(root)
            accepted = snapshot.generated_manifest_sha256(root, source_sha)
            with self.assertRaises(snapshot.AcceptedBuildInputSnapshotError):
                snapshot.stage_accepted_build_inputs(root, source_sha, Path(raw) / "stage", accepted)

    def test_case_distinct_tracked_prefixes_fail_before_materialization(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw) / "repo"
            root.mkdir()
            git(root, "init", "-q")
            git(root, "config", "user.email", "capture@example.invalid")
            git(root, "config", "user.name", "Capture Test")
            (root / "Foo").mkdir()
            (root / "foo").mkdir()
            (root / "Foo/A.swift").write_text("UPPER\n", encoding="utf-8")
            (root / "foo/B.swift").write_text("lower\n", encoding="utf-8")
            git(root, "add", "Foo/A.swift", "foo/B.swift")
            git(root, "commit", "-qm", "case-distinct tracked namespace")
            source_sha = git(root, "rev-parse", "HEAD")
            with self.assertRaises(snapshot.AcceptedBuildInputSnapshotError):
                snapshot._git_tree_entries(root, source_sha)
            destination = Path(raw) / "stage"
            with self.assertRaises(snapshot.AcceptedBuildInputSnapshotError):
                snapshot.materialize_tracked_source(root, source_sha, destination)
            self.assertFalse(destination.exists())

    def test_casefolded_tracked_ancestor_cannot_alias_generated_subject(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw) / "repo"
            root.mkdir()
            seed_repo(root)
            os.symlink(".", root / "localsecrets")
            git(root, "add", "localsecrets")
            git(root, "commit", "-qm", "track case-fold generated ancestor alias")
            source_sha = git(root, "rev-parse", "HEAD")
            seed_generated(root)
            accepted = snapshot.generated_manifest_sha256(root, source_sha)
            destination = Path(raw) / "stage"
            with self.assertRaises(snapshot.AcceptedBuildInputSnapshotError):
                snapshot.stage_accepted_build_inputs(root, source_sha, destination, accepted)
            self.assertFalse(destination.exists())
            self.assertTrue(snapshot._namespace_paths_overlap(Path("localsecrets"), Path("LocalSecrets/TuyaSDK")))

    def test_tracked_ancestor_symlink_cannot_alias_generated_subject(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw) / "repo"
            root.mkdir()
            seed_repo(root)
            os.symlink(".", root / "LocalSecrets")
            git(root, "add", "LocalSecrets")
            git(root, "commit", "-qm", "track generated ancestor alias")
            source_sha = git(root, "rev-parse", "HEAD")
            seed_generated(root)
            with self.assertRaises(snapshot.AcceptedBuildInputSnapshotError):
                snapshot.generated_manifest_sha256(root, source_sha)
            destination = Path(raw) / "stage"
            self.assertFalse(destination.exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
