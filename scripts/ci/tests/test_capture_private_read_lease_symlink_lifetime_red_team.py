#!/usr/bin/env python3
"""Exploit-positive oracle for same-directory symlink replacement after held validation."""
from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

REPO = Path(__file__).resolve().parents[3]
HELPER = REPO / "scripts/ci/capture_selected_xcode_build_orchestrator.py"


def load():
    spec = importlib.util.spec_from_file_location("nembra_symlink_lifetime_redteam", HELPER)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load selected-Xcode orchestrator")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class CapturePrivateReadLeaseSymlinkLifetimeRedTeamTests(unittest.TestCase):
    def test_same_held_directory_can_replace_validated_internal_symlink_before_lease_returns(self) -> None:
        helper = load()
        temp_parent = Path("/private/tmp") if sys.platform == "darwin" else None
        kwargs = {"dir": temp_parent} if temp_parent is not None else {}
        with tempfile.TemporaryDirectory(prefix="nembra-symlink-lifetime-", **kwargs) as raw:
            outer = Path(raw)
            repo = outer / "repo"
            subject = repo / "LocalSecrets/TuyaSDK/Build"
            subject.mkdir(parents=True)
            internal = subject / "Internal"
            internal.mkdir()
            (internal / "accepted.fixture").write_text("accepted\n", encoding="utf-8")

            external = outer / "outside-subject"
            external.mkdir()
            (external / "outside.fixture").write_text("outside\n", encoding="utf-8")

            link = subject / "escape"
            link.symlink_to("Internal", target_is_directory=True)

            original_validator = helper._validate_subject_symlinks_from_descriptor
            raced = False

            def validate_then_replace(path: Path, descriptor: int) -> None:
                nonlocal raced
                original_validator(path, descriptor)
                # The parent directory descriptor is still the exact generation that
                # production holds. Replacing one directory entry does not replace that
                # directory inode. The current plan stores no identity for symlink
                # objects, so mutate the admitted link only after descriptor-bound
                # validation has accepted its internal target.
                link.unlink()
                link.symlink_to(external, target_is_directory=True)
                raced = True

            plan = ()
            try:
                with mock.patch.object(
                    helper,
                    "_validate_subject_symlinks_from_descriptor",
                    side_effect=validate_then_replace,
                ):
                    plan = helper._lease_paths(
                        (subject,),
                        repo,
                        include_descriptors=True,
                    )

                # Exploit-positive success means planning returned a coherent held
                # descriptor lease after the live symlink had already escaped the
                # admitted subject. A later pathname consumer can therefore traverse
                # bytes that were not the symlink target admitted by the policy check.
                self.assertTrue(raced)
                self.assertTrue(plan)
                self.assertTrue(link.is_symlink())
                self.assertEqual(link.resolve(strict=True), external.resolve(strict=True))
                self.assertEqual(
                    (link / "outside.fixture").read_text(encoding="utf-8"),
                    "outside\n",
                )
                with self.assertRaises(ValueError):
                    link.resolve(strict=True).relative_to(subject.resolve(strict=True))
            finally:
                for entry in reversed(plan):
                    if len(entry) != 4:
                        continue
                    try:
                        os.close(int(entry[3]))
                    except OSError:
                        pass


if __name__ == "__main__":
    unittest.main(verbosity=2)
