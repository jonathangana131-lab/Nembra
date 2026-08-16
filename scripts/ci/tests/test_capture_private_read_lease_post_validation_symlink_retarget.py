#!/usr/bin/env python3
"""Regression for symlink retargeting after descriptor-bound lease validation."""
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


class CapturePrivateReadLeasePostValidationSymlinkRetargetTests(unittest.TestCase):
    def test_grant_revalidates_symlinks_after_acl_materialization(self) -> None:
        helper = load()
        # Keep the synthetic repository beneath the checkout so Darwin does not
        # encounter the unrelated /var -> /private/var compatibility symlink.
        with tempfile.TemporaryDirectory(
            prefix="nembra-post-validate-symlink-retarget-",
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
            validation_calls = 0

            def validate_safe_then_retarget(
                admitted_subject: Path,
                subject_descriptor: int,
            ) -> None:
                nonlocal validation_calls
                validation_calls += 1
                original_validator(admitted_subject, subject_descriptor)
                if validation_calls == 1:
                    # The initial descriptor-bound classification accepted the safe
                    # link. Retarget only the mutable symlink object before ACL grant
                    # finishes. The final authority-handoff validation must reject it.
                    link.unlink()
                    link.symlink_to(external, target_is_directory=True)

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
                with self.assertRaises(helper.SelectedXcodeBuildOrchestratorError):
                    lease.grant("nembrapostvalidate")

            self.assertGreaterEqual(validation_calls, 2)
            self.assertFalse(lease._opened)
            self.assertEqual(lease._principal, "")
            self.assertTrue(acl_state)
            self.assertTrue(all(value == "" for value in acl_state.values()))
            self.assertEqual(link.resolve(strict=True), external.resolve(strict=True))

    def test_grant_source_contains_final_descriptor_bound_symlink_recheck(self) -> None:
        helper = load()
        grant_source = inspect.getsource(helper._PrivateReadLease.grant)
        self.assertIn("_validate_subject_symlinks_from_descriptor", grant_source)
        self.assertIn("self._subjects", grant_source)
        self.assertIn("accepted private read-lease subject", grant_source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
