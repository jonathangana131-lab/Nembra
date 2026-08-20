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
        self.assertIsNone(baseline.semantics)
        library.acl_get_fd.assert_called_once_with(74)
        library.acl_init.assert_called_once_with(0)
        library.acl_free.assert_not_called()

    def test_native_seeded_fd_baseline_retains_canonical_semantics(self) -> None:
        helper = load()
        library = mock.Mock()
        library.acl_get_fd.return_value = 0xA001
        library.acl_dup.return_value = 0xA002
        library.acl_free.return_value = 0

        with (
            mock.patch.object(helper, "_darwin_acl_library", return_value=library),
            mock.patch.object(
                helper, "_native_acl_text", return_value=b"user:root allow readattr\n"
            ) as canonicalize,
        ):
            baseline = helper._capture_fd_acl_baseline(75)

        self.assertEqual(baseline, 0xA002)
        self.assertEqual(baseline.semantics, b"user:root allow readattr\n")
        library.acl_get_fd.assert_called_once_with(75)
        library.acl_dup.assert_called_once_with(0xA001)
        canonicalize.assert_called_once_with(library, 0xA002, "descriptor baseline")
        library.acl_free.assert_called_once_with(0xA001)

    def test_native_baseline_coherence_accepts_equal_seeded_views(self) -> None:
        helper = load()
        library = mock.Mock()
        library.acl_get_file.return_value = 0xB001
        library.acl_free.return_value = 0
        baseline = helper._NativeACLBaseline(0xB002, b"seeded-acl")

        with (
            mock.patch.object(helper, "_darwin_acl_library", return_value=library),
            mock.patch.object(
                helper, "_native_acl_text", return_value=b"seeded-acl"
            ),
            mock.patch.object(helper, "_require_canonical_acl_identity") as identity,
        ):
            helper._require_native_acl_baseline_coherence(
                Path("/private/tmp/accepted"), 81, (1, 2, 3), True, baseline
            )

        self.assertEqual(identity.call_count, 2)
        library.acl_get_file.assert_called_once_with(
            os.fsencode(Path("/private/tmp/accepted")), helper._DARWIN_ACL_TYPE_EXTENDED
        )
        library.acl_free.assert_called_once_with(0xB001)

    def test_native_baseline_coherence_rejects_semantic_mismatch_before_grant(self) -> None:
        helper = load()
        library = mock.Mock()
        library.acl_get_file.return_value = 0xC001
        library.acl_free.return_value = 0
        baseline = helper._NativeACLBaseline(0xC002, b"fd-acl")

        with (
            mock.patch.object(helper, "_darwin_acl_library", return_value=library),
            mock.patch.object(helper, "_native_acl_text", return_value=b"path-acl"),
            mock.patch.object(helper, "_require_canonical_acl_identity"),
            self.assertRaisesRegex(
                helper.SelectedXcodeBuildOrchestratorError,
                "baseline semantics diverge",
            ),
        ):
            helper._require_native_acl_baseline_coherence(
                Path("/private/tmp/accepted"), 82, (1, 2, 3), True, baseline
            )

        library.acl_free.assert_called_once_with(0xC001)

    def test_native_baseline_coherence_accepts_enoent_only_when_both_absent(self) -> None:
        helper = load()
        library = mock.Mock()

        def absent_path(_path, _acl_type):
            helper.ctypes.set_errno(helper.errno.ENOENT)
            return None

        library.acl_get_file.side_effect = absent_path
        baseline = helper._NativeACLBaseline(0xD001, None)
        with (
            mock.patch.object(helper, "_darwin_acl_library", return_value=library),
            mock.patch.object(helper, "_require_canonical_acl_identity") as identity,
        ):
            helper._require_native_acl_baseline_coherence(
                Path("/private/tmp/accepted"), 83, (1, 2, 3), True, baseline
            )
        self.assertEqual(identity.call_count, 2)

    def test_native_baseline_coherence_rejects_mixed_absent_present_classes(self) -> None:
        helper = load()
        library = mock.Mock()

        def absent_path(_path, _acl_type):
            helper.ctypes.set_errno(helper.errno.ENOENT)
            return None

        library.acl_get_file.side_effect = absent_path
        baseline = helper._NativeACLBaseline(0xD002, b"fd-present")
        with (
            mock.patch.object(helper, "_darwin_acl_library", return_value=library),
            mock.patch.object(helper, "_require_canonical_acl_identity"),
            self.assertRaisesRegex(
                helper.SelectedXcodeBuildOrchestratorError,
                "baseline classes diverge",
            ),
        ):
            helper._require_native_acl_baseline_coherence(
                Path("/private/tmp/accepted"), 84, (1, 2, 3), True, baseline
            )

    def test_native_baseline_coherence_rejects_null_path_acl_without_enoent(self) -> None:
        helper = load()
        library = mock.Mock()
        library.acl_get_file.return_value = None
        baseline = helper._NativeACLBaseline(0xD003, None)
        with (
            mock.patch.object(helper, "_darwin_acl_library", return_value=library),
            mock.patch.object(helper, "_require_canonical_acl_identity"),
            self.assertRaisesRegex(
                helper.SelectedXcodeBuildOrchestratorError,
                "could not classify canonical-path private read-lease ACL baseline: errno 0",
            ),
        ):
            helper._require_native_acl_baseline_coherence(
                Path("/private/tmp/accepted"), 85, (1, 2, 3), True, baseline
            )

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
                    helper, "_require_native_acl_baseline_coherence"
                ) as coherence,
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
            coherence.assert_called_once_with(subject, descriptor, signature, False, 4242)
            grant.assert_called_once()
            restore.assert_called_once_with(descriptor, 4242)
            free.assert_called_once_with(4242)
            legacy_chmod.assert_not_called()
            self.assertEqual(events, [("restore", 4242), ("free", 4242)])
            self.assertEqual(lease._opened, [])
            self.assertEqual(lease._principal, "")


if __name__ == "__main__":
    unittest.main(verbosity=2)
