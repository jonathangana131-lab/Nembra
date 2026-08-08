#!/usr/bin/env python3
from pathlib import Path
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "xcode27_signed_field_candidate.sh"


class SignedFieldCandidateIntendedDeviceSourceTests(unittest.TestCase):
    def test_intended_device_is_required_as_private_path_and_used_only_for_verification(self) -> None:
        source = SCRIPT.read_text(encoding="utf-8")

        self.assertIn(
            ': "${NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE:?Set NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE to an absolute path naming a private mode-0600 file containing the intended field iPhone UDID for verification only.}"',
            source,
        )
        self.assertIn(
            '--validate-only',
            source,
            "Validate the private verification-input file before spending a signed archive/export cycle.",
        )
        self.assertIn(
            '--intended-device-udid-file "$NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE"',
            source,
        )
        self.assertIn('es80_signed_field_artifact_private_runner.py', source)

        # The raw intended device identifier is private admission input. It must not be accepted in
        # an environment variable or forwarded through a child process argv. Only its private file
        # path may cross those OS-visible boundaries.
        self.assertNotIn(': "${NEMBRA_INTENDED_FIELD_DEVICE_UDID:?', source)
        self.assertNotIn('python3 - "$NEMBRA_INTENDED_FIELD_DEVICE_UDID"', source)
        self.assertNotIn('--intended-device-udid "$NEMBRA_INTENDED_FIELD_DEVICE_UDID"', source)
        self.assertNotIn('intended_device_udid=', source)
        self.assertNotIn('field_device_udid=', source)
        self.assertNotIn('echo "$NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE"', source)
        self.assertNotIn('ARTIFACTS_DIR="$NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE', source)
        self.assertNotIn('BUILD_INSTANCE_ID="$NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE', source)


if __name__ == "__main__":
    unittest.main()
