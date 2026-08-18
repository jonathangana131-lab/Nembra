#!/usr/bin/env python3
"""Exploit-positive oracle for native seeded ACL baseline coherence.

SUCCESS means the attacked production lease can grant strict accepted-root authority
while the descriptor-retained rollback baseline has never been semantically tied
to the canonical-path pre-grant ACL. This is validation evidence only.
"""

from __future__ import annotations

import importlib.util
import inspect
import os
from pathlib import Path
import tempfile
import unittest
from unittest import mock

REPOSITORY = Path(__file__).resolve().parents[3]
ORCHESTRATOR = REPOSITORY / "scripts/ci/capture_selected_xcode_build_orchestrator.py"


def load():
    spec = importlib.util.spec_from_file_location(
        "nembra_native_acl_seeded_baseline_equivalence_red_team", ORCHESTRATOR
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load selected-Xcode build orchestrator")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class CaptureNativeACLSeededBaselineEquivalenceRedTeam(unittest.TestCase):
    def test_strict_native_grant_accepts_unrelated_fd_baseline_handle(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-native-seeded-equivalence-") as temporary:
            outer = Path(temporary)
            outer.chmod(0o711)
            repo = outer / "repo"
            repo.mkdir(mode=0o755)
            subject = repo / "accepted-root.fixture"
            subject.write_bytes(b"fixture\n")

            descriptor = os.open(subject, os.O_RDONLY)
            signature = helper._descriptor_signature(descriptor)
            lease = helper._PrivateReadLease(
                (subject,), repo, use_native_darwin_acl=True
            )

            # Model a seeded canonical-path baseline. The retained descriptor ACL
            # handle below is intentionally opaque/unrelated. Production currently
            # has no semantic comparison that can reject this contradiction.
            canonical_before = " 0: user:root allow readattr\n"
            canonical_after = (
                canonical_before
                + " 1: user:nembrabuildcoherence allow read,readattr,readextattr,readsecurity\n"
            )
            listings = iter((canonical_before, canonical_after, canonical_before))
            events: list[tuple[str, int]] = []

            with (
                mock.patch.object(
                    helper,
                    "_lease_paths",
                    return_value=((subject, False, signature, descriptor),),
                ),
                mock.patch.object(helper, "_validate_lease_subject_symlinks"),
                mock.patch.object(
                    helper,
                    "_capture_fd_acl_baseline",
                    return_value=0x4242,
                ) as capture,
                mock.patch.object(
                    helper,
                    "_path_acl_listing",
                    side_effect=lambda *_args: next(listings),
                ) as path_listing,
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
            ):
                # Exploit-positive condition: admission succeeds even though the
                # opaque fd rollback baseline was never compared to canonical_before.
                lease.grant("nembrabuildcoherence")
                self.assertEqual(len(lease._opened), 1)
                self.assertEqual(lease._opened[0]["native_baseline_acl"], 0x4242)
                self.assertEqual(lease._opened[0]["before"], canonical_before)
                lease.revoke()

            capture.assert_called_once_with(descriptor)
            grant.assert_called_once()
            self.assertEqual(path_listing.call_count, 3)
            restore.assert_called_once_with(descriptor, 0x4242)
            free.assert_called_once_with(0x4242)
            self.assertEqual(events, [("restore", 0x4242), ("free", 0x4242)])
            self.assertEqual(lease._opened, [])
            self.assertEqual(lease._principal, "")

    def test_native_transport_has_no_canonical_path_acl_semantic_acquisition(self) -> None:
        helper = load()
        library_source = inspect.getsource(helper._darwin_acl_library)
        grant_source = inspect.getsource(helper._PrivateReadLease.grant)

        self.assertIn("acl_get_fd", library_source)
        self.assertNotIn("acl_get_file", library_source)
        self.assertIn("_capture_fd_acl_baseline(descriptor)", grant_source)
        self.assertIn("_path_acl_listing(", grant_source)
        self.assertNotIn("acl_get_file", grant_source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
