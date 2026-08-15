#!/usr/bin/env python3
"""Exploit-positive oracle for generated symlink/.. semantic escape."""
from __future__ import annotations

import hashlib
import importlib.util
from pathlib import Path
import tempfile
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
HELPER = REPOSITORY / "scripts/ci/capture_accepted_build_input_snapshot.py"
SOURCE_SHA = "a" * 40


def load():
    spec = importlib.util.spec_from_file_location("nembra_generated_symlink_dotdot", HELPER)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load accepted build-input helper")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def seed_generated(root: Path) -> None:
    (root / "Podfile.lock").write_text("PODS:\n  - Synthetic\n", encoding="utf-8")
    workspace = root / "NembraCapture.xcworkspace"
    workspace.mkdir()
    (workspace / "contents.xcworkspacedata").write_text("<Workspace/>\n", encoding="utf-8")
    pods = root / "Pods"
    pods.mkdir()
    (pods / "SyntheticPod.swift").write_text("// pod\n", encoding="utf-8")
    (pods / "anchor").symlink_to(".", target_is_directory=True)
    # Lexically this appears to collapse back to <root>/outside.fixture.
    # POSIX resolution follows anchor -> Pods first, then applies both '..',
    # reaching the parent of the admitted root.
    (pods / "escape").symlink_to("anchor/../../outside.fixture")
    sdk = root / "LocalSecrets/TuyaSDK"
    runtime = root / "LocalSecrets/TuyaRuntime"
    sdk.mkdir(parents=True)
    runtime.mkdir(parents=True)
    (sdk / "sdk.bin").write_bytes(b"sdk\n")
    (runtime / "runtime.bin").write_bytes(b"runtime\n")


class CaptureGeneratedSymlinkDotDotEscapeRedTeamTests(unittest.TestCase):
    def test_preaccepted_manifest_and_copy_can_preserve_semantically_escaping_symlink(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(
            prefix="nembra-generated-symlink-dotdot-",
            dir=REPOSITORY,
        ) as raw:
            outer = Path(raw).resolve(strict=True)
            source = outer / "source"
            stage = outer / "stage"
            source.mkdir()
            stage.mkdir()
            outside = outer / "outside.fixture"
            outside.write_bytes(b"outside\n")
            seed_generated(source)

            source_escape = source / "Pods/escape"
            self.assertEqual(source_escape.resolve(strict=True), outside)
            self.assertNotEqual(outside.parent, source)

            manifest = helper.canonical_generated_manifest(source, SOURCE_SHA)
            accepted_digest = hashlib.sha256(manifest).hexdigest()

            helper._copy_generated_subjects(source, stage)
            copied_digest = helper.generated_manifest_sha256(stage, SOURCE_SHA)
            self.assertEqual(copied_digest, accepted_digest)

            copied_escape = stage / "Pods/escape"
            self.assertEqual(copied_escape.readlink().as_posix(), "anchor/../../outside.fixture")
            self.assertEqual(copied_escape.resolve(strict=True), outside)
            self.assertNotEqual(copied_escape.resolve(strict=True).parent, stage)


if __name__ == "__main__":
    unittest.main(verbosity=2)
