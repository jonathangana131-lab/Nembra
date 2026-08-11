#!/usr/bin/env python3
"""Expected-red regression for Final-GO lstat-to-read pathname replacement."""
from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import stat
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
PRIVATE = ROOT / "scripts/ci/es80_authenticated_stationary_private_review_final_go.py"


def load_module():
    spec = importlib.util.spec_from_file_location("nembra_final_go_physical_payload_race", PRIVATE)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load current Final-GO candidate authority")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class FinalGoPhysicalPayloadReadRaceTests(unittest.TestCase):
    def test_regular_file_replacement_between_lstat_and_read_is_rejected(self) -> None:
        module = load_module()
        accepted_payload = b"accepted-final-go-source\n"
        replacement_payload = b"replacement-must-not-be-admitted\n"

        with tempfile.TemporaryDirectory(prefix="nembra-final-go-physical-read-race-") as temporary:
            root = Path(temporary)
            relative = "NembraApp/App/Capture.swift"
            path = root / relative
            escaped = root / "NembraApp/App/Capture.accepted.swift"
            path.parent.mkdir(parents=True)
            path.write_bytes(accepted_payload)
            path.chmod(0o644)

            admitted = os.lstat(path)
            self.assertTrue(stat.S_ISREG(admitted.st_mode))

            original_read_bytes = Path.read_bytes
            attack_fired = False

            def interpose_read_bytes(subject: Path):
                nonlocal attack_fired
                if subject == path and not attack_fired:
                    attack_fired = True
                    os.rename(path, escaped)
                    replacement_fd = os.open(
                        path,
                        os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_CLOEXEC", 0),
                        0o644,
                    )
                    try:
                        os.write(replacement_fd, replacement_payload)
                        os.fsync(replacement_fd)
                    finally:
                        os.close(replacement_fd)
                return original_read_bytes(subject)

            Path.read_bytes = interpose_read_bytes
            try:
                with self.assertRaises(
                    RuntimeError,
                    msg="Final-GO admitted bytes from a replacement inode reopened after lstat",
                ):
                    module._read_physical_payload(root, relative, b"100644")
            finally:
                Path.read_bytes = original_read_bytes

            self.assertTrue(attack_fired, "fixture did not interpose at the pathname reopen boundary")
            self.assertEqual(escaped.read_bytes(), accepted_payload)
            self.assertEqual(path.read_bytes(), replacement_payload)


if __name__ == "__main__":
    unittest.main(verbosity=2)
