#!/usr/bin/env python3
"""Exploit-positive witness for inode-reuse ABA against planned lease identity."""

from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import tempfile
import time
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
ORCHESTRATOR = REPOSITORY / "scripts/ci/capture_selected_xcode_build_orchestrator.py"


def load():
    spec = importlib.util.spec_from_file_location(
        "nembra_private_read_lease_inode_aba_red_team", ORCHESTRATOR
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load selected-Xcode build orchestrator")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class CapturePrivateReadLeaseInodeABARedTeamTests(unittest.TestCase):
    def test_recycled_inode_replacement_matches_three_field_plan_signature(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-read-lease-inode-aba-") as temporary:
            root = Path(temporary)
            target = root / "accepted-directory"
            target.mkdir()

            accepted_signature = helper._path_signature(target)
            accepted_ctime_ns = target.stat().st_ctime_ns
            target.rmdir()

            # Make the replacement a distinct filesystem generation even on a fast
            # tmpfs/overlay runner, then search only for the exact three-field
            # (device, inode, type) identity production currently freezes.
            time.sleep(0.005)
            replacement_ctime_ns = None
            attempts = 0
            for attempts in range(1, 20001):
                target.mkdir()
                candidate_signature = helper._path_signature(target)
                candidate_ctime_ns = target.stat().st_ctime_ns
                if (
                    candidate_signature == accepted_signature
                    and candidate_ctime_ns != accepted_ctime_ns
                ):
                    replacement_ctime_ns = candidate_ctime_ns
                    break
                target.rmdir()
            else:
                self.fail(
                    "runner did not recycle the admitted directory inode within 20,000 attempts; "
                    "this witness requires a filesystem that demonstrates inode reuse"
                )

            self.assertIsNotNone(replacement_ctime_ns)
            self.assertNotEqual(replacement_ctime_ns, accepted_ctime_ns)
            self.assertEqual(helper._path_signature(target), accepted_signature)

            marker = target / "replacement.marker"
            marker.write_bytes(b"replacement-generation\n")

            # The production aa610e identity check accepts the replacement because
            # the frozen tuple does not carry a generation/change discriminator.
            descriptor = helper._open_pinned_path(target, True, accepted_signature)
            try:
                self.assertEqual(helper._descriptor_signature(descriptor), accepted_signature)
                marker_descriptor = os.open("replacement.marker", os.O_RDONLY, dir_fd=descriptor)
                try:
                    self.assertEqual(os.read(marker_descriptor, 128), b"replacement-generation\n")
                finally:
                    os.close(marker_descriptor)
            finally:
                os.close(descriptor)

            self.assertGreaterEqual(attempts, 1)


if __name__ == "__main__":
    unittest.main(verbosity=2)
