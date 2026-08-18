#!/usr/bin/env python3
"""Permanent regressions for held-symlink policy at ACL authority transitions."""
from __future__ import annotations

import importlib.util
import inspect
from pathlib import Path
import tempfile
import unittest
from unittest import mock

REPO = Path(__file__).resolve().parents[3]
HELPER = REPO / "scripts/ci/capture_selected_xcode_build_orchestrator.py"


def load():
    spec = importlib.util.spec_from_file_location("nembra_symlink_authority_transition", HELPER)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load selected-Xcode orchestrator")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def fixture():
    return tempfile.TemporaryDirectory(
        prefix="nembra-symlink-authority-transition-",
        dir=REPO,
    )


class CapturePrivateReadLeaseSymlinkAuthorityTransitionTests(unittest.TestCase):
    def _make_tree(self, raw: str):
        outer = Path(raw)
        repo = outer / "repo"
        subject = repo / "LocalSecrets/TuyaSDK/Build"
        inside = subject / "inside"
        inside.mkdir(parents=True)
        (inside / "inside.fixture").write_text("inside\n", encoding="utf-8")
        external = outer / "outside-subject"
        external.mkdir()
        (external / "outside.fixture").write_text("outside\n", encoding="utf-8")
        link = subject / "escape"
        link.symlink_to("inside", target_is_directory=True)
        return repo, subject, external, link

    @staticmethod
    def _acl_transport():
        state: dict[int, str] = {}

        def listing(descriptor: int) -> str:
            return state.get(descriptor, "")

        def chmod(descriptor: int, operation: str, acl: str) -> None:
            if operation == "+a":
                state[descriptor] = f"0: {acl}"
            elif operation == "-a":
                state[descriptor] = ""
            else:
                raise AssertionError(f"unexpected ACL operation: {operation}")

        return state, listing, chmod

    def test_retarget_after_planner_validation_is_rejected_before_acl(self) -> None:
        helper = load()
        with fixture() as raw:
            repo, subject, external, link = self._make_tree(raw)
            original = helper._validate_subject_symlinks_from_descriptor
            calls = 0

            def validate_then_retarget(admitted_subject: Path, descriptor: int) -> None:
                nonlocal calls
                calls += 1
                original(admitted_subject, descriptor)
                if calls == 1:
                    link.unlink()
                    link.symlink_to(external, target_is_directory=True)

            state, listing, chmod = self._acl_transport()
            lease = helper._PrivateReadLease((subject,), repo)
            with (
                mock.patch.object(
                    helper,
                    "_validate_subject_symlinks_from_descriptor",
                    side_effect=validate_then_retarget,
                ),
                mock.patch.object(helper, "_acl_listing", side_effect=listing),
                mock.patch.object(helper, "_chmod_acl", side_effect=chmod),
            ):
                with self.assertRaises(helper.SelectedXcodeBuildOrchestratorError):
                    lease.grant("nembrasymlinkfence")

            self.assertGreaterEqual(calls, 2)
            self.assertFalse(any(state.values()), "no ACL may survive rejected authority admission")
            self.assertFalse(lease._opened)
            self.assertEqual(lease._principal, "")
            self.assertEqual(link.resolve(strict=True), external.resolve(strict=True))

    def test_retarget_during_acl_application_fails_closed_and_rolls_back(self) -> None:
        helper = load()
        with fixture() as raw:
            repo, subject, external, link = self._make_tree(raw)
            state, listing, base_chmod = self._acl_transport()
            retargeted = False

            def chmod_then_retarget(descriptor: int, operation: str, acl: str) -> None:
                nonlocal retargeted
                base_chmod(descriptor, operation, acl)
                if operation == "+a" and not retargeted:
                    link.unlink()
                    link.symlink_to(external, target_is_directory=True)
                    retargeted = True

            lease = helper._PrivateReadLease((subject,), repo)
            with (
                mock.patch.object(helper, "_acl_listing", side_effect=listing),
                mock.patch.object(helper, "_chmod_acl", side_effect=chmod_then_retarget),
            ):
                with self.assertRaises(helper.SelectedXcodeBuildOrchestratorError):
                    lease.grant("nembrasymlinkfence")

            self.assertTrue(retargeted)
            self.assertTrue(state, "the fixture must reach ACL materialization")
            self.assertFalse(any(state.values()), "exact rollback must remove every synthetic ACL")
            self.assertFalse(lease._opened)
            self.assertEqual(lease._principal, "")
            self.assertEqual(link.resolve(strict=True), external.resolve(strict=True))

    def test_retarget_inside_readlink_is_rejected_by_directory_generation(self) -> None:
        helper = load()
        with fixture() as raw:
            repo, subject, external, link = self._make_tree(raw)
            original_readlink = helper.os.readlink
            retargets = 0

            def safe_readlink_then_external(path, *, dir_fd=None):
                nonlocal retargets
                # Simulate a concurrent field mutation that presents the safe target
                # only for the descriptor-relative readlink, then restores the
                # external target before the validator can return.
                if link.is_symlink():
                    link.unlink()
                link.symlink_to("inside", target_is_directory=True)
                value = original_readlink(path, dir_fd=dir_fd)
                link.unlink()
                link.symlink_to(external, target_is_directory=True)
                retargets += 1
                return value

            state, listing, chmod = self._acl_transport()
            lease = helper._PrivateReadLease((subject,), repo)
            with mock.patch.object(
                helper.os,
                "readlink",
                side_effect=safe_readlink_then_external,
            ) as injected_readlink:
                advertised_dir_fd_support = set(helper.os.supports_dir_fd)
                advertised_dir_fd_support.add(injected_readlink)
                with (
                    mock.patch.object(
                        helper.os,
                        "supports_dir_fd",
                        advertised_dir_fd_support,
                    ),
                    mock.patch.object(helper, "_acl_listing", side_effect=listing),
                    mock.patch.object(helper, "_chmod_acl", side_effect=chmod),
                ):
                    with self.assertRaises(helper.SelectedXcodeBuildOrchestratorError) as raised:
                        lease.grant("nembrasymlinkgeneration")

            self.assertIn(
                "held directory generation changed during symlink validation",
                str(raised.exception),
            )
            self.assertGreaterEqual(retargets, 1)
            self.assertFalse(any(state.values()))
            self.assertFalse(lease._opened)
            self.assertEqual(lease._principal, "")

    def test_grant_source_revalidates_symlinks_before_and_after_acl_loop(self) -> None:
        helper = load()
        grant = inspect.getsource(helper._PrivateReadLease.grant)
        validator = inspect.getsource(helper._validate_subject_symlinks_from_descriptor)
        self.assertIn("st_mtime_ns", validator)
        self.assertIn("st_ctime_ns", validator)
        self.assertIn("after_generation != before_generation", validator)
        marker = "_validate_lease_subject_symlinks(self._subjects, pinned_plan)"
        self.assertEqual(grant.count(marker), 2)
        first = grant.index(marker)
        loop = grant.index("for record, (path, host_only, accepted_signature, descriptor) in zip")
        second = grant.rindex(marker)
        rollback = grant.index("except Exception as error:")
        self.assertLess(first, loop)
        self.assertLess(loop, second)
        self.assertLess(second, rollback)


if __name__ == "__main__":
    unittest.main(verbosity=2)
