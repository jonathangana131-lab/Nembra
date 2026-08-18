#!/usr/bin/env python3
"""Portable rollback regressions for partial private read-lease admission."""

from __future__ import annotations

import importlib.util
import os
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
        outer = Path(temporary).resolve(strict=True)
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

    def test_native_null_acl_without_enoent_fails_closed_before_empty_baseline(self) -> None:
        helper = load()
        library = mock.Mock()
        library.acl_get_fd.return_value = None
        library.acl_init.return_value = 0xC0FFEE
        library.acl_free.return_value = 0

        with (
            mock.patch.object(helper, "_darwin_acl_library", return_value=library),
            self.assertRaisesRegex(
                helper.SelectedXcodeBuildOrchestratorError,
                "could not classify descriptor-pinned private read-lease ACL baseline: errno 0",
            ),
        ):
            helper._capture_fd_acl_baseline(73)

        library.acl_get_fd.assert_called_once_with(73)
        library.acl_init.assert_not_called()
        library.acl_free.assert_not_called()

    def test_native_enoent_acl_acquisition_mints_empty_baseline(self) -> None:
        helper = load()
        library = mock.Mock()

        def absent_acl(descriptor: int):
            self.assertEqual(descriptor, 74)
            helper.ctypes.set_errno(helper.errno.ENOENT)
            return None

        library.acl_get_fd.side_effect = absent_acl
        library.acl_init.return_value = 0xC0FFEE
        library.acl_free.return_value = 0

        with mock.patch.object(helper, "_darwin_acl_library", return_value=library):
            baseline = helper._capture_fd_acl_baseline(74)

        self.assertEqual(baseline, 0xC0FFEE)
        library.acl_get_fd.assert_called_once_with(74)
        library.acl_init.assert_called_once_with(0)
        library.acl_free.assert_not_called()

    def test_native_strict_revoke_restores_held_object_after_path_replacement(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-lease-native-revoke-") as temporary:
            repo, subject = self._subject(temporary)
            descriptor = os.open(subject, os.O_RDONLY)
            signature = helper._descriptor_signature(descriptor)
            lease = helper._PrivateReadLease(
                (subject,), repo, use_native_darwin_acl=True
            )
            events: list[tuple[str, int]] = []
            listings = iter((
                "",
                " 0: user:nembrabuildnative allow read,readattr,readextattr,readsecurity\n",
            ))

            with (
                mock.patch.object(
                    helper,
                    "_lease_paths",
                    return_value=((subject, False, signature, descriptor),),
                ),
                mock.patch.object(helper, "_validate_lease_subject_symlinks"),
                mock.patch.object(
                    helper, "_capture_fd_acl_baseline", return_value=4242
                ) as capture,
                mock.patch.object(
                    helper, "_path_acl_listing", side_effect=lambda *_args: next(listings)
                ),
                mock.patch.object(helper, "_chmod_acl_path") as grant,
                mock.patch.object(
                    helper,
                    "_restore_fd_acl_baseline",
                    side_effect=lambda fd, baseline: events.append(("restore", baseline)),
                ) as restore,
                mock.patch.object(
                    helper,
                    "_free_fd_acl_baseline",
                    side_effect=lambda baseline: events.append(("free", baseline)),
                ) as free,
                mock.patch.object(helper, "_chmod_acl") as legacy_chmod,
            ):
                lease.grant("nembrabuildnative")
                moved = repo / "private.fixture.moved"
                subject.rename(moved)
                subject.write_bytes(b"attacker replacement\n")
                with self.assertRaisesRegex(
                    helper.SelectedXcodeBuildOrchestratorError,
                    "pathname no longer identifies opened object",
                ):
                    lease.revoke()
                self.assertEqual(subject.read_bytes(), b"attacker replacement\n")
                self.assertEqual(moved.read_bytes(), b"fixture\n")

            capture.assert_called_once_with(descriptor)
            grant.assert_called_once()
            restore.assert_called_once_with(descriptor, 4242)
            free.assert_called_once_with(4242)
            legacy_chmod.assert_not_called()
            self.assertEqual(events, [("restore", 4242), ("free", 4242)])
            self.assertEqual(lease._opened, [])
            self.assertEqual(lease._principal, "")


if __name__ == "__main__":
    unittest.main(verbosity=2)
