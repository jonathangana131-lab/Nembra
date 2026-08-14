#!/usr/bin/env python3
"""Portable rollback regression for partial private read-lease admission."""

from __future__ import annotations

import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest import mock

REPOSITORY = Path(__file__).resolve().parents[3]
ORCHESTRATOR = REPOSITORY / "scripts/ci/capture_selected_xcode_build_orchestrator.py"


def load():
    spec = importlib.util.spec_from_file_location(
        "nembra_private_read_lease_rollback", ORCHESTRATOR
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load selected-Xcode build orchestrator")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class CapturePrivateReadLeaseRollbackTests(unittest.TestCase):
    def test_failed_post_grant_verification_revokes_the_exact_acl(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-lease-rollback-") as temporary:
            outer = Path(temporary)
            outer.chmod(0o711)
            repo = outer / "repo"
            repo.mkdir(mode=0o755)
            subject = repo / "private.fixture"
            subject.write_bytes(b"fixture\n")

            lease = helper._PrivateReadLease((subject,), repo)
            mutations: list[tuple[str, str]] = []
            listings = iter(("", "", ""))

            def fake_listing(_descriptor: int) -> str:
                return next(listings)

            def fake_chmod(_descriptor: int, operation: str, acl: str) -> None:
                mutations.append((operation, acl))

            with (
                mock.patch.object(helper, "_acl_listing", side_effect=fake_listing),
                mock.patch.object(helper, "_chmod_acl", side_effect=fake_chmod),
                self.assertRaises(helper.SelectedXcodeBuildOrchestratorError),
            ):
                lease.grant("nembrabuildrollback")

            self.assertEqual(len(mutations), 2)
            self.assertEqual(mutations[0][0], "+a")
            self.assertEqual(mutations[1][0], "-a")
            self.assertEqual(mutations[0][1], mutations[1][1])
            self.assertEqual(lease._opened, [])
            self.assertEqual(lease._principal, "")


if __name__ == "__main__":
    unittest.main(verbosity=2)
