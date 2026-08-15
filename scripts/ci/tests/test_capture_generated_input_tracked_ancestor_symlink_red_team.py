#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
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
        ["git", "-C", str(repo), *args],
        text=True,
        capture_output=True,
        check=True,
    )
    return completed.stdout.strip()


def seed_tracked_source_with_generated_ancestor_symlink(repo: Path) -> str:
    git(repo, "init", "-q")
    git(repo, "config", "user.email", "capture-red-team@example.invalid")
    git(repo, "config", "user.name", "Capture Red Team")

    (repo / "Sources").mkdir()
    (repo / "Sources/App.swift").write_text("let accepted = true\n", encoding="utf-8")

    # The accepted Git tree owns an ancestor of two generated subjects. The
    # symlink is lexically confined to the future stage root, so tracked-source
    # materialization admits it. Generated materialization must nevertheless
    # reject this topology instead of traversing the tracked ancestor.
    os.symlink("GeneratedSecrets", repo / "LocalSecrets")

    git(repo, "add", "Sources", "LocalSecrets")
    git(repo, "commit", "-qm", "accepted tracked ancestor symlink")
    return git(repo, "rev-parse", "HEAD")


def seed_generated_inputs(repo: Path) -> None:
    (repo / "Podfile.lock").write_text("PODS:\n  - ThingSmartHomeKit (7.8.0)\n", encoding="utf-8")

    workspace = repo / "NembraCapture.xcworkspace"
    workspace.mkdir()
    (workspace / "contents.xcworkspacedata").write_text("<Workspace/>\n", encoding="utf-8")

    pods = repo / "Pods/ThingSmartHomeKit"
    pods.mkdir(parents=True)
    (pods / "libTuya.a").write_bytes(b"public-pod-A")

    sdk = repo / "GeneratedSecrets/TuyaSDK"
    (sdk / "Build").mkdir(parents=True)
    (sdk / "ThingSmartCryption.podspec").write_text("Pod::Spec.new\n", encoding="utf-8")
    (sdk / "Build/libThingSmartCryption.a").write_bytes(b"private-sdk-A")

    runtime = repo / "GeneratedSecrets/TuyaRuntime"
    sources = runtime / "Sources/NembraTuyaPrivateConfig"
    sources.mkdir(parents=True)
    (runtime / "NembraTuyaPrivateConfig.podspec").write_text("Pod::Spec.new\n", encoding="utf-8")
    (sources / "Identity.swift").write_text('let secret = "SECRET-A"\n', encoding="utf-8")


class GeneratedInputTrackedAncestorSymlinkRedTeamTests(unittest.TestCase):
    def test_current_collision_check_admits_tracked_ancestor_symlink(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            repo = Path(raw) / "repo"
            repo.mkdir()
            source_sha = seed_tracked_source_with_generated_ancestor_symlink(repo)
            seed_generated_inputs(repo)

            accepted_manifest = snapshot.canonical_generated_manifest(repo, source_sha)
            accepted_digest = snapshot.generated_manifest_sha256(repo, source_sha)
            payload = json.loads(accepted_manifest)

            # The accepted generated-input manifest has only logical
            # LocalSecrets/... paths. It does not list the physical alias root
            # reached through the accepted tracked ancestor symlink.
            self.assertTrue(any(entry["path"].startswith("LocalSecrets/TuyaSDK") for entry in payload["entries"]))
            self.assertFalse(any(entry["path"].startswith("GeneratedSecrets/") for entry in payload["entries"]))

            destination = Path(raw) / "stage"
            actual = snapshot.stage_accepted_build_inputs(
                repo,
                source_sha,
                destination,
                accepted_digest,
            )

            # EXPLOIT-POSITIVE: current #3359 returns accepted even though a
            # tracked symlink is an ancestor of generated subjects and causes
            # their bytes to be materialized under an unlisted physical alias.
            self.assertEqual(actual, accepted_digest)
            self.assertTrue((destination / "LocalSecrets").is_symlink())
            self.assertEqual(os.readlink(destination / "LocalSecrets"), "GeneratedSecrets")
            self.assertTrue((destination / "GeneratedSecrets/TuyaSDK/Build/libThingSmartCryption.a").is_file())
            self.assertTrue((destination / "GeneratedSecrets/TuyaRuntime/Sources/NembraTuyaPrivateConfig/Identity.swift").is_file())

            tracked = {
                relative
                for _mode, _kind, _oid, relative in snapshot._git_tree_entries(repo, source_sha)
            }
            self.assertIn(Path("LocalSecrets"), tracked)
            self.assertNotIn(Path("LocalSecrets/TuyaSDK"), tracked)


if __name__ == "__main__":
    unittest.main(verbosity=2)
