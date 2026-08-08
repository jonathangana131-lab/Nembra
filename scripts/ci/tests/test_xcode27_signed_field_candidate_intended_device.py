#!/usr/bin/env python3
from pathlib import Path
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "xcode27_signed_field_candidate.sh"
PRIVATE_RUNNER = Path(__file__).resolve().parents[1] / "es80_signed_field_artifact_private_runner.py"


class SignedFieldCandidateIntendedDeviceSourceTests(unittest.TestCase):
    def test_intended_device_is_required_through_private_path_only_input(self) -> None:
        source = SCRIPT.read_text(encoding="utf-8")
        runner = PRIVATE_RUNNER.read_text(encoding="utf-8")

        self.assertIn(
            ': "${NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE:?Set NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE to an absolute private mode-0600 file containing the verification-only intended field iPhone UDID.}"',
            source,
        )
        self.assertIn('es80_signed_field_artifact_private_runner.py', source)
        self.assertIn('--validate-private-input-only', source)
        self.assertIn(
            '--intended-device-udid-file "$NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE"',
            source,
        )
        self.assertIn('unset NEMBRA_INTENDED_FIELD_DEVICE_UDID || true', source)
        self.assertIn('unset NEMBRA_FIELD_DEVICE_UDID || true', source)
        self.assertLess(
            source.index('unset NEMBRA_INTENDED_FIELD_DEVICE_UDID || true'),
            source.index('run_xcodebuild()'),
        )
        self.assertLess(
            source.index('unset NEMBRA_FIELD_DEVICE_UDID || true'),
            source.index('run_xcodebuild()'),
        )
        self.assertNotIn('NEMBRA_INTENDED_FIELD_DEVICE_UDID:?Set', source)
        self.assertNotIn('python3 - "$NEMBRA_INTENDED_FIELD_DEVICE_UDID"', source)
        self.assertNotIn('--intended-device-udid "$NEMBRA_INTENDED_FIELD_DEVICE_UDID"', source)

        self.assertIn('os.O_NOFOLLOW', runner)
        self.assertIn('os.open not in os.supports_dir_fd', runner)
        self.assertIn('dir_fd=parent_descriptor', runner)
        self.assertIn('os.fstat(descriptor)', runner)
        self.assertIn('metadata.st_uid != os.geteuid()', runner)
        self.assertIn('metadata.st_nlink != 1', runner)
        self.assertIn('metadata.st_mode & 0o077', runner)
        self.assertIn('value in os.fspath(path)', runner)
        self.assertIn('inspector.main(inspector_arguments)', runner)
        self.assertNotIn('subprocess', runner)
        self.assertNotIn('os.environ', runner)

        self.assertNotIn('intended_device_udid=', source)
        self.assertNotIn('field_device_udid=', source)
        self.assertNotIn('echo "$NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE"', source)
        self.assertNotIn('ARTIFACTS_DIR="$NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE', source)
        self.assertNotIn('BUILD_INSTANCE_ID="$NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE', source)


if __name__ == "__main__":
    unittest.main()
