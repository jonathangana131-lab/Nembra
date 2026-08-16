#!/usr/bin/env python3
"""Regression for held-subject symlink retargeting across lease ACL admission."""
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
    spec = importlib.util.spec_from_file_location(
        "nembra_post_validation_symlink_retarget_regression",
        HELPER,
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load selected-Xcode orchestrator")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class CapturePrivateReadLeasePostValidationSymlinkRetargetRegressionTests(unittest.TestCase):
    def test_grant_rejects_symlink_retargeted_after_descriptor_bound_validation(self) -> None:
        helper = load()
        # Keep the synthetic repository under the checkout so Darwin does not reject
        # the unrelated /var -> /private/var temporary-root compatibility symlink.
        with tempfile.TemporaryDirectory(
            prefix="nembra-post-validate-symlink-retarget-regression-",
            dir=REPO,
        ) as raw:
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

            original_validator = helper._validate_subject_symlinks_from_descriptor
            validation_count = 0
            retargeted = False

            def validate_safe_then_retarget(
                admitted_subject: Path,
                subject_descriptor: int,
            ) -> None:
                nonlocal validation_count, retargeted
                validation_count += 1
                original_validator(admitted_subject, subject_descriptor)
                if not retargeted:
                    # Reproduce the #3438 chronology exactly: mutate only after the
                    # first descriptor-bound policy check has accepted the safe link.
                    link.unlink()
                    link.symlink_to(external, target_is_directory=True)
                    retargeted = True

            acl_state: dict[int, str] = {}

            def fake_acl_listing(descriptor: int) -> str:
                return acl_state.get(descriptor, "")

            def fake_chmod_acl(descriptor: int, operation: str, acl: str) -> None:
                if operation == "+a":
                    acl_state[descriptor] = f"0: {acl}"
                elif operation == "-a":
                    acl_state[descriptor] = ""
                else:
                    raise AssertionError(f"unexpected ACL operation: {operation}")

            lease = helper._PrivateReadLease((subject,), repo)
            with (
                mock.patch.object(
                    helper,
                    "_validate_subject_symlinks_from_descriptor",
                    side_effect=validate_safe_then_retarget,
                ),
                mock.patch.object(helper, "_acl_listing", side_effect=fake_acl_listing),
                mock.patch.object(helper, "_chmod_acl", side_effect=fake_chmod_acl),
            ):
                with self.assertRaisesRegex(
                    helper.SelectedXcodeBuildOrchestratorError,
                    "symlink escaped|symlink target",
                ):
                    lease.grant("nembrapostvalidate")

            self.assertTrue(retargeted)
            self.assertGreaterEqual(validation_count, 2)
            self.assertFalse(lease._opened)
            self.assertEqual(lease._principal, "")
            self.assertTrue(all(not listing for listing in acl_state.values()))

    def test_source_revalidates_held_subject_policy_before_grant_returns(self) -> None:
        helper = load()
        grant = inspect.getsource(helper._PrivateReadLease.grant)
        revalidator = inspect.getsource(helper._revalidate_held_subject_symlink_policy)
        self.assertIn("_revalidate_held_subject_symlink_policy", grant)
        self.assertIn("_validate_subject_symlinks_from_descriptor", revalidator)
        self.assertIn("_descriptor_signature", revalidator)


if __name__ == "__main__":
    unittest.main(verbosity=2)
