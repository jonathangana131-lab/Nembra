#!/usr/bin/env python3
"""Regression for field-installer private-device runner execution custody."""
from __future__ import annotations

from pathlib import Path
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
INSTALLER = REPOSITORY / "scripts/field/install_one_time_capture.command"

VULNERABLE_RUNNER_ASSIGNMENT = (
    'PRIVATE_DEVICE_RUNNER="$ROOT/scripts/ci/es80_signed_field_artifact_private_runner.py"'
)
VULNERABLE_PATH_IMPORT = 'spec = importlib.util.spec_from_file_location("nembra_private_device_reader", runner_path)'


class PrivateDeviceRunnerExecutionSubjectTests(unittest.TestCase):
    def installer_source(self) -> str:
        return INSTALLER.read_text(encoding="utf-8")

    def test_installer_must_not_reopen_private_device_authority_runner_by_mutable_checkout_path(self) -> None:
        source = self.installer_source()
        self.assertNotIn(VULNERABLE_RUNNER_ASSIGNMENT, source)
        self.assertNotIn(VULNERABLE_PATH_IMPORT, source)
        self.assertIn('PRIVATE_DEVICE_RUNNER_BLOB="$(/usr/bin/git rev-parse "$SOURCE_SHA:$PRIVATE_DEVICE_RUNNER_PATH"', source)
        self.assertIn('PRIVATE_DEVICE_RUNNER_BASE64="$(/usr/bin/git cat-file blob "$PRIVATE_DEVICE_RUNNER_BLOB"', source)
        self.assertIn('module.__file__ = "<es80_signed_field_artifact_private_runner.py:accepted-git-blob>"', source)
        self.assertIn('exec(compile(runner_bytes, module.__file__, "exec"), module.__dict__)', source)

    def test_runner_blob_identity_is_rechecked_inside_authority_interpreter(self) -> None:
        source = self.installer_source()
        self.assertIn('git_blob_payload = b"blob " + str(len(runner_bytes)).encode("ascii") + b"\\0" + runner_bytes', source)
        self.assertIn('actual_runner_blob = hashlib.sha1(git_blob_payload).hexdigest()', source)
        self.assertIn('hmac.compare_digest(actual_runner_blob, expected_runner_blob)', source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
