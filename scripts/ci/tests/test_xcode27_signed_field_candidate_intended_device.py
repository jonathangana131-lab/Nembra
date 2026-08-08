#!/usr/bin/env python3
from pathlib import Path
import re
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "xcode27_signed_field_candidate.sh"
RUNNER = Path(__file__).resolve().parents[1] / "es80_signed_field_artifact_private_runner.py"


class SignedFieldCandidateIntendedDeviceSourceTests(unittest.TestCase):
    def test_intended_device_is_required_as_private_file_only(self) -> None:
        source = SCRIPT.read_text(encoding="utf-8")
        runner = RUNNER.read_text(encoding="utf-8")

        self.assertIn(
            ': "${NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE:?Set NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE to a private mode-0600 file containing the intended field iPhone UDID for verification only.}"',
            source,
        )
        self.assertIn('--validate-private-input', source)
        self.assertIn(
            '--intended-device-udid-file "$NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE"',
            source,
        )
        self.assertEqual(re.findall(r'\bNEMBRA_INTENDED_FIELD_DEVICE_UDID\b', source), [])
        self.assertNotIn('--intended-device-udid "$', source)
        self.assertNotIn('echo "$NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE"', source)
        self.assertNotIn('intended_device_udid=', source)
        self.assertNotIn('field_device_udid=', source)

        self.assertIn('os.O_NOFOLLOW', runner)
        self.assertIn('metadata.st_mode & 0o077', runner.replace('before.st_mode', 'metadata.st_mode'))
        self.assertIn('inspector.main(inspector_arguments)', runner)
        self.assertIn('"--intended-device-udid",\n        intended_device_identifier,', runner)
        self.assertNotIn('os.environ[', runner)


if __name__ == "__main__":
    unittest.main()
