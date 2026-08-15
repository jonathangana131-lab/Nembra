#!/usr/bin/env python3
"""Exploit-positive validation for generated/private subject ancestor custody.

SUCCESS on the attacked parent means the accepted-input snapshot follows an
unadmitted LocalSecrets ancestor symlink outside the repository and can promote
those external private bytes under the canonical logical subject names.
"""

from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

HELPER = Path(__file__).resolve().parents[1] / "capture_accepted_build_input_snapshot.py"
spec = importlib.util.spec_from_file_location("capture_accepted_build_input_snapshot_red_team", HELPER)
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


def seed_tracked_repo(root: Path) -> str:
    git(root, "init", "-q")
    git(root, "config", "user.email", "capture@example.invalid")
    git(root, "config", "user.name", "Capture Red Team")
    (root / "Sources").mkdir()
    (root / "Sources/App.swift").write_text("let accepted = true\n", encoding="utf-8")
    git(root, "add", "Sources")
    git(root, "commit", "-qm", "accepted source")
    return git(root, "rev-parse", "HEAD")


def seed_public_generated(root: Path) -> None:
    (root / "Podfile.lock").write_text("PODS:\n  - ThingSmartHomeKit (7.8.0)\n", encoding="utf-8")
    workspace = root / "NembraCapture.xcworkspace"
    workspace.mkdir()
    (workspace / "contents.xcworkspacedata").write_text("<Workspace/>\n", encoding="utf-8")
    pod = root / "Pods/ThingSmartHomeKit"
    pod.mkdir(parents=True)
    (pod / "libTuya.a").write_bytes(b"public-pod")


def seed_external_private(root: Path) -> None:
    sdk = root / "TuyaSDK"
    (sdk / "Build").mkdir(parents=True)
    (sdk / "ThingSmartCryption.podspec").write_text("Pod::Spec.new\n", encoding="utf-8")
    (sdk / "Build/libThingSmartCryption.a").write_bytes(b"EXTERNAL-PRIVATE-SDK")

    runtime = root / "TuyaRuntime"
    sources = runtime / "Sources/NembraTuyaPrivateConfig"
    sources.mkdir(parents=True)
    (runtime / "NembraTuyaPrivateConfig.podspec").write_text("Pod::Spec.new\n", encoding="utf-8")
    (sources / "Identity.swift").write_text(
        'let secret = "EXTERNAL-PRIVATE-IDENTITY"\n', encoding="utf-8"
    )
    (runtime / "ResolvedTuyaDependencyProvenance.txt").write_text(
        "schema=1\nexternal-private-hashes-only\n", encoding="utf-8"
    )


class GeneratedPrivateAncestorSymlinkRedTeam(unittest.TestCase):
    def test_unadmitted_localsecrets_ancestor_can_escape_repository(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-generated-ancestor-red-") as raw:
            sandbox = Path(raw)
            repo = sandbox / "repo"
            repo.mkdir()
            source_sha = seed_tracked_repo(repo)
            seed_public_generated(repo)

            external_private = sandbox / "external-private"
            seed_external_private(external_private)
            os.symlink("../external-private", repo / "LocalSecrets")

            self.assertTrue((repo / "LocalSecrets").is_symlink())
            self.assertFalse(external_private.resolve().is_relative_to(repo.resolve()))

            accepted = snapshot.generated_manifest_sha256(repo, source_sha)
            stage = sandbox / "stage"
            actual = snapshot.stage_accepted_build_inputs(repo, source_sha, stage, accepted)

            # Exploit-positive contract: current production admits the external bytes
            # and publishes them under canonical in-repository logical names.
            self.assertEqual(actual, accepted)
            self.assertEqual(
                (stage / "LocalSecrets/TuyaSDK/Build/libThingSmartCryption.a").read_bytes(),
                b"EXTERNAL-PRIVATE-SDK",
            )
            self.assertEqual(
                (stage / "LocalSecrets/TuyaRuntime/Sources/NembraTuyaPrivateConfig/Identity.swift").read_text(encoding="utf-8"),
                'let secret = "EXTERNAL-PRIVATE-IDENTITY"\n',
            )
            self.assertFalse((stage / "LocalSecrets").is_symlink())

            manifest = snapshot.canonical_generated_manifest(repo, source_sha)
            self.assertNotIn(b"symlink\tLocalSecrets\t", manifest)


if __name__ == "__main__":
    unittest.main(verbosity=2)
