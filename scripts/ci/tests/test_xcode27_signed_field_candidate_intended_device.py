#!/usr/bin/env python3
from pathlib import Path
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "xcode27_signed_field_candidate.sh"
RUNNER = Path(__file__).resolve().parents[1] / "es80_signed_field_artifact_private_runner.py"


class SignedFieldCandidateIntendedDeviceSourceTests(unittest.TestCase):
    def test_intended_device_is_path_only_at_producer_boundary(self) -> None:
        source = SCRIPT.read_text(encoding="utf-8")

        self.assertIn(
            ': "${NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE:?Set NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE to a private mode-0600 file containing the intended field iPhone UDID for verification only.}"',
            source,
        )
        self.assertIn(
            '--validate-intended-device-udid-file "$INTENDED_DEVICE_UDID_FILE"',
            source,
        )
        self.assertIn(
            '--intended-device-udid-file "$INTENDED_DEVICE_UDID_FILE"',
            source,
        )
        self.assertNotIn('--intended-device-udid "$NEMBRA_INTENDED_FIELD_DEVICE_UDID"', source)
        self.assertNotIn('python3 - "$NEMBRA_INTENDED_FIELD_DEVICE_UDID"', source)
        self.assertNotIn('${NEMBRA_INTENDED_FIELD_DEVICE_UDID:?', source)

    def test_private_runner_keeps_raw_identifier_out_of_process_argv(self) -> None:
        source = RUNNER.read_text(encoding="utf-8")

        self.assertIn('os.O_NOFOLLOW', source)
        self.assertIn('metadata.st_mode & 0o077', source)
        self.assertIn('MAX_IDENTIFIER_BYTES = 128', source)
        self.assertIn('read_private_identifier(args.intended_device_udid_file)', source)
        self.assertIn('inspector.main(inspector_arguments)', source)
        self.assertIn('"--intended-device-udid",\n        intended_device_identifier,', source)
        self.assertIn('--validate-intended-device-udid-file', source)
        self.assertNotIn('os.environ[', source)
        self.assertNotIn('subprocess', source)


if __name__ == "__main__":
    unittest.main()
