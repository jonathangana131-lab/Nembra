#!/usr/bin/env python3
"""Exploit-positive witness for intermediate-component private read-lease races.

A full-path os.open(..., O_NOFOLLOW) protects only the final component. If an
intermediate directory is replaced after planning, production can descriptor-bind the
attacker-selected external target while its lstat/fstat identity comparison still passes.
SUCCESS in this diagnostic means the attacked production head remains RED.
"""

from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import tempfile
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
ORCHESTRATOR = REPOSITORY / "scripts/ci/capture_selected_xcode_build_orchestrator.py"


def _load_production():
    spec = importlib.util.spec_from_file_location("capture_selected_xcode_build_orchestrator", ORCHESTRATOR)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load production orchestrator")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class CapturePrivateReadLeaseIntermediateSymlinkRedTeam(unittest.TestCase):
    def test_final_component_nofollow_still_traverses_swapped_intermediate(self) -> None:
        production = _load_production()
        self.assertTrue(hasattr(production, "_open_lease_descriptor"))

        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            repository = root / "repo"
            trusted_sdk = repository / "LocalSecrets" / "TuyaSDK"
            trusted_build = trusted_sdk / "Build"
            external_sdk = root / "attacker-sdk"
            external_build = external_sdk / "Build"
            trusted_build.mkdir(parents=True)
            external_build.mkdir(parents=True)
            (trusted_build / "trusted.txt").write_text("trusted", encoding="utf-8")
            (external_build / "attacker.txt").write_text("attacker", encoding="utf-8")

            planned = production._lease_paths((trusted_build,), repository)
            self.assertTrue(any(path == trusted_build for path, _ in planned))

            parked = repository / "LocalSecrets" / "TuyaSDK.trusted"
            trusted_sdk.rename(parked)
            os.symlink(external_sdk, trusted_sdk, target_is_directory=True)

            descriptor = -1
            try:
                descriptor, is_directory = production._open_lease_descriptor(trusted_build, False)
                self.assertTrue(is_directory)
                opened = os.fstat(descriptor)
                external = external_build.stat()
                original = (parked / "Build").stat()
                self.assertEqual((opened.st_dev, opened.st_ino), (external.st_dev, external.st_ino))
                self.assertNotEqual((opened.st_dev, opened.st_ino), (original.st_dev, original.st_ino))
            finally:
                if descriptor >= 0:
                    os.close(descriptor)

    def test_current_source_uses_full_path_final_component_nofollow(self) -> None:
        source = ORCHESTRATOR.read_text(encoding="utf-8")
        self.assertIn("before = path.lstat()", source)
        self.assertIn("descriptor = os.open(path, flags)", source)
        self.assertIn('getattr(os, "O_NOFOLLOW", 0)', source)
        self.assertNotIn("dir_fd=", source)
        self.assertNotIn("os.open(component", source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
