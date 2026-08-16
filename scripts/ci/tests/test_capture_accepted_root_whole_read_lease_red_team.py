#!/usr/bin/env python3
"""Exploit-positive classifier for strict accepted-root compiler read authority.

The stale strict compiler-root integration seals the whole accepted input tree as
root-owned/owner-only, then leases only the SDK/runtime private subtrees to the
fresh non-root compiler identity. This witness proves required lock/workspace/
Pods inputs remain outside that lease plan.
"""
from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import stat
import tempfile
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
SNAPSHOT = REPOSITORY / "scripts/ci/capture_accepted_build_input_snapshot.py"
ORCHESTRATOR = REPOSITORY / "scripts/ci/capture_selected_xcode_build_orchestrator.py"


def load(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"could not load {path.name}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def seed_generated_inputs(root: Path) -> None:
    (root / "NembraCapture.xcworkspace").mkdir(parents=True)
    (root / "NembraCapture.xcworkspace/contents.xcworkspacedata").write_text(
        "<Workspace/>\n", encoding="utf-8"
    )
    (root / "Pods").mkdir()
    (root / "Pods/SyntheticPod.swift").write_text("// pod\n", encoding="utf-8")
    (root / "LocalSecrets/TuyaSDK").mkdir(parents=True)
    (root / "LocalSecrets/TuyaSDK/sdk.bin").write_bytes(b"SDK\n")
    (root / "LocalSecrets/TuyaRuntime").mkdir(parents=True)
    (root / "LocalSecrets/TuyaRuntime/runtime.bin").write_bytes(b"RUNTIME\n")
    (root / "Podfile.lock").write_text("PODS:\n  - Synthetic\n", encoding="utf-8")


class CaptureAcceptedRootWholeReadLeaseRedTeamTests(unittest.TestCase):
    def test_strict_two_subtree_lease_omits_owner_only_required_generated_inputs(self) -> None:
        snapshot = load(SNAPSHOT, "nembra_snapshot_whole_read_lease_red_team")
        orchestrator = load(ORCHESTRATOR, "nembra_orchestrator_whole_read_lease_red_team")

        # Keep fixtures beneath the checkout so Darwin does not encounter the
        # unrelated /var -> /private/var compatibility symlink in host ancestry.
        with tempfile.TemporaryDirectory(
            prefix="nembra-accepted-root-whole-read-lease-", dir=REPOSITORY
        ) as raw:
            outer = Path(raw)
            live = outer / "live"
            accepted = outer / "accepted"
            live.mkdir()
            accepted.mkdir()
            seed_generated_inputs(live)

            snapshot._copy_generated_subjects(live, accepted)

            required = {
                accepted / "Podfile.lock": 0o600,
                accepted / "NembraCapture.xcworkspace": 0o700,
                accepted / "NembraCapture.xcworkspace/contents.xcworkspacedata": 0o600,
                accepted / "Pods": 0o700,
                accepted / "Pods/SyntheticPod.swift": 0o600,
            }
            for path, mode in required.items():
                self.assertTrue(path.exists(), path)
                self.assertEqual(stat.S_IMODE(path.lstat().st_mode), mode, path)

            sdk = accepted / orchestrator.CANONICAL_SDK_RELATIVE
            runtime = accepted / orchestrator.CANONICAL_RUNTIME_RELATIVE
            lease = orchestrator._lease_paths((sdk, runtime), accepted)
            planned = {path for path, _host_only in lease}

            # The root itself receives directory traversal/list authority and the
            # two private trees are recursively planned. That does not confer
            # read/traversal authority on their owner-only generated siblings.
            self.assertIn(accepted, planned)
            self.assertIn(sdk, planned)
            self.assertIn(sdk / "sdk.bin", planned)
            self.assertIn(runtime, planned)
            self.assertIn(runtime / "runtime.bin", planned)
            for path in required:
                self.assertNotIn(path, planned, path)

    def test_root_directory_ace_is_nonrecursive_and_not_file_read_authority(self) -> None:
        orchestrator = load(ORCHESTRATOR, "nembra_orchestrator_root_acl_red_team")
        root_ace = orchestrator._acl_text("nembrabuildfixture", True, False)
        self.assertIn("list,search", root_ace)
        self.assertNotIn("file_inherit", root_ace)
        self.assertNotIn("directory_inherit", root_ace)

        file_ace = orchestrator._acl_text("nembrabuildfixture", False, False)
        self.assertIn("read,readattr", file_ace)
        self.assertNotEqual(root_ace, file_ace)

    def test_strict_source_shape_leases_only_sdk_and_runtime(self) -> None:
        source = ORCHESTRATOR.read_text(encoding="utf-8")
        strict = source[source.index("if accepted_generated_manifest_sha256 is not None:") :]
        self.assertIn(
            "accepted_root / CANONICAL_SDK_RELATIVE,\n"
            "                accepted_root / CANONICAL_RUNTIME_RELATIVE,",
            strict,
        )
        self.assertIn("lease_repo = accepted_root", strict)
        self.assertIn("build_cwd = accepted_root", strict)
        self.assertNotIn("private_subjects = (accepted_root,)", strict)


if __name__ == "__main__":
    unittest.main(verbosity=2)
