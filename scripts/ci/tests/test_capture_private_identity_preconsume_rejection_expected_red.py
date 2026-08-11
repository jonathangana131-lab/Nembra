#!/usr/bin/env python3
"""Expected-red: early destination rejection must sanitize admitted private residue."""
from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
WRITER_PATH = ROOT / "Scripts/provision_capture_tuya_identity_writer.py"
PREFIX = ".nembra-private-stage-"


def load_writer():
    spec = importlib.util.spec_from_file_location("nembra_private_identity_preconsume_rejection", WRITER_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("private identity writer import unavailable")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class PrivateIdentityPreconsumeRejectionTests(unittest.TestCase):
    def test_invalid_existing_output_rejection_sanitizes_admitted_residue(self) -> None:
        writer = load_writer()
        admitted_payload = b"credential-bearing-crash-residue-must-not-survive-rejection"
        new_payload = b"new-private-output"

        with tempfile.TemporaryDirectory(prefix="nembra-private-preconsume-reject-") as temporary:
            checkout = Path(temporary) / "repo"
            destination_parent = checkout / "private"
            destination_parent.mkdir(parents=True, mode=0o700)

            stage_name = f"{PREFIX}{os.getpid()}-{'c' * 24}"
            stage = checkout / stage_name
            stage.write_bytes(admitted_payload)
            stage.chmod(0o600)

            # A same-UID attacker can make the intended final name an invalid
            # replacement subject. The writer must reject it, but admission of
            # the old credential-bearing residue already gave us exact descriptor
            # authority to sanitize that residue without touching the attacker path.
            destination = destination_parent / "identity.swift"
            destination.mkdir(mode=0o700)

            checkout_fd = os.open(checkout, writer._directory_flags())
            destination_fd = os.open(destination_parent, writer._directory_flags())
            recovered = None
            try:
                recovered = writer._recover_private_stage_residue(checkout_fd)
                self.assertIsNotNone(recovered, "fixture did not admit the writer-shaped crash residue")

                with self.assertRaises(writer.ProvisionError):
                    writer._write_staged(
                        checkout_fd,
                        destination_fd,
                        "identity.swift",
                        "private/identity.swift",
                        new_payload,
                        recovered_stage=recovered,
                    )
            finally:
                if recovered is not None:
                    recovered.close()
                os.close(destination_fd)
                os.close(checkout_fd)

            self.assertTrue(destination.is_dir(), "failure cleanup mutated the invalid attacker destination")
            self.assertTrue(stage.is_file(), "admitted residue disappeared instead of remaining under held inode custody")
            self.assertEqual(
                stage.read_bytes(),
                b"",
                "early existing-output rejection left credential-bearing bytes in the exact admitted residue inode",
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)
