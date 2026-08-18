#!/usr/bin/env python3
"""Exploit-positive classifier for missing fd/path native ACL baseline coherence."""

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
        "nembra_native_acl_baseline_coherence_red_team", ORCHESTRATOR
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load selected-Xcode build orchestrator")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class CaptureNativeACLBaselineCoherenceRedTeamTests(unittest.TestCase):
    def test_seeded_fd_baseline_can_diverge_from_path_baseline_and_grant_still_succeeds(self) -> None:
        helper = load()
        source = ORCHESTRATOR.read_text()
        native_helpers = source[
            source.index("def _darwin_acl_library") : source.index("def _principal_already_present")
        ]
        grant_body = source[source.index("    def grant(self, principal: str)") : source.index("    def revoke(")]

        self.assertIn("acl_get_fd", native_helpers)
        self.assertNotIn("acl_get_file", native_helpers)
        self.assertNotIn("acl_to_text", native_helpers)
        self.assertIn("_capture_fd_acl_baseline(descriptor)", grant_body)
        self.assertNotIn("acl_get_file", grant_body)
        self.assertNotIn("acl_to_text", grant_body)

        with tempfile.TemporaryDirectory(prefix="nembra-native-acl-coherence-redteam-") as temporary:
            repo = Path(temporary) / "repo"
            repo.mkdir()
            subject = repo / "accepted-root"
            subject.mkdir()
            descriptor = os.open(subject, os.O_RDONLY)
            signature = helper._descriptor_signature(descriptor)
            lease = helper._PrivateReadLease((subject,), repo, use_native_darwin_acl=True)

            path_listings = iter(
                (
                    "",
                    " 0: user:nembrabuildcoherence allow list,search,readattr,readextattr,readsecurity\n",
                    "",
                )
            )
            grant_calls: list[Path] = []
            restore_calls: list[tuple[int, int]] = []

            with (
                mock.patch.object(
                    helper,
                    "_lease_paths",
                    return_value=((subject, False, signature, descriptor),),
                ),
                mock.patch.object(helper, "_validate_lease_subject_symlinks"),
                mock.patch.object(helper, "_capture_fd_acl_baseline", return_value=0xBEEF) as capture,
                mock.patch.object(
                    helper,
                    "_path_acl_listing",
                    side_effect=lambda *_args: next(path_listings),
                ),
                mock.patch.object(
                    helper,
                    "_chmod_acl_path",
                    side_effect=lambda path, *_args: grant_calls.append(path),
                ),
                mock.patch.object(
                    helper,
                    "_restore_fd_acl_baseline",
                    side_effect=lambda fd, baseline: restore_calls.append((fd, baseline)),
                ),
                mock.patch.object(helper, "_free_fd_acl_baseline"),
            ):
                lease.grant("nembrabuildcoherence")
                self.assertEqual(grant_calls, [subject])
                lease.revoke()

            capture.assert_called_once_with(descriptor)
            self.assertEqual(restore_calls, [(descriptor, 0xBEEF)])
            self.assertEqual(lease._opened, [])
            self.assertEqual(lease._principal, "")

        print(
            "NEMBRA_NATIVE_ACL_BASELINE_COHERENCE_GAP "
            "fdBaselineSeeded=true canonicalPathBaselineEmpty=true "
            "nativeSemanticComparisonAbsent=true canonicalPathGrantStillSucceeded=true"
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
