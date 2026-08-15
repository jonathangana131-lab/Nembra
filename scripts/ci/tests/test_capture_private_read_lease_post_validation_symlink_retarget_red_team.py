#!/usr/bin/env python3
"""Exploit-positive oracle for post-validation held-directory symlink retargeting."""
from __future__ import annotations

import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest import mock

REPO = Path(__file__).resolve().parents[3]
HELPER = REPO / "scripts/ci/capture_selected_xcode_build_orchestrator.py"


def load():
    spec = importlib.util.spec_from_file_location("nembra_post_validation_symlink_retarget", HELPER)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load selected-Xcode orchestrator")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class CapturePrivateReadLeasePostValidationSymlinkRetargetRedTeamTests(unittest.TestCase):
    def test_grant_can_accept_symlink_retargeted_after_descriptor_bound_validation(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(
            prefix="nembra-post-validate-symlink-retarget-current-",
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
            retargeted = False

            def validate_safe_then_retarget(admitted_subject: Path, subject_descriptor: int) -> None:
                nonlocal retargeted
                original_validator(admitted_subject, subject_descriptor)
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
                lease.grant("nembrapostvalidate")
                self.assertTrue(retargeted)
                self.assertTrue(lease._opened)
                self.assertEqual(link.resolve(strict=True), external.resolve(strict=True))
                with self.assertRaises(ValueError):
                    link.resolve(strict=True).relative_to(subject.resolve(strict=True))
                lease.revoke()
                self.assertFalse(lease._opened)
                self.assertEqual(lease._principal, "")

    def test_current_product_still_has_no_symlink_identity_in_final_descriptor_verification(self) -> None:
        helper = load()
        import inspect

        lease_paths = inspect.getsource(helper._lease_paths)
        validator = inspect.getsource(helper._validate_subject_symlinks_from_descriptor)
        verifier = inspect.getsource(helper._verify_descriptor_plan)
        self.assertIn("_validate_subject_symlinks_from_descriptor", lease_paths)
        self.assertIn("stat.S_ISLNK", validator)
        self.assertIn("continue", validator)
        self.assertNotIn("readlink", verifier)
        self.assertNotIn("S_ISLNK", verifier)


if __name__ == "__main__":
    unittest.main(verbosity=2)
