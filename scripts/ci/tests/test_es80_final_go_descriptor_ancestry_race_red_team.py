#!/usr/bin/env python3
"""Expected-red witness for Final-GO descriptor ancestry namespace rebinding."""
from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
PRIVATE = ROOT / "scripts/ci/es80_authenticated_stationary_private_review_final_go.py"
SPEC = importlib.util.spec_from_file_location("nembra_final_go_descriptor_ancestry_redteam", PRIVATE)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load current Final-GO candidate authority")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class FinalGoDescriptorAncestryRedTeamTests(unittest.TestCase):
    def test_parent_directory_namespace_swap_during_read_is_rejected(self) -> None:
        accepted_payload = b"accepted-final-go-source\n"
        attacker_payload = b"attacker-live-candidate-source\n"
        with tempfile.TemporaryDirectory(prefix="nembra-final-go-ancestry-race-") as temporary:
            root = Path(temporary).resolve(strict=True)
            relative = "NembraApp/App/Capture.swift"
            live_parent = root / "NembraApp/App"
            detached_parent = root / "NembraApp/App.accepted"
            path = live_parent / "Capture.swift"
            live_parent.mkdir(parents=True)
            path.write_bytes(accepted_payload)
            path.chmod(0o644)
            accepted_identity = path.stat()

            original_read = MODULE.os.read
            attack_fired = False

            def interpose_read(descriptor: int, count: int) -> bytes:
                nonlocal attack_fired
                payload = original_read(descriptor, count)
                metadata = os.fstat(descriptor)
                if (
                    not attack_fired
                    and metadata.st_dev == accepted_identity.st_dev
                    and metadata.st_ino == accepted_identity.st_ino
                ):
                    attack_fired = True
                    os.rename(live_parent, detached_parent)
                    live_parent.mkdir()
                    replacement = live_parent / "Capture.swift"
                    replacement.write_bytes(attacker_payload)
                    replacement.chmod(0o644)
                return payload

            MODULE.os.read = interpose_read
            try:
                with self.assertRaises(
                    RuntimeError,
                    msg=(
                        "Final-GO admitted bytes from a detached accepted parent-directory FD "
                        "after the live candidate ancestry was replaced"
                    ),
                ):
                    MODULE._read_physical_payload(root, relative, b"100644")
            finally:
                MODULE.os.read = original_read

            self.assertTrue(attack_fired, "fixture never replaced the live parent directory")
            self.assertEqual((detached_parent / "Capture.swift").read_bytes(), accepted_payload)
            self.assertEqual(path.read_bytes(), attacker_payload)


if __name__ == "__main__":
    unittest.main(verbosity=2)
