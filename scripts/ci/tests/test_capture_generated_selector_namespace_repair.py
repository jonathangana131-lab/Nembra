#!/usr/bin/env python3
"""Permanent regressions for accepted Capture compiler-input namespace authority."""

from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

HELPER = Path(__file__).resolve().parents[1] / "capture_accepted_build_input_snapshot.py"
spec = importlib.util.spec_from_file_location("capture_generated_selector_namespace_repair", HELPER)
assert spec and spec.loader
snapshot = importlib.util.module_from_spec(spec)
spec.loader.exec_module(snapshot)


def git(repo: Path, *arguments: str, input_text: str | None = None) -> str:
    completed = subprocess.run(
        ["/usr/bin/git", "-C", str(repo), *arguments],
        input=input_text,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if completed.returncode != 0:
        raise RuntimeError(
            f"git {' '.join(arguments)} failed rc={completed.returncode}: {completed.stderr.strip()}"
        )
    return completed.stdout.strip()


def hash_blob(repo: Path, payload: bytes) -> str:
    completed = subprocess.run(
        ["/usr/bin/git", "-C", str(repo), "hash-object", "-w", "--stdin"],
        input=payload,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if completed.returncode != 0:
        raise RuntimeError(
            f"git hash-object failed: {completed.stderr.decode('utf-8', 'replace')}"
        )
    return completed.stdout.decode("ascii").strip()


def seed_tracked_repo(root: Path) -> str:
    git(root, "init", "-q")
    git(root, "config", "user.email", "capture-selector-repair@example.invalid")
    git(root, "config", "user.name", "Capture Selector Repair")
    (root / "Sources").mkdir()
    (root / "Sources/App.swift").write_text("let accepted = true\n", encoding="utf-8")
    git(root, "add", "Sources")
    git(root, "commit", "-qm", "accepted source")
    return git(root, "rev-parse", "HEAD")


def seed_public_generated(root: Path) -> None:
    (root / "Podfile.lock").write_text("PODS:\n  - Synthetic\n", encoding="utf-8")
    workspace = root / "NembraCapture.xcworkspace"
    workspace.mkdir()
    (workspace / "contents.xcworkspacedata").write_text("<Workspace/>\n", encoding="utf-8")
    pods = root / "Pods"
    pods.mkdir()
    (pods / "SyntheticPod.swift").write_text("// synthetic pod\n", encoding="utf-8")


def seed_private(root: Path) -> None:
    sdk = root / "TuyaSDK"
    sdk.mkdir(parents=True)
    (sdk / "SyntheticSDK.swift").write_text("// private sdk\n", encoding="utf-8")
    runtime = root / "TuyaRuntime"
    runtime.mkdir(parents=True)
    (runtime / "SyntheticIdentity.swift").write_text(
        'let syntheticSecret = "PRIVATE-A"\n', encoding="utf-8"
    )


def seed_normal_private(repo: Path) -> None:
    local = repo / "LocalSecrets"
    local.mkdir()
    seed_private(local)


def seed_case_distinct_commit(repo: Path) -> str:
    git(repo, "init", "-q")
    git(repo, "config", "user.name", "Capture Namespace Repair")
    git(repo, "config", "user.email", "capture-namespace-repair@example.invalid")
    upper_blob = hash_blob(repo, b"UPPER\n")
    lower_blob = hash_blob(repo, b"lower\n")
    upper_tree = git(repo, "mktree", input_text=f"100644 blob {upper_blob}\tA.swift\n")
    lower_tree = git(repo, "mktree", input_text=f"100644 blob {lower_blob}\tB.swift\n")
    root_tree = git(
        repo,
        "mktree",
        input_text=(
            f"040000 tree {upper_tree}\tFoo\n"
            f"040000 tree {lower_tree}\tfoo\n"
        ),
    )
    return git(repo, "commit-tree", root_tree, "-m", "case-distinct tracked namespace")


class GeneratedSelectorNamespaceRepairTests(unittest.TestCase):
    def test_unadmitted_localsecrets_ancestor_symlink_fails_before_manifest(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-selector-escape-repair-") as raw:
            sandbox = Path(raw)
            repo = sandbox / "repo"
            repo.mkdir()
            source_sha = seed_tracked_repo(repo)
            seed_public_generated(repo)
            external = sandbox / "external-private"
            seed_private(external)
            os.symlink("../external-private", repo / "LocalSecrets")

            with self.assertRaises(snapshot.AcceptedBuildInputSnapshotError):
                snapshot.generated_manifest_sha256(repo, source_sha)

    def test_unadmitted_localsecrets_ancestor_symlink_fails_before_copy(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-selector-copy-repair-") as raw:
            sandbox = Path(raw)
            accepted_repo = sandbox / "accepted-repo"
            accepted_repo.mkdir()
            source_sha = seed_tracked_repo(accepted_repo)
            seed_public_generated(accepted_repo)
            seed_normal_private(accepted_repo)
            accepted_digest = snapshot.generated_manifest_sha256(accepted_repo, source_sha)

            # Preserve the same tracked Git graph and public generated bytes, but replace
            # only the unadmitted private selector ancestor with an external symlink.
            attacker_repo = sandbox / "attacker-repo"
            subprocess.run(
                ["/usr/bin/git", "clone", "-q", str(accepted_repo), str(attacker_repo)],
                check=True,
            )
            seed_public_generated(attacker_repo)
            external = sandbox / "external-private"
            seed_private(external)
            local = attacker_repo / "LocalSecrets"
            if local.exists() or local.is_symlink():
                if local.is_symlink():
                    local.unlink()
                else:
                    import shutil
                    shutil.rmtree(local)
            os.symlink("../external-private", local)

            destination = sandbox / "stage"
            with self.assertRaises(snapshot.AcceptedBuildInputSnapshotError):
                snapshot.stage_accepted_build_inputs(
                    attacker_repo,
                    source_sha,
                    destination,
                    accepted_digest,
                )
            self.assertFalse(destination.exists())

    def test_case_distinct_tracked_directory_prefixes_fail_before_materialization(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-tracked-namespace-repair-") as raw:
            repo = Path(raw) / "repo"
            repo.mkdir()
            source_sha = seed_case_distinct_commit(repo)
            with self.assertRaises(snapshot.AcceptedBuildInputSnapshotError):
                snapshot._git_tree_entries(repo, source_sha)
            destination = Path(raw) / "stage"
            with self.assertRaises(snapshot.AcceptedBuildInputSnapshotError):
                snapshot.materialize_tracked_source(repo, source_sha, destination)
            self.assertFalse(destination.exists())

    def test_normal_generated_tree_still_round_trips_with_owner_only_private_modes(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-selector-normal-repair-") as raw:
            repo = Path(raw) / "repo"
            repo.mkdir()
            source_sha = seed_tracked_repo(repo)
            seed_public_generated(repo)
            seed_normal_private(repo)
            (repo / "Pods/target").symlink_to("SyntheticPod.swift")
            accepted_digest = snapshot.generated_manifest_sha256(repo, source_sha)
            destination = Path(raw) / "stage"
            actual = snapshot.stage_accepted_build_inputs(
                repo, source_sha, destination, accepted_digest
            )
            self.assertEqual(actual, accepted_digest)
            self.assertEqual(
                (destination / "LocalSecrets/TuyaRuntime/SyntheticIdentity.swift").read_text(
                    encoding="utf-8"
                ),
                'let syntheticSecret = "PRIVATE-A"\n',
            )
            self.assertEqual(
                (destination / "LocalSecrets/TuyaRuntime/SyntheticIdentity.swift").stat().st_mode & 0o777,
                0o600,
            )
            self.assertEqual((destination / "LocalSecrets/TuyaRuntime").stat().st_mode & 0o777, 0o700)
            self.assertTrue((destination / "Pods/target").is_symlink())
            self.assertEqual(os.readlink(destination / "Pods/target"), "SyntheticPod.swift")


if __name__ == "__main__":
    unittest.main(verbosity=2)
