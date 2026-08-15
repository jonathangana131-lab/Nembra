#!/usr/bin/env python3
"""Portable rollback regressions for partial private read-lease admission."""

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
    def _subject(self, temporary: str) -> tuple[Path, Path]:
        outer = Path(temporary)
        outer.chmod(0o711)
        repo = outer / "repo"
        repo.mkdir(mode=0o755)
        subject = repo / "private.fixture"
        subject.write_bytes(b"fixture\n")
        return repo, subject

    def test_failed_post_grant_verification_revokes_the_exact_acl(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-lease-rollback-") as temporary:
            repo, subject = self._subject(temporary)
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

    def test_chmod_failure_after_observable_mutation_still_revokes_the_exact_acl(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-lease-chmod-failure-") as temporary:
            repo, subject = self._subject(temporary)
            lease = helper._PrivateReadLease((subject,), repo)
            mutations: list[tuple[str, str]] = []
            listings = iter(("before", "after-plus-a", "before"))

            def fake_listing(_descriptor: int) -> str:
                return next(listings)

            def fake_chmod(_descriptor: int, operation: str, acl: str) -> None:
                mutations.append((operation, acl))
                if operation == "+a":
                    raise helper.SelectedXcodeBuildOrchestratorError(
                        "simulated chmod failure after kernel mutation"
                    )

            with (
                mock.patch.object(helper, "_acl_listing", side_effect=fake_listing),
                mock.patch.object(helper, "_chmod_acl", side_effect=fake_chmod),
                self.assertRaises(helper.SelectedXcodeBuildOrchestratorError),
            ):
                lease.grant("nembrabuildrollback")

            self.assertEqual([operation for operation, _acl in mutations], ["+a", "-a"])
            self.assertEqual(mutations[0][1], mutations[1][1])
            self.assertEqual(lease._opened, [])
            self.assertEqual(lease._principal, "")

    def test_grant_surfaces_rollback_failure_instead_of_silently_forgetting_it(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-lease-rollback-failure-") as temporary:
            repo, subject = self._subject(temporary)
            lease = helper._PrivateReadLease((subject,), repo)
            listings = iter(("before", "after-plus-a"))

            def fake_listing(_descriptor: int) -> str:
                return next(listings)

            def fake_chmod(_descriptor: int, operation: str, _acl: str) -> None:
                if operation == "+a":
                    raise helper.SelectedXcodeBuildOrchestratorError(
                        "simulated grant command failure"
                    )
                raise helper.SelectedXcodeBuildOrchestratorError(
                    "simulated rollback command failure"
                )

            with (
                mock.patch.object(helper, "_acl_listing", side_effect=fake_listing),
                mock.patch.object(helper, "_chmod_acl", side_effect=fake_chmod),
                self.assertRaisesRegex(
                    helper.SelectedXcodeBuildOrchestratorError,
                    "rollback",
                ),
            ):
                lease.grant("nembrabuildrollback")


if __name__ == "__main__":
    unittest.main(verbosity=2)
