#!/usr/bin/env python3
"""Portable policy regression for host-ancestor private read-lease authority."""

from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import tempfile
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
ORCHESTRATOR = REPOSITORY / "scripts/ci/capture_selected_xcode_build_orchestrator.py"


def load():
    spec = importlib.util.spec_from_file_location(
        "nembra_private_read_lease_host_ancestry", ORCHESTRATOR
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load selected-Xcode build orchestrator")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class CapturePrivateReadLeaseHostAncestryTests(unittest.TestCase):
    def test_only_non_world_searchable_host_ancestors_receive_traversal_lease(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-lease-host-") as temporary:
            outer = Path(temporary)
            outer.chmod(0o711)
            world_searchable = outer / "world-searchable"
            world_searchable.mkdir(mode=0o711)
            private_host = world_searchable / "private-host"
            private_host.mkdir(mode=0o700)
            repo = private_host / "repo"
            repo.mkdir(mode=0o755)
            subject = repo / "LocalSecrets/TuyaSDK/Build"
            subject.mkdir(parents=True)
            (subject / "payload.bin").write_bytes(b"fixture\n")

            lease_paths = dict(helper._lease_paths((subject,), repo))

            self.assertIs(lease_paths.get(private_host), True)
            self.assertNotIn(world_searchable, lease_paths)
            self.assertNotIn(outer, lease_paths)
            self.assertIs(lease_paths.get(repo), False)
            self.assertIs(lease_paths.get(repo / "LocalSecrets"), False)
            self.assertIs(lease_paths.get(repo / "LocalSecrets/TuyaSDK"), False)
            self.assertIs(lease_paths.get(subject), False)
            self.assertIs(lease_paths.get(subject / "payload.bin"), False)

    def test_host_ancestor_must_be_a_real_directory(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-lease-host-symlink-") as temporary:
            outer = Path(temporary)
            outer.chmod(0o711)
            real_parent = outer / "real-parent"
            real_parent.mkdir(mode=0o700)
            linked_parent = outer / "linked-parent"
            linked_parent.symlink_to(real_parent, target_is_directory=True)
            repo = linked_parent / "repo"
            repo.mkdir(mode=0o755)
            subject = repo / "LocalSecrets/TuyaSDK/Build"
            subject.mkdir(parents=True)

            with self.assertRaises(helper.SelectedXcodeBuildOrchestratorError):
                helper._lease_paths((subject,), repo)

    def test_traversal_acl_never_grants_list_or_read(self) -> None:
        helper = load()
        acl = helper._acl_text("nembrabuildfixture", True, True)
        self.assertIn("search", acl)
        self.assertNotIn("list", acl)
        self.assertNotIn("readextattr", acl)
        self.assertNotIn(" write", acl)


if __name__ == "__main__":
    unittest.main(verbosity=2)
