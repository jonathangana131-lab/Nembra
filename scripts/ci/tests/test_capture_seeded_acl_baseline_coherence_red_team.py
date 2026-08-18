#!/usr/bin/env python3
"""Exploit-positive classifier for missing native fd/path ACL baseline coherence."""

from __future__ import annotations

import importlib.util
from pathlib import Path
import unittest
from unittest import mock

REPOSITORY = Path(__file__).resolve().parents[3]
ORCHESTRATOR = REPOSITORY / "scripts/ci/capture_selected_xcode_build_orchestrator.py"


def load():
    spec = importlib.util.spec_from_file_location(
        "nembra_seeded_acl_baseline_coherence_red_team", ORCHESTRATOR
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load selected-Xcode build orchestrator")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class CaptureSeededACLBaselineCoherenceRedTeamTests(unittest.TestCase):
    def test_native_grant_never_compares_seeded_fd_baseline_to_path_native_baseline(self) -> None:
        helper = load()
        principal = "nembrabuildfixture"
        subject = Path("/private/tmp/nembra-seeded-acl-baseline")
        descriptor = 73
        accepted_signature = (501, 777, helper.stat.S_IFDIR | 0o700)

        # Model a real non-empty descriptor ACL baseline. A canonical pathname
        # native ACL is also available and intentionally different, but current
        # production never asks for it before creating temporary authority.
        library = mock.Mock()
        library.acl_get_fd.return_value = 0x1111
        library.acl_dup.return_value = 0x2222
        library.acl_get_file.return_value = 0x3333
        library.acl_to_text.return_value = b"path-baseline-differs"

        before_listing = "drwx------ 1 root wheel 0 Aug 17 00:00 nembra-seeded-acl-baseline\n"
        after_listing = (
            before_listing
            + f" 0: user:{principal} allow list,search,readattr,readextattr,readsecurity\n"
        )

        with (
            mock.patch.object(helper, "_darwin_acl_library", return_value=library),
            mock.patch.object(
                helper,
                "_lease_paths",
                return_value=[(subject, False, accepted_signature, descriptor)],
            ),
            mock.patch.object(helper, "_validate_lease_subject_symlinks"),
            mock.patch.object(
                helper,
                "_path_acl_listing",
                side_effect=[before_listing, after_listing],
            ),
            mock.patch.object(helper, "_chmod_acl_path"),
            mock.patch.object(
                helper, "_descriptor_signature", return_value=accepted_signature
            ),
            mock.patch.object(helper, "_open_pinned_path", return_value=91),
            mock.patch.object(helper.os, "close"),
        ):
            lease = helper._PrivateReadLease(
                (subject,),
                subject,
                use_native_darwin_acl=True,
            )
            lease.grant(principal)

        self.assertEqual(len(lease._opened), 1)
        self.assertEqual(lease._opened[0]["native_baseline_acl"], 0x2222)
        library.acl_get_fd.assert_called_once_with(descriptor)
        library.acl_dup.assert_called_once()

        # Accepted #3555/#3550 seeded-baseline semantics require a canonical
        # pathname native acquisition + canonical comparison before grant. The
        # attacked product succeeds without either call.
        library.acl_get_file.assert_not_called()
        library.acl_to_text.assert_not_called()

        print(
            "NEMBRA_SEEDED_ACL_BASELINE_COHERENCE_GAP "
            "fdBaselineCaptured=true pathNativeBaselineAcquired=false "
            "nativeSemanticEqualityProven=false grantReturned=true"
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
