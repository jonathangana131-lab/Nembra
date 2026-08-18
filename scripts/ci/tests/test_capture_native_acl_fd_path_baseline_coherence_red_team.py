#!/usr/bin/env python3
"""Exploit-positive oracle for unbound descriptor/path ACL rollback baselines."""

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
        "nembra_native_acl_fd_path_baseline_coherence_red_team", ORCHESTRATOR
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load selected-Xcode build orchestrator")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class CaptureNativeACLFDPathBaselineCoherenceRedTeamTests(unittest.TestCase):
    def test_mismatched_fd_baseline_is_restored_before_path_mismatch_is_detected(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-native-acl-baseline-coherence-") as temporary:
            repo = Path(temporary)
            subject = repo / "accepted-root"
            subject.mkdir()
            descriptor = os.open(subject, os.O_RDONLY)
            accepted_signature = helper._descriptor_signature(descriptor)

            # Model the dangerous split explicitly: descriptor-native acquisition
            # freezes ACL A while the canonical pathname says the admitted object
            # starts with ACL B. Accepted Darwin validation required these views to
            # be equal before grant; production currently carries no such gate.
            fd_baseline_acl = 0xA11
            canonical_before = "canonical-baseline-B"
            canonical_after_grant = "canonical-baseline-B + nembrabaselinecoherence"
            canonical_after_restore = "descriptor-baseline-A"
            path_listings = iter(
                (canonical_before, canonical_after_grant, canonical_after_restore)
            )
            restore_calls: list[tuple[int, int]] = []
            free_calls: list[int] = []

            def fake_path_acl_listing(*_args, **_kwargs) -> str:
                return next(path_listings)

            def fake_principal_present(listing: str, principal: str) -> bool:
                self.assertEqual(principal, "nembrabaselinecoherence")
                return listing == canonical_after_grant

            def fake_open_pinned_path(*_args, **_kwargs) -> int:
                return os.dup(descriptor)

            def fake_restore(held_descriptor: int, baseline_acl: int) -> None:
                restore_calls.append((held_descriptor, baseline_acl))

            def fake_free(baseline_acl: int) -> None:
                free_calls.append(baseline_acl)

            with (
                mock.patch.object(
                    helper,
                    "_lease_paths",
                    return_value=[(subject, False, accepted_signature, descriptor)],
                ),
                mock.patch.object(helper, "_validate_lease_subject_symlinks"),
                mock.patch.object(
                    helper,
                    "_capture_fd_acl_baseline",
                    return_value=fd_baseline_acl,
                ) as capture,
                mock.patch.object(
                    helper, "_path_acl_listing", side_effect=fake_path_acl_listing
                ) as path_listing,
                mock.patch.object(
                    helper, "_principal_already_present", side_effect=fake_principal_present
                ),
                mock.patch.object(helper, "_chmod_acl_path"),
                mock.patch.object(
                    helper, "_open_pinned_path", side_effect=fake_open_pinned_path
                ),
                mock.patch.object(
                    helper, "_restore_fd_acl_baseline", side_effect=fake_restore
                ),
                mock.patch.object(
                    helper, "_free_fd_acl_baseline", side_effect=fake_free
                ),
            ):
                lease = helper._PrivateReadLease(
                    (subject,), repo, use_native_darwin_acl=True
                )
                lease.grant("nembrabaselinecoherence")

                # Admission succeeds even though the descriptor rollback baseline
                # was never proven equivalent to the canonical pre-grant baseline.
                capture.assert_called_once_with(descriptor)
                self.assertEqual(restore_calls, [])

                # The first time production notices the disagreement is *after*
                # it has already applied descriptor ACL A to the held object.
                with self.assertRaisesRegex(
                    helper.SelectedXcodeBuildOrchestratorError,
                    "did not restore exact ACL listing",
                ):
                    lease.revoke()

            self.assertEqual(restore_calls, [(descriptor, fd_baseline_acl)])
            self.assertEqual(free_calls, [fd_baseline_acl])
            self.assertEqual(path_listing.call_count, 3)
            self.assertEqual(lease._opened, [])
            self.assertEqual(lease._principal, "")

        print(
            "NEMBRA_NATIVE_ACL_BASELINE_COHERENCE_GAP "
            "fdBaselineCaptured=true canonicalBaselineCaptured=true "
            "preGrantEqualityRequired=false mismatchedRestoreApplied=true "
            "mismatchDetectedOnlyAfterRestore=true"
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
