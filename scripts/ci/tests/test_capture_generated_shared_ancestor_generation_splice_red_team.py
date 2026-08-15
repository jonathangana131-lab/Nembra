#!/usr/bin/env python3
"""Exploit-positive witness for mixed-generation LocalSecrets subject admission."""

from __future__ import annotations

import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

REPOSITORY = Path(__file__).resolve().parents[3]
SNAPSHOT_HELPER = REPOSITORY / "scripts/ci/capture_accepted_build_input_snapshot.py"
SOURCE_SHA = "a" * 40


def load_helper():
    spec = importlib.util.spec_from_file_location(
        "nembra_generated_shared_ancestor_generation_splice_red_team", SNAPSHOT_HELPER
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load accepted build-input snapshot helper")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def digest(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


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
    for entry in payload["entries"]:  # type: ignore[index]
        if entry.get("path") == path:
            return str(entry["sha256"])
    raise AssertionError(f"manifest entry missing: {path}")


class CaptureGeneratedSharedAncestorGenerationSpliceRedTeamTests(unittest.TestCase):
    def test_manifest_can_splice_sdk_and_runtime_from_distinct_localsecrets_generations(self) -> None:
        helper = load_helper()
        with tempfile.TemporaryDirectory(prefix="nembra-generated-generation-splice-") as raw:
            root = Path(raw)
            seed_common(root)
            generation_a = make_generation(root, "LocalSecrets.A", b"SDK-A\n", b"RUNTIME-A\n")
            generation_b = make_generation(root, "LocalSecrets.B", b"SDK-B\n", b"RUNTIME-B\n")

            generation_a.rename(root / "LocalSecrets")
            pure_a = helper.canonical_generated_manifest(root, SOURCE_SHA)
            (root / "LocalSecrets").rename(root / "LocalSecrets.A")
            generation_b.rename(root / "LocalSecrets")
            pure_b = helper.canonical_generated_manifest(root, SOURCE_SHA)
            (root / "LocalSecrets").rename(root / "LocalSecrets.B")
            (root / "LocalSecrets.A").rename(root / "LocalSecrets")

            original_open_subject = helper._open_subject
            swapped = False

            def swap_before_runtime(root_fd: int, subject: Path):
                nonlocal swapped
                if subject == Path("LocalSecrets/TuyaRuntime") and not swapped:
                    (root / "LocalSecrets").rename(root / "LocalSecrets.A.attack")
                    (root / "LocalSecrets.B").rename(root / "LocalSecrets")
                    swapped = True
                return original_open_subject(root_fd, subject)

            with mock.patch.object(helper, "_open_subject", side_effect=swap_before_runtime):
                mixed = helper.canonical_generated_manifest(root, SOURCE_SHA)

            self.assertTrue(swapped)
            self.assertNotEqual(digest(mixed), digest(pure_a))
            self.assertNotEqual(digest(mixed), digest(pure_b))

            mixed_payload = json.loads(mixed)
            a_payload = json.loads(pure_a)
            b_payload = json.loads(pure_b)
            sdk_path = "LocalSecrets/TuyaSDK/sdk.bin"
            runtime_path = "LocalSecrets/TuyaRuntime/identity.bin"

            self.assertEqual(entry_sha(mixed_payload, sdk_path), entry_sha(a_payload, sdk_path))
            self.assertNotEqual(entry_sha(mixed_payload, sdk_path), entry_sha(b_payload, sdk_path))
            self.assertEqual(entry_sha(mixed_payload, runtime_path), entry_sha(b_payload, runtime_path))
            self.assertNotEqual(entry_sha(mixed_payload, runtime_path), entry_sha(a_payload, runtime_path))

            # The production helper therefore minted a canonical digest for a private
            # subject set that never existed beneath one LocalSecrets generation.
            self.assertEqual(entry_sha(mixed_payload, sdk_path), hashlib.sha256(b"SDK-A\n").hexdigest())
            self.assertEqual(
                entry_sha(mixed_payload, runtime_path), hashlib.sha256(b"RUNTIME-B\n").hexdigest()
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)
