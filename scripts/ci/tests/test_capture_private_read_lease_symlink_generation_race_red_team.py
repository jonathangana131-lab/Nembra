#!/usr/bin/env python3
"""Exploit-positive oracle for pathname-raced internal-symlink classification."""
from __future__ import annotations

import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest import mock

REPO = Path(__file__).resolve().parents[3]
HELPER = REPO / "scripts/ci/capture_selected_xcode_build_orchestrator.py"


def load():
    spec = importlib.util.spec_from_file_location("nembra_symlink_generation_race", HELPER)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load selected-Xcode orchestrator")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class CapturePrivateReadLeaseSymlinkGenerationRaceRedTeamTests(unittest.TestCase):
    def test_actual_grant_can_validate_internal_symlink_B_while_holding_external_symlink_A(self) -> None:
        helper = load()
        # Keep the synthetic repository beneath the checked-out repository rather than
        # the platform-default temporary root. On macOS, TemporaryDirectory() defaults
        # beneath /var/folders while /var is itself a compatibility symlink to
        # /private/var. Production's no-follow component walker correctly rejects that
        # unrelated host-path symlink before the generation-race seam can execute.
        # The checkout is already reached through the exact Actions path and gives this
        # portable witness an ordinary real-directory ancestry on both Linux and macOS.
        with tempfile.TemporaryDirectory(prefix="nembra-held-symlink-race-", dir=REPO) as raw:
            outer = Path(raw)
            repo = outer / "repo"
            subject = repo / "LocalSecrets/TuyaSDK/Build"
            subject.mkdir(parents=True)

            external = outer / "outside-subject"
            external.mkdir()
            (external / "outside.fixture").write_text("outside\n", encoding="utf-8")

            # Generation A is the tree that descriptor planning pins. Its symlink is
            # intentionally outside the admitted subject and must never qualify as an
            # accepted internal link.
            (subject / "escape").symlink_to(external, target_is_directory=True)
            accepted_hold = repo / "LocalSecrets/TuyaSDK/Build.accepted-hold"

            # Generation B exists only long enough for legacy pathname classification.
            # Its symlink is genuinely internal (self-referential to the subject root),
            # so the real production _validate_internal_symlink accepts it.
            replacement = outer / "replacement-build"
            replacement.mkdir()
            (replacement / "escape").symlink_to(".", target_is_directory=True)

            original_subject_entries = helper._subject_entries
            raced = False

            def classify_replacement_then_restore(
                path: Path,
                *,
                include_signatures: bool = False,
            ):
                nonlocal raced
                candidate = Path(path)
                if candidate != subject or raced:
                    return original_subject_entries(
                        candidate,
                        include_signatures=include_signatures,
                    )

                # _lease_paths has already admitted/held generation A's subject FD.
                # Swap only the subject pathname while _subject_entries performs its
                # symlink policy check, then restore A before descriptor coherence and
                # grant-time pathname diagnostics.
                subject.rename(accepted_hold)
                replacement.rename(subject)
                try:
                    entries = original_subject_entries(
                        subject,
                        include_signatures=include_signatures,
                    )
                finally:
                    subject.rename(replacement)
                    accepted_hold.rename(subject)
                raced = True
                return entries

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
                    "_subject_entries",
                    side_effect=classify_replacement_then_restore,
                ),
                mock.patch.object(helper, "_acl_listing", side_effect=fake_acl_listing),
                mock.patch.object(helper, "_chmod_acl", side_effect=fake_chmod_acl),
            ):
                # Exploit-positive success means production grant accepts descriptor
                # generation A even though A contains an external symlink; the policy
                # check was performed against temporary pathname generation B instead.
                lease.grant("nembrasymlinkrace")
                self.assertTrue(raced)
                self.assertTrue(lease._opened)
                self.assertEqual((subject / "escape").resolve(strict=True), external.resolve(strict=True))
                with self.assertRaises(ValueError):
                    (subject / "escape").resolve(strict=True).relative_to(subject.resolve(strict=True))
                lease.revoke()
                self.assertFalse(lease._opened)
                self.assertEqual(lease._principal, "")

    def test_source_symlink_policy_remains_pathname_resolve_based(self) -> None:
        helper = load()
        import inspect

        validator = inspect.getsource(helper._validate_internal_symlink)
        entries = inspect.getsource(helper._subject_entries)
        plan = inspect.getsource(helper._lease_paths)
        self.assertIn("link.resolve(strict=True)", validator)
        self.assertIn("subject.resolve(strict=True)", validator)
        self.assertIn("_validate_internal_symlink(candidate, subject)", entries)
        self.assertIn("_subject_entries(", plan)
        self.assertIn("include_descriptors", plan)


if __name__ == "__main__":
    unittest.main(verbosity=2)
