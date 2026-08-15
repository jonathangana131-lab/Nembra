#!/usr/bin/env python3
"""Exploit-positive macOS witness for tracked/tracked case-fold directory aliases."""

from __future__ import annotations

import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
SNAPSHOT_HELPER = REPOSITORY / "scripts/ci/capture_accepted_build_input_snapshot.py"


def load_helper():
    spec = importlib.util.spec_from_file_location(
        "nembra_tracked_casefold_directory_alias_red_team", SNAPSHOT_HELPER
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load accepted build-input snapshot helper")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


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
        raise RuntimeError(f"git hash-object failed: {completed.stderr.decode('utf-8', 'replace')}")
    return completed.stdout.decode("ascii").strip()


def seed_case_distinct_commit(repo: Path) -> str:
    git(repo, "init", "-q")
    git(repo, "config", "user.name", "Nembra Red Team")
    git(repo, "config", "user.email", "nembra-red-team@example.invalid")

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


def seed_generated_inputs(repo: Path) -> None:
    (repo / "Podfile.lock").write_text("PODS:\n  - Synthetic\n", encoding="utf-8")
    workspace = repo / "NembraCapture.xcworkspace"
    workspace.mkdir()
    (workspace / "contents.xcworkspacedata").write_text("<Workspace/>\n", encoding="utf-8")
    pods = repo / "Pods"
    pods.mkdir()
    (pods / "SyntheticPod.swift").write_text("// synthetic pod\n", encoding="utf-8")
    sdk = repo / "LocalSecrets/TuyaSDK"
    runtime = repo / "LocalSecrets/TuyaRuntime"
    sdk.mkdir(parents=True)
    runtime.mkdir(parents=True)
    (sdk / "SyntheticSDK.swift").write_text("// synthetic sdk\n", encoding="utf-8")
    (runtime / "SyntheticIdentity.swift").write_text("// synthetic identity\n", encoding="utf-8")


class CaptureTrackedCasefoldDirectoryAliasRedTeamTests(unittest.TestCase):
    def test_case_distinct_git_directories_merge_in_case_insensitive_stage(self) -> None:
        helper = load_helper()
        with tempfile.TemporaryDirectory(prefix="nembra-tracked-casefold-alias-") as raw:
            root = Path(raw)
            probe = root / "CaseProbe"
            probe.mkdir()
            if not (root / "caseprobe").exists():
                self.fail("red-team witness requires the field-macOS case-insensitive namespace")
            probe.rmdir()

            repo = root / "repo"
            repo.mkdir()
            source_sha = seed_case_distinct_commit(repo)
            seed_generated_inputs(repo)

            tracked = {
                relative
                for _mode, _kind, _oid, relative in helper._git_tree_entries(repo, source_sha)
            }
            self.assertEqual(tracked, {Path("Foo/A.swift"), Path("foo/B.swift")})
            self.assertEqual(
                helper._namespace_key(Path("Foo")), helper._namespace_key(Path("foo"))
            )

            accepted_manifest = helper.generated_manifest_sha256(repo, source_sha)
            stage = root / "stage"
            actual_manifest = helper.stage_accepted_build_inputs(
                repo, source_sha, stage, accepted_manifest
            )
            self.assertEqual(actual_manifest, accepted_manifest)

            # The exact Git tree has two distinct directory objects, but the admitted
            # compiler stage collapses those names onto one APFS directory. Both files
            # are therefore visible through one namespace that did not exist in Git.
            upper_directory = (stage / "Foo").stat()
            lower_directory = (stage / "foo").stat()
            self.assertEqual(
                (upper_directory.st_dev, upper_directory.st_ino),
                (lower_directory.st_dev, lower_directory.st_ino),
            )
            self.assertEqual((stage / "Foo/A.swift").read_bytes(), b"UPPER\n")
            self.assertEqual((stage / "Foo/B.swift").read_bytes(), b"lower\n")
            self.assertEqual((stage / "foo/A.swift").read_bytes(), b"UPPER\n")
            self.assertEqual((stage / "foo/B.swift").read_bytes(), b"lower\n")


if __name__ == "__main__":
    unittest.main(verbosity=2)
